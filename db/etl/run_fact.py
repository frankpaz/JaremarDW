"""
Orquestador del flujo Bronze -> Silver -> Gold de un hecho AS400.

Corre los pasos en orden y se detiene en el primero que falle (los silver ya
verifican por su cuenta que los extracts esten completos y frescos).

Uso:
    python db/etl/run_fact.py ventas   [--env-file .env.prod]     # diario (incremental, ventana de 30 dias)
    python db/etl/run_fact.py compras  [--env-file .env.prod]
    python db/etl/run_fact.py envios   [--env-file .env.prod]     # el extract es FULL (el origen no tiene fecha de modificacion)
    python db/etl/run_fact.py guias    [--env-file .env.prod]     # guias de remision: ventana de 30 dias por fecha de registro
    python db/etl/run_fact.py manifiestos [--env-file .env.prod]  # manifiestos (UNDIS002): ventana de 30 dias por fecha de la orden

    python db/etl/run_fact.py ventas --reconciliar                # semanal: extrae todo el historico, gold recorre todo [int]
"""
import argparse
import subprocess
import sys
from pathlib import Path

ETL = Path(__file__).resolve().parent

# (script, acepta --reconciliar)
FLUJOS = {
    "ventas": [
        ("factVentas/extract_fact_ventas_encabezados.py", True),
        ("factVentas/extract_fact_ventas_lineas.py", True),
        ("factVentas/load_silver_fact_ventas.py", False),
        ("factVentas/load_gold_fact_ventas.py", True),
    ],
    "compras": [
        ("factCompras/extract_fact_compras_encabezados.py", True),
        ("factCompras/extract_fact_compras_lineas.py", True),
        ("factCompras/load_silver_fact_compras.py", False),
        ("factCompras/load_gold_fact_compras.py", True),
    ],
    "envios": [
        ("factEnvios/extract_fact_envios.py", False),
        ("factEnvios/load_silver_fact_envios.py", False),
        ("factEnvios/load_gold_fact_envios.py", True),
    ],
    # Reemplazo por ventana de fecha de registro (el origen no tiene llave unica); --reconciliar = desde 2025.
    "guias": [
        ("factGuiasRemision/extract_fact_guias_remision.py", True),
        ("factGuiasRemision/load_silver_fact_guias_remision.py", False),
        ("factGuiasRemision/load_gold_fact_guias_remision.py", True),
    ],
    # Mismo esquema de ventana que guias, por fecha de la orden; --reconciliar = desde 2026.
    "manifiestos": [
        ("factManifiestos/extract_fact_manifiestos.py", True),
        ("factManifiestos/load_silver_fact_manifiestos.py", False),
        ("factManifiestos/load_gold_fact_manifiestos.py", True),
    ],
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("flujo", choices=sorted(FLUJOS))
    parser.add_argument("--env-file", default=None)
    parser.add_argument("--reconciliar", action="store_true")
    args = parser.parse_args()

    for script, acepta_reconciliar in FLUJOS[args.flujo]:
        cmd = [sys.executable, str(ETL / script)]
        if args.env_file:
            cmd += ["--env-file", args.env_file]
        if args.reconciliar and acepta_reconciliar:
            cmd.append("--reconciliar")
        print(f"\n=== {script} ===", flush=True)
        rc = subprocess.run(cmd).returncode
        if rc != 0:
            print(f"!!! {script} termino con codigo {rc}; se detiene el flujo.", file=sys.stderr)
            return rc

    print(f"\nFlujo '{args.flujo}' completado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
