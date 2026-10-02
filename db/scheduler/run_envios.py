"""
Orquestador de envios: actualiza dimVehiculo (la llave que resuelve el gold), corre el hecho
de envios (extract -> silver -> gold) y luego el monitor de alertas.

El extract es incremental por huella (migraciones 246-247): compara por dia los envios del
AS400 contra [int] y trae solo los dias que no cuadran. La corrida normal compara los dias
recientes (~8 s si no hay cambios); con --reconciliar compara todos los dias (~45 s) y gold
recorre todo [int]. registrar_tareas_envios.ps1 programa la normal a las 15:00 y la completa
todos los dias a las 07:00, que es la que detecta correcciones de fechas viejas. El gold
rellena en cada corrida las VehiculoKey que la dimension resuelva despues (migracion 186).

Si dimVehiculo falla, envios corre igual (las llaves que queden NULL se rellenan en la
corrida siguiente). La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_envios.py --env-file .env.prod                 # dias recientes
    python db/scheduler/run_envios.py --env-file .env.prod --reconciliar   # todos los dias (diaria 07:00)
    python db/scheduler/run_envios.py --env-file .env.prod --solo envios   # sin actualizar dimVehiculo
    python db/scheduler/run_envios.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_envios_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_envios.lock para no solaparse.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

# Con el extract FULL tardaba ~4 min (extract 204 s); por huella la normal tarda ~10 s y la
# completa ~45 s. La primera corrida despues de la migracion 246 trae todo una vez (~4 min).
TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["vehiculo"]

# Prefijos de sus procesos en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["Envios", "Vehiculo"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "envios", "envios", DIMENSIONES, PREFIJOS_MONITOR, TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre dimVehiculo y el hecho de envios, y el monitor.",
    ))
