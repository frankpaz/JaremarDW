"""
Orquestador de compras: actualiza dimProveedor (la llave que resuelve el gold), corre el
hecho de compras (extract encabezados -> extract lineas -> silver -> gold) y luego el monitor
de alertas, acotado a los dominios Compras y Proveedor.

dimEmpresas no se corre aqui (cambia poco; la actualizan guias, manifiestos y
run_dimensiones.py). Si la dimension falla, compras corre igual (las llaves que queden NULL se rellenan en la
reconciliacion). La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_compras.py --env-file .env.prod                 # diaria (incremental, ventana de 30 dias)
    python db/scheduler/run_compras.py --env-file .env.prod --reconciliar   # semanal: todo el historico
    python db/scheduler/run_compras.py --env-file .env.prod --solo compras  # sin actualizar dimensiones
    python db/scheduler/run_compras.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_compras_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_compras.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

# La carga completa del 2026-09-23 tardo ~11 min (encabezados 5,5 min, lineas 4,7 min).
TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["proveedor"]

# Dominios de sus procesos en dbo.EtlProcess (para acotar el monitor).
DOMINIOS_MONITOR = ["Compras", "Proveedor"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "compras", "compras", DIMENSIONES, [], TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre dimProveedor y el hecho de compras, y el monitor.", dominios_monitor=DOMINIOS_MONITOR,
    ))
