"""
Orquestador de pedidos de venta: actualiza las dimensiones que resuelve el gold
(dimEmpresas, dimCliente, dimProducto, dimRuta), corre el hecho factPedidos
(extract -> silver -> gold, reemplazo por ventana de 30 dias de la fecha de la orden)
y luego el monitor de alertas.

Si una dimension falla, los pedidos corren igual (las llaves que queden NULL se
rellenan en la reconciliacion). La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_pedidos.py --env-file .env.prod                 # diaria (ventana de 30 dias)
    python db/scheduler/run_pedidos.py --env-file .env.prod --reconciliar   # semanal: todo desde 2026
    python db/scheduler/run_pedidos.py --env-file .env.prod --solo pedidos  # sin actualizar dimensiones
    python db/scheduler/run_pedidos.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_pedidos_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_pedidos.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

TIMEOUT_PASO_DEFECTO = 1800
# Todo 2026 son ~2,7 M filas al 2026-09 (~32 min de extract en prod) y crece ~3,4 M filas/anio.
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["empresas", "cliente", "producto", "ruta"]

# Prefijos de sus procesos en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["Pedidos", "Empresas", "EmpresaMoneda", "Cliente", "Producto", "Ruta"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "pedidos", "pedidos", DIMENSIONES, PREFIJOS_MONITOR, TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre las dimensiones de los pedidos, el hecho factPedidos y el monitor.",
    ))
