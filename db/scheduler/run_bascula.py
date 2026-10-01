"""
Orquestador de boletas de bascula: actualiza los 4 catalogos de bascula (dimBascula,
dimTipoBoleta, dimLugarBascula, dimProductoBascula; las llaves que resuelve el gold), corre el
hecho factBasculaBufalo (extract -> silver -> gold) y luego el monitor de alertas.

El hecho es incremental con una llave construida (BASCIA + NUMBOLET + FECHAGEN + HORAGEN) y
nunca borra: la diaria trae 30 dias + las boletas abiertas; la reconciliacion semanal trae toda
BASMASTNN (~90 k filas, ~2 min) para captar correcciones de boletas viejas y marcar como no
vigentes las que desaparezcan. La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_bascula.py --env-file .env.prod                 # diaria
    python db/scheduler/run_bascula.py --env-file .env.prod --reconciliar   # semanal: toda la tabla
    python db/scheduler/run_bascula.py --env-file .env.prod --solo bascula  # sin actualizar catalogos
    python db/scheduler/run_bascula.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_bascula_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_bascula.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

# La carga inicial del 2026-09-29 (toda la tabla, 90.581 filas) tardo ~2 min; la diaria, segundos.
TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["basculas", "tipoboleta", "lugarbascula", "productobascula"]

# Dominio de sus procesos en dbo.EtlProcess (para acotar el monitor): hecho y 4 catalogos.
DOMINIOS_MONITOR = ["Basculas"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "bascula", "bascula", DIMENSIONES, [], TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre los catalogos de bascula y el hecho factBasculaBufalo, y el monitor.", dominios_monitor=DOMINIOS_MONITOR,
    ))
