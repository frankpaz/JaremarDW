"""
Orquestador del dominio SanAlejo (PIDSA, bascula de las extractoras de palma): actualiza los 6
catalogos (dimSanAlejoProducto, Localizacion, Transportista, Cliente, Productor, Finca), corre los
3 hechos -- factSanAlejoFruta, factSanAlejoDespachos, factSanAlejoIngresos (extract -> silver ->
gold cada uno) -- y luego el monitor de alertas.

Cada hecho es un grupo independiente: si falla uno, los otros corren igual. Los hechos son
incrementales con la llave CODCIA + NUMDOC y nunca borran: la diaria trae 30 dias por fecha de
documento o de modificacion; la reconciliacion semanal trae todo desde 2025 (~2,5 min) para captar
correcciones viejas y marcar como no vigentes los documentos que desaparezcan. La logica comun esta
en hecho_programado.py.

Uso:
    python db/scheduler/run_sanalejo.py --env-file .env.prod                 # diaria
    python db/scheduler/run_sanalejo.py --env-file .env.prod --reconciliar   # semanal: todo desde 2025
    python db/scheduler/run_sanalejo.py --env-file .env.prod --solo sanalejo_fruta
    python db/scheduler/run_sanalejo.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_sanalejo_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_sanalejo.lock para no solaparse (la diaria y la reconciliacion comparten el bloqueo).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hecho_programado  # noqa: E402

TIMEOUT_PASO_DEFECTO = 1800
TIMEOUT_PASO_RECONCILIAR = 3600

DIMENSIONES = ["sanalejoproducto", "sanalejolocalizacion", "sanalejotransportista", "sanalejocliente",
               "sanalejoproductor", "sanalejofinca"]
HECHOS = ["sanalejo_fruta", "sanalejo_despachos", "sanalejo_ingresos"]

# Todos los procesos del dominio empiezan con "SanAlejo" (para acotar el monitor).
PREFIJOS_MONITOR = ["SanAlejo"]


if __name__ == "__main__":
    raise SystemExit(hecho_programado.main(
        "sanalejo", HECHOS, DIMENSIONES, PREFIJOS_MONITOR, TIMEOUT_PASO_DEFECTO, TIMEOUT_PASO_RECONCILIAR,
        "Corre los catalogos y los 3 hechos del dominio SanAlejo, y el monitor.",
    ))
