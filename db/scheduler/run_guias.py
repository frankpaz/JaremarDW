"""
Orquestador de guias de remision: actualiza las dimensiones que resuelve el gold
(dimEmpresas, dimCliente, dimProducto, dimVehiculo, dimMotivoTraslado), corre el hecho
factGuiasRemision (extract -> silver -> gold, reemplazo por ventana de 30 dias de la
fecha de registro) y luego el monitor de alertas.

Si una dimension falla, las guias corren igual (las llaves que queden NULL se rellenan
en la reconciliacion). La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_guias.py --env-file .env.prod                # diaria (ventana de 30 dias)
    python db/scheduler/run_guias.py --env-file .env.prod --reconciliar  # semanal: todo desde 2025
    python db/scheduler/run_guias.py --env-file .env.prod --solo guias   # sin actualizar dimensiones
    python db/scheduler/run_guias.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_guias_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_guias.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["empresas", "cliente", "producto", "vehiculo", "motivotraslado"]

# Prefijos de sus procesos en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["GuiasRemision", "Empresas", "EmpresaMoneda", "Cliente", "Producto", "Vehiculo", "MotivoTraslado"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "guias", "guias", DIMENSIONES, PREFIJOS_MONITOR, TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre las dimensiones de las guias de remision, el hecho factGuiasRemision y el monitor.",
    ))
