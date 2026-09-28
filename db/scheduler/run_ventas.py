"""
Orquestador de ventas: actualiza dimEmpresas y dimProducto, corre el hecho de ventas
(extract encabezados -> extract lineas -> silver -> gold) y luego el monitor de alertas.

Las dimensiones van primero para que gold resuelva EmpresaKey/ProductoKey con datos frescos.
Cada grupo es independiente: si una dimension falla, ventas corre igual (las llaves que queden
NULL se rellenan en la reconciliacion). Dentro de ventas, ante el primer error se omiten los
pasos siguientes (silver ademas verifica por su cuenta que los dos extracts esten completos).

Los pasos de ventas se toman de db/etl/run_fact.py y los de las dimensiones de
run_dimensiones.py, para no duplicar las listas.

Uso:
    python db/scheduler/run_ventas.py --env-file .env.prod                # diaria (incremental, ventana de 30 dias)
    python db/scheduler/run_ventas.py --env-file .env.prod --reconciliar  # semanal: todo el historico
    python db/scheduler/run_ventas.py --env-file .env.prod --solo ventas  # sin actualizar dimensiones
    python db/scheduler/run_ventas.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_ventas_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_ventas.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import argparse
import datetime
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "etl"))
from run_solar import (  # noqa: E402
    ETL, MONITOR, ROOT, LOG_DIR_DEFECTO, RETENCION_DIAS,
    Registro, correr, ejecutar_subproceso, imprimir_resumen, liberar_bloqueo, tomar_bloqueo,
)
import run_dimensiones  # noqa: E402
from run_fact import FLUJOS  # noqa: E402

# Un extract completo de lineas tarda ~25 min (1,56 M filas); la reconciliacion necesita mas margen.
TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600
HORAS_SIN_EXITO = 26
SIN_REPETIR_HORAS = 12

DIMENSIONES = ["empresas", "producto"]
GRUPOS = DIMENSIONES + ["ventas"]

# Prefijos de sus procesos en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["Ventas", "Empresas", "EmpresaMoneda", "Producto"]


def armar_pasos(reconciliar: bool):
    def pasos_del_grupo(grupo: str) -> list:
        """[(etiqueta, ruta_script, argumentos extra)] en orden."""
        if grupo in DIMENSIONES:
            return run_dimensiones.pasos_del_grupo(grupo)
        salida = []
        for script, acepta_reconciliar in FLUJOS["ventas"]:
            ruta = ETL / script
            extra = ["--reconciliar"] if reconciliar and acepta_reconciliar else []
            salida.append((f"{ruta.parent.name}/{ruta.stem}", ruta, extra))
        return salida
    return pasos_del_grupo


def purgar_logs(log_dir: Path, dias: int) -> int:
    limite = time.time() - dias * 86400
    n = 0
    for f in log_dir.glob("run_ventas_*.log"):
        if f.stat().st_mtime < limite:
            f.unlink()
            n += 1
    return n


def correr_monitor(env_file: str, log: Registro) -> int:
    cmd = [sys.executable, str(MONITOR), "--procesos", *PREFIJOS_MONITOR, "--horas-sin-exito", str(HORAS_SIN_EXITO),
           "--sin-repetir-horas", str(SIN_REPETIR_HORAS)]
    if env_file:
        cmd += ["--env-file", env_file]
    log("\n##### Monitor de alertas (ventas y sus dimensiones) #####")
    rc, salida, seg = ejecutar_subproceso(cmd, 120)
    for linea in salida.strip().splitlines():
        log(f"      {linea}")
    log(f"--- monitor: rc={rc} ({seg:.0f}s)")
    return rc


def main() -> int:
    parser = argparse.ArgumentParser(description="Corre dimEmpresas, dimProducto y el hecho de ventas, y el monitor.")
    parser.add_argument("--env-file", default=None, help="Archivo .env con las credenciales (default: .env de la raiz).")
    parser.add_argument("--reconciliar", action="store_true",
                        help="Extrae todo el historico de ventas y gold recorre todo [int] (corrida semanal).")
    parser.add_argument("--solo", nargs="+", choices=GRUPOS, default=None, metavar="GRUPO",
                        help=f"Corre solo estos grupos ({', '.join(GRUPOS)}).")
    parser.add_argument("--dry-run", action="store_true", help="Muestra el plan y verifica los scripts; no ejecuta nada.")
    parser.add_argument("--timeout-paso", type=int, default=None,
                        help=f"Segundos maximos por paso (default {TIMEOUT_PASO_DEFECTO}; {TIMEOUT_PASO_RECONCILIAR} con --reconciliar).")
    parser.add_argument("--log-dir", default=str(LOG_DIR_DEFECTO), help="Carpeta de registros y bloqueo (default <repo>/logs).")
    parser.add_argument("--sin-monitor", action="store_true", help="No corre el monitor de alertas al final.")
    args = parser.parse_args()

    grupos = [g for g in GRUPOS if g in args.solo] if args.solo else GRUPOS
    pasos_del_grupo = armar_pasos(args.reconciliar)
    timeout = args.timeout_paso or (TIMEOUT_PASO_RECONCILIAR if args.reconciliar else TIMEOUT_PASO_DEFECTO)
    modo = "reconciliacion" if args.reconciliar else "incremental"

    if args.dry_run:
        faltan = []
        for g in grupos:
            print(f"\n[{g}]")
            for paso in pasos_del_grupo(g):
                etiqueta, script = paso[0], paso[1]
                extra = " ".join(paso[2]) if len(paso) > 2 else ""
                existe = script.is_file()
                print(f"  {'OK ' if existe else 'FALTA'} {etiqueta:44} {script.relative_to(ROOT)} {extra}".rstrip())
                if not existe:
                    faltan.append(str(script))
        print(f"\n{sum(len(pasos_del_grupo(g)) for g in grupos)} pasos en {len(grupos)} grupo(s); modo {modo}; "
              f"limite {timeout}s por paso; monitor {'omitido' if args.sin_monitor else 'al final'}.")
        return 1 if faltan else 0

    log_dir = Path(args.log_dir)
    bloqueo = log_dir / "run_ventas.lock"
    if not tomar_bloqueo(bloqueo):
        print(f"Ya hay una corrida en curso ({bloqueo}); esta se cancela.", file=sys.stderr)
        return 2
    try:
        inicio = datetime.datetime.now()
        log = Registro(log_dir / f"run_ventas_{inicio:%Y%m%d_%H%M%S}.log")
        log(f"Corrida de ventas ({modo}) iniciada {inicio:%Y-%m-%d %H:%M:%S} | grupos: {grupos} | env: {args.env_file or '(.env)'}")
        purgados = purgar_logs(log_dir, RETENCION_DIAS)
        if purgados:
            log(f"Logs con mas de {RETENCION_DIAS} dias eliminados: {purgados}")

        resultados = correr(grupos, args.env_file, log, timeout, pasos_por_grupo=pasos_del_grupo)
        imprimir_resumen(resultados, log)
        hubo_fallo = any(r["estado"] == "FALLO" for r in resultados)

        rc_monitor = None if args.sin_monitor else correr_monitor(args.env_file, log)

        log(f"\nCorrida terminada {datetime.datetime.now():%Y-%m-%d %H:%M:%S} ({(datetime.datetime.now() - inicio).total_seconds():.0f}s)")
        if hubo_fallo:
            return 1
        return 3 if rc_monitor == 1 else 0
    finally:
        liberar_bloqueo(bloqueo)


if __name__ == "__main__":
    raise SystemExit(main())
