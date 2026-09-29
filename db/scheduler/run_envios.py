"""
Orquestador de envios: actualiza dimVehiculo (la llave que resuelve el gold), corre el hecho
de envios (extract FULL -> silver -> gold) y luego el monitor de alertas.

A diferencia de los otros hechos no lleva reconciliacion semanal: el extract ya trae todo
ENCAB cada vez, silver da de baja lo que desaparece del AS400 y el gold rellena en cada
corrida las VehiculoKey que la dimension resuelva despues (migracion 186). --reconciliar
queda disponible a mano (gold recorre todo [int]), pero no hace falta programarlo.

Si dimVehiculo falla, envios corre igual (las llaves que queden NULL se rellenan en la
corrida siguiente). La logica comun esta en hecho_programado.py.

Uso:
    python db/scheduler/run_envios.py --env-file .env.prod                 # diaria
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

# La corrida del 2026-09-23 tardo ~4 min (extract FULL 204 s, silver 16 s, gold 13 s).
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
