"""
Orquestador del dominio Solar: corre silver y gold de las 15 tablas solares (dimensiones y
hechos cuyo Bronze deposita un proceso externo en stg) y luego el monitor de alertas.

Los grupos son independientes entre si (un proveedor que falla no bloquea a los demas);
dentro de un grupo, cada paso depende del anterior (dispositivos <- planta/estacion,
hechos <- dispositivos), asi que ante el primer error se detiene ese grupo.

Uso:
    python db/scheduler/run_solar.py --env-file .env.prod                 # corrida normal (la que programa el Programador de tareas)
    python db/scheduler/run_solar.py --env-file .env.prod --solo sma meteo # solo esos grupos
    python db/scheduler/run_solar.py --dry-run                            # muestra el plan y verifica que existan los scripts

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_solar_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_solar.lock para no solaparse. Las alertas salen por los canales ALERT_* del .env
(ver db/monitor_etl.py). Las cargas de dimPlanGeneracion, geografia y AS400 NO forman parte de esta corrida.
"""
import argparse
import datetime
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ETL = ROOT / "db" / "etl"
MONITOR = ROOT / "db" / "monitor_etl.py"
LOG_DIR_DEFECTO = ROOT / "logs"

RETENCION_DIAS = 30
BLOQUEO_VENCE_HORAS = 2
TIMEOUT_PASO_DEFECTO = 900
HORAS_SIN_EXITO = 16
SIN_REPETIR_HORAS = 12

# Prefijos de los procesos solares en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["Sma", "Huawei", "Soliscloud", "Growatt", "Meteo", "DeviceCapacity", "GhiPlan", "GsaMonthly"]

# grupo -> [(carpeta, script silver, script gold)] en orden de dependencia.
GRUPOS = {
    "sma": [
        ("dimSmaPlants", "load_silver_dim_sma_plants.py", "load_gold_dim_sma_plants.py"),
        ("dimSmaDevices", "load_silver_dim_sma_devices.py", "load_gold_dim_sma_devices.py"),
        ("factSmaPowerPlanta", "load_silver_fact_sma_power_planta.py", "load_gold_fact_sma_power_planta.py"),
        ("factSmaPower15Minutes", "load_silver_fact_sma_power_15minutes.py", "load_gold_fact_sma_power_15minutes.py"),
    ],
    "huawei": [
        ("dimHuaweiStations", "load_silver_dim_huawei_stations.py", "load_gold_dim_huawei_stations.py"),
        ("dimHuaweiDevices", "load_silver_dim_huawei_devices.py", "load_gold_dim_huawei_devices.py"),
        ("factHuaweiEnergyAndPowerPv", "load_silver_fact_huawei_energy_and_power_pv.py", "load_gold_fact_huawei_energy_and_power_pv.py"),
    ],
    "soliscloud": [
        ("dimSoliscloudStations", "load_silver_dim_soliscloud_stations.py", "load_gold_dim_soliscloud_stations.py"),
        ("dimSoliscloudDevices", "load_silver_dim_soliscloud_devices.py", "load_gold_dim_soliscloud_devices.py"),
        ("factSoliscloudEnergyAndPowerPv", "load_silver_fact_soliscloud_energy_and_power_pv.py", "load_gold_fact_soliscloud_energy_and_power_pv.py"),
    ],
    "growatt": [
        ("factGrowattEnergyAndPowerPv", "load_silver_fact_growatt_energy_and_power_pv.py", "load_gold_fact_growatt_energy_and_power_pv.py"),
    ],
    "meteo": [
        ("factMeteoDaily", "load_silver_fact_meteo_daily.py", "load_gold_fact_meteo_daily.py"),
    ],
    "referencia": [
        ("dimDeviceCapacity", "load_silver_dim_device_capacity.py", "load_gold_dim_device_capacity.py"),
        ("dimGhiPlanDaily", "load_silver_dim_ghi_plan_daily.py", "load_gold_dim_ghi_plan_daily.py"),
        ("dimGsaMonthlyReference", "load_silver_dim_gsa_monthly_reference.py", "load_gold_dim_gsa_monthly_reference.py"),
    ],
}


def pasos_del_grupo(grupo: str) -> list:
    """[(etiqueta, ruta_script)] en orden silver -> gold por tabla."""
    salida = []
    for carpeta, silver, gold in GRUPOS[grupo]:
        salida.append((f"{carpeta} silver", ETL / carpeta / silver))
        salida.append((f"{carpeta} gold", ETL / carpeta / gold))
    return salida


# --- Registro ------------------------------------------------------------------

class Registro:
    """Escribe a consola y, si hay archivo, al log de la corrida."""

    def __init__(self, ruta: Path = None):
        self.ruta = ruta
        if ruta:
            ruta.parent.mkdir(parents=True, exist_ok=True)

    def __call__(self, texto: str = "") -> None:
        print(texto, flush=True)
        if self.ruta:
            with open(self.ruta, "a", encoding="utf-8") as f:
                f.write(texto + "\n")


def purgar_logs(log_dir: Path, dias: int) -> int:
    limite = time.time() - dias * 86400
    n = 0
    for f in log_dir.glob("run_solar_*.log"):
        if f.stat().st_mtime < limite:
            f.unlink()
            n += 1
    return n


# --- Bloqueo anti-solapamiento ------------------------------------------------

def tomar_bloqueo(ruta: Path) -> bool:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(2):
        try:
            fd = os.open(ruta, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            with os.fdopen(fd, "w") as f:
                f.write(f"pid={os.getpid()} inicio={datetime.datetime.now().isoformat(timespec='seconds')}\n")
            return True
        except FileExistsError:
            edad_h = (time.time() - ruta.stat().st_mtime) / 3600
            if edad_h < BLOQUEO_VENCE_HORAS:
                return False
            ruta.unlink(missing_ok=True)  # bloqueo vencido (corrida caida)
    return False


def liberar_bloqueo(ruta: Path) -> None:
    ruta.unlink(missing_ok=True)


# --- Ejecucion -----------------------------------------------------------------

def ejecutar_subproceso(cmd: list, timeout: int) -> tuple:
    """Devuelve (codigo, salida, segundos). Codigo -9 si vencio el tiempo."""
    inicio = time.time()
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=timeout, cwd=ROOT, env=env)
        return r.returncode, (r.stdout or "") + (r.stderr or ""), time.time() - inicio
    except subprocess.TimeoutExpired as exc:
        salida = ((exc.stdout or b"").decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or ""))
        return -9, salida + f"\nTIEMPO AGOTADO ({timeout}s)", time.time() - inicio


def correr(grupos: list, env_file: str, log: Registro, timeout_paso: int = TIMEOUT_PASO_DEFECTO, ejecutor=ejecutar_subproceso,
           pasos_por_grupo=pasos_del_grupo) -> list:
    """Corre los grupos en orden. Un fallo detiene SOLO su grupo. Devuelve una fila por paso."""
    resultados = []
    for grupo in grupos:
        log(f"\n##### Grupo {grupo} #####")
        fallo_previo = False
        for etiqueta, script in pasos_por_grupo(grupo):
            if fallo_previo:
                resultados.append({"grupo": grupo, "paso": etiqueta, "estado": "OMITIDO", "rc": None, "seg": 0.0})
                log(f"--- {etiqueta}: OMITIDO (fallo anterior en el grupo)")
                continue
            cmd = [sys.executable, str(script)] + (["--env-file", env_file] if env_file else [])
            rc, salida, seg = ejecutor(cmd, timeout_paso)
            estado = "OK" if rc == 0 else "FALLO"
            resultados.append({"grupo": grupo, "paso": etiqueta, "estado": estado, "rc": rc, "seg": seg})
            log(f"--- {etiqueta}: {estado} (rc={rc}, {seg:.0f}s)")
            for linea in salida.strip().splitlines()[-6:]:
                log(f"      {linea}")
            if rc != 0:
                fallo_previo = True
    return resultados


def imprimir_resumen(resultados: list, log: Registro) -> None:
    log("\n===== RESUMEN =====")
    por_grupo = {}
    for r in resultados:
        por_grupo.setdefault(r["grupo"], []).append(r)
    for grupo, filas in por_grupo.items():
        ok = sum(1 for f in filas if f["estado"] == "OK")
        malos = [f["paso"] for f in filas if f["estado"] == "FALLO"]
        omit = sum(1 for f in filas if f["estado"] == "OMITIDO")
        detalle = f" | FALLO en: {malos}" if malos else ""
        detalle += f" | omitidos: {omit}" if omit else ""
        log(f"  {grupo:11} {ok}/{len(filas)} pasos OK{detalle}")
    log(f"  tiempo total en pasos: {sum(r['seg'] for r in resultados):.0f}s")


def correr_monitor(env_file: str, log: Registro) -> int:
    cmd = [sys.executable, str(MONITOR), "--procesos", *PREFIJOS_MONITOR, "--horas-sin-exito", str(HORAS_SIN_EXITO),
           "--sin-repetir-horas", str(SIN_REPETIR_HORAS)]
    if env_file:
        cmd += ["--env-file", env_file]
    log("\n##### Monitor de alertas (solo procesos solares) #####")
    rc, salida, seg = ejecutar_subproceso(cmd, 120)
    for linea in salida.strip().splitlines():
        log(f"      {linea}")
    log(f"--- monitor: rc={rc} ({seg:.0f}s)")
    return rc


def avisar_directo(env_file: str, resultados: list, log: Registro) -> None:
    """Respaldo: si el monitor no pudo evaluar (ej. base inaccesible) y hubo pasos fallidos, avisa desde aqui."""
    try:
        sys.path.insert(0, str(ROOT / "db"))
        from monitor_etl import notificar  # noqa: E402
        from migrate import load_env  # noqa: E402
        env = load_env(Path(env_file))
        malos = [f"{r['grupo']}/{r['paso']}" for r in resultados if r["estado"] == "FALLO"]
        texto = ("Corrida del dominio Solar con pasos fallidos y el monitor no pudo evaluar la base "
                 f"({env.get('JAREMAR_SERVER', '?')}). Pasos: {malos}. Revisar logs/ en el equipo que ejecuta la tarea.")
        notificar(env, "[ETL JAREMAR] CRITICO: fallo del dominio Solar", texto)
    except Exception as exc:
        log(f"No se pudo enviar el aviso directo: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Corre silver y gold del dominio Solar y el monitor de alertas.")
    parser.add_argument("--env-file", default=None, help="Archivo .env con las credenciales (default: .env de la raiz).")
    parser.add_argument("--solo", nargs="+", choices=sorted(GRUPOS), default=None, metavar="GRUPO",
                        help=f"Corre solo estos grupos ({', '.join(GRUPOS)}).")
    parser.add_argument("--dry-run", action="store_true", help="Muestra el plan y verifica los scripts; no ejecuta nada.")
    parser.add_argument("--timeout-paso", type=int, default=TIMEOUT_PASO_DEFECTO, help="Segundos maximos por paso (default 900).")
    parser.add_argument("--log-dir", default=str(LOG_DIR_DEFECTO), help="Carpeta de registros y bloqueo (default <repo>/logs).")
    parser.add_argument("--sin-monitor", action="store_true", help="No corre el monitor de alertas al final.")
    args = parser.parse_args()

    grupos = args.solo or list(GRUPOS)

    if args.dry_run:
        faltan = []
        for g in grupos:
            print(f"\n[{g}]")
            for etiqueta, script in pasos_del_grupo(g):
                existe = script.is_file()
                print(f"  {'OK ' if existe else 'FALTA'} {etiqueta:44} {script.relative_to(ROOT)}")
                if not existe:
                    faltan.append(str(script))
        print(f"\n{sum(len(pasos_del_grupo(g)) for g in grupos)} pasos en {len(grupos)} grupo(s); "
              f"monitor {'omitido' if args.sin_monitor else 'al final'} ({', '.join(PREFIJOS_MONITOR)}).")
        return 1 if faltan else 0

    log_dir = Path(args.log_dir)
    bloqueo = log_dir / "run_solar.lock"
    if not tomar_bloqueo(bloqueo):
        print(f"Ya hay una corrida en curso ({bloqueo}); esta se cancela.", file=sys.stderr)
        return 2
    try:
        inicio = datetime.datetime.now()
        log = Registro(log_dir / f"run_solar_{inicio:%Y%m%d_%H%M%S}.log")
        log(f"Corrida del dominio Solar iniciada {inicio:%Y-%m-%d %H:%M:%S} | grupos: {grupos} | env: {args.env_file or '(.env)'}")
        purgados = purgar_logs(log_dir, RETENCION_DIAS)
        if purgados:
            log(f"Logs con mas de {RETENCION_DIAS} dias eliminados: {purgados}")

        resultados = correr(grupos, args.env_file, log, args.timeout_paso)
        imprimir_resumen(resultados, log)
        hubo_fallo = any(r["estado"] == "FALLO" for r in resultados)

        rc_monitor = None
        if not args.sin_monitor:
            rc_monitor = correr_monitor(args.env_file, log)
            if hubo_fallo and rc_monitor not in (0, 1):
                avisar_directo(args.env_file, resultados, log)

        log(f"\nCorrida terminada {datetime.datetime.now():%Y-%m-%d %H:%M:%S} ({(datetime.datetime.now() - inicio).total_seconds():.0f}s)")
        if hubo_fallo:
            return 1
        return 3 if rc_monitor == 1 else 0
    finally:
        liberar_bloqueo(bloqueo)


if __name__ == "__main__":
    raise SystemExit(main())
