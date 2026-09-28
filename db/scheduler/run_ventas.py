"""
Orquestador de ventas: actualiza dimEmpresas y dimProducto, corre el hecho de ventas
(extract encabezados -> extract lineas -> silver -> gold) y luego el monitor de alertas.

Las dimensiones van primero para que gold resuelva EmpresaKey/ProductoKey con datos frescos.
Si una dimension falla, ventas corre igual (las llaves que queden NULL se rellenan en la
reconciliacion). La logica comun esta en hecho_programado.py.

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
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

# Un extract completo de lineas tarda ~25 min (1,56 M filas); la reconciliacion necesita mas margen.
TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["empresas", "producto"]

# Prefijos de sus procesos en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["Ventas", "Empresas", "EmpresaMoneda", "Producto"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "ventas", "ventas", DIMENSIONES, PREFIJOS_MONITOR, TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre dimEmpresas, dimProducto y el hecho de ventas, y el monitor.",
    ))
