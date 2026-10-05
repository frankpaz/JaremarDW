"""
Orquestador de ventas: actualiza dimProducto, corre el hecho de ventas
(extract lineas -> extract encabezados -> silver -> gold) y luego el monitor de alertas,
acotado a los dominios Ventas y Producto.

El hecho es incremental por huella (migraciones 253-255): el extract de lineas compara por dia
de factura contra el AS400 y solo se traen los dias que no cuadran. La corrida normal compara
los ultimos 45 dias; con --reconciliar compara todos los que guarda el AS400 (~4 meses: el ERP
purga lo anterior, que queda vigente en el warehouse) y gold recorre todo [int].

dimProducto va primero para que gold resuelva ProductoKey con datos frescos. dimEmpresas no
se corre aqui (cambia poco; la actualizan guias, manifiestos y run_dimensiones.py).
Si la dimension falla, ventas corre igual (las llaves que queden NULL se rellenan en la
reconciliacion). La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_ventas.py --env-file .env.prod                # dias recientes (05:00 y 13:00)
    python db/scheduler/run_ventas.py --env-file .env.prod --reconciliar  # todos los dias (diaria 02:00)
    python db/scheduler/run_ventas.py --env-file .env.prod --solo ventas  # sin actualizar dimensiones
    python db/scheduler/run_ventas.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_ventas_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_ventas.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

# La primera corrida por huella vuelve a traer todo lo que guarda el AS400 (~1,33 M lineas, ~25 min);
# despues, la completa solo trae los dias que no cuadran.
TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["producto"]

# Dominios de sus procesos en dbo.EtlProcess (para acotar el monitor). Por dominio y no por prefijo:
# el prefijo "Producto" tambien tomaba ProductoBascula, que es del dominio Basculas.
DOMINIOS_MONITOR = ["Ventas", "Producto"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "ventas", "ventas", DIMENSIONES, [], TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre dimProducto y el hecho de ventas, y el monitor.", dominios_monitor=DOMINIOS_MONITOR,
    ))
