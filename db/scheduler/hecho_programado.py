"""
Logica comun de los orquestadores de hechos AS400 programados (run_ventas.py,
run_guias.py, run_compras.py, run_manifiestos.py, run_envios.py, run_bascula.py,
run_sanalejo.py): actualiza primero las dimensiones de las que depende el gold del
hecho, corre el flujo del hecho (tomado de db/etl/run_fact.py) y al final el monitor
acotado a esos procesos. Un orquestador puede correr varios hechos (run_sanalejo.py).

Cada dimension y cada hecho es un grupo independiente: si una dimension falla, el
hecho corre igual (las llaves que queden NULL se rellenan en la corrida siguiente o
en la reconciliacion), y si un hecho falla los demas siguen. Dentro de un grupo, ante
el primer error se omiten los pasos siguientes.

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_<nombre>_AAAAMMDD_HHMMSS.log (se conservan 30 dias)
y usa logs/run_<nombre>.lock para no solaparse (la diaria y la reconciliacion
comparten el bloqueo).
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

HORAS_SIN_EXITO = 26
SIN_REPETIR_HORAS = 12


def armar_pasos(dimensiones: list, reconciliar: bool):
    def pasos_del_grupo(grupo: str) -> list:
        """[(etiqueta, ruta_script, argumentos extra)] en orden."""
        if grupo in dimensiones:
            return run_dimensiones.pasos_del_grupo(grupo)
        salida = []
        for script, acepta_reconciliar in FLUJOS[grupo]:
            ruta = ETL / script
            extra = ["--reconciliar"] if reconciliar and acepta_reconciliar else []
            salida.append((f"{ruta.parent.name}/{ruta.stem}", ruta, extra))
        return salida
    return pasos_del_grupo


def purgar_logs(log_dir: Path, nombre: str, dias: int) -> int:
    limite = time.time() - dias * 86400
    n = 0
    for f in log_dir.glob(f"run_{nombre}_*.log"):
        if f.stat().st_mtime < limite:
            f.unlink()
            n += 1
    return n


def correr_monitor(env_file: str, log: Registro, prefijos: list, titulo: str) -> int:
    cmd = [sys.executable, str(MONITOR), "--procesos", *prefijos, "--horas-sin-exito", str(HORAS_SIN_EXITO),
           "--sin-repetir-horas", str(SIN_REPETIR_HORAS)]
    if env_file:
        cmd += ["--env-file", env_file]
    log(f"\n##### Monitor de alertas ({titulo}) #####")
    rc, salida, seg = ejecutar_subproceso(cmd, 120)
    for linea in salida.strip().splitlines():
        log(f"      {linea}")
    log(f"--- monitor: rc={rc} ({seg:.0f}s)")
    return rc


def main(nombre: str, flujo: str, dimensiones: list, prefijos_monitor: list,
         timeout_defecto: int, timeout_reconciliar: int, descripcion: str) -> int:
    """nombre: sufijo de log/bloqueo; flujo: clave (o lista de claves) de run_fact.FLUJOS; dimensiones: grupos de
    run_dimensiones."""
    flujos = [flujo] if isinstance(flujo, str) else list(flujo)
    grupos_todos = dimensiones + flujos
    parser = argparse.ArgumentParser(description=descripcion)
    parser.add_argument("--env-file", default=None, help="Archivo .env con las credenciales (default: .env de la raiz).")
    parser.add_argument("--reconciliar", action="store_true",
                        help=f"Reconciliacion semanal de {', '.join(flujos)} (ver db/etl/run_fact.py).")
    parser.add_argument("--solo", nargs="+", choices=grupos_todos, default=None, metavar="GRUPO",
                        help=f"Corre solo estos grupos ({', '.join(grupos_todos)}).")
    parser.add_argument("--dry-run", action="store_true", help="Muestra el plan y verifica los scripts; no ejecuta nada.")
    parser.add_argument("--timeout-paso", type=int, default=None,
                        help=f"Segundos maximos por paso (default {timeout_defecto}; {timeout_reconciliar} con --reconciliar).")
    parser.add_argument("--log-dir", default=str(LOG_DIR_DEFECTO), help="Carpeta de registros y bloqueo (default <repo>/logs).")
    parser.add_argument("--sin-monitor", action="store_true", help="No corre el monitor de alertas al final.")
    args = parser.parse_args()

    grupos = [g for g in grupos_todos if g in args.solo] if args.solo else grupos_todos
    pasos_del_grupo = armar_pasos(dimensiones, args.reconciliar)
    timeout = args.timeout_paso or (timeout_reconciliar if args.reconciliar else timeout_defecto)
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
    bloqueo = log_dir / f"run_{nombre}.lock"
    if not tomar_bloqueo(bloqueo):
        print(f"Ya hay una corrida en curso ({bloqueo}); esta se cancela.", file=sys.stderr)
        return 2
    try:
        inicio = datetime.datetime.now()
        log = Registro(log_dir / f"run_{nombre}_{inicio:%Y%m%d_%H%M%S}.log")
        log(f"Corrida de {nombre} ({modo}) iniciada {inicio:%Y-%m-%d %H:%M:%S} | grupos: {grupos} | env: {args.env_file or '(.env)'}")
        purgados = purgar_logs(log_dir, nombre, RETENCION_DIAS)
        if purgados:
            log(f"Logs con mas de {RETENCION_DIAS} dias eliminados: {purgados}")

        resultados = correr(grupos, args.env_file, log, timeout, pasos_por_grupo=pasos_del_grupo)
        imprimir_resumen(resultados, log)
        hubo_fallo = any(r["estado"] == "FALLO" for r in resultados)

        rc_monitor = None if args.sin_monitor else correr_monitor(
            args.env_file, log, prefijos_monitor, f"{nombre} y sus dimensiones")

        log(f"\nCorrida terminada {datetime.datetime.now():%Y-%m-%d %H:%M:%S} ({(datetime.datetime.now() - inicio).total_seconds():.0f}s)")
        if hubo_fallo:
            return 1
        return 3 if rc_monitor == 1 else 0
    finally:
        liberar_bloqueo(bloqueo)
