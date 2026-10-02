"""
Orquestador del flujo Bronze -> Silver -> Gold de un hecho AS400.

Corre los pasos en orden y se detiene en el primero que falle (los silver ya
verifican por su cuenta que los extracts esten completos y frescos).

Uso:
    python db/etl/run_fact.py ventas   [--env-file .env.prod]     # diario (incremental, ventana de 30 dias)
    python db/etl/run_fact.py compras  [--env-file .env.prod]
    python db/etl/run_fact.py envios   [--env-file .env.prod]     # por huella: trae solo los dias que no cuadran (--reconciliar compara todos)
    python db/etl/run_fact.py guias    [--env-file .env.prod]     # guias de remision: ventana de 30 dias por fecha de registro
    python db/etl/run_fact.py manifiestos [--env-file .env.prod]  # manifiestos (UNDIS002): ventana de 30 dias por fecha de la orden
    python db/etl/run_fact.py bascula  [--env-file .env.prod]     # boletas de bascula (BASMASTNN): ventana de 30 dias + abiertas, MERGE
    python db/etl/run_fact.py sanalejo_fruta [--env-file .env.prod]  # dominio SanAlejo (tambien sanalejo_despachos / sanalejo_ingresos)

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
    # Por huella (migraciones 248-250): encabezados por dia de factura y lineas por dia de creacion;
    # --reconciliar = todos los dias.
    "compras": [
        ("factCompras/extract_fact_compras_encabezados.py", True),
        ("factCompras/extract_fact_compras_lineas.py", True),
        ("factCompras/load_silver_fact_compras.py", False),
        ("factCompras/load_gold_fact_compras.py", True),
    ],
    # Por huella (migraciones 246-247): compara por dia contra el AS400; --reconciliar = todos los dias.
    "envios": [
        ("factEnvios/extract_fact_envios.py", True),
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
    # Boletas de bascula: MERGE por llave construida (nunca borra); --reconciliar = toda la tabla.
    "bascula": [
        ("factBasculaBufalo/extract_fact_bascula_bufalo.py", True),
        ("factBasculaBufalo/load_silver_fact_bascula_bufalo.py", False),
        ("factBasculaBufalo/load_gold_fact_bascula_bufalo.py", True),
    ],
    # Dominio SanAlejo (PIDSA, bascula de las extractoras): MERGE por CODCIA + NUMDOC, nunca borra;
    # ventana de 30 dias por fecha de documento o de modificacion; --reconciliar = todo desde 2025.
    "sanalejo_fruta": [
        ("factSanAlejoFruta/extract_fact_san_alejo_fruta.py", True),
        ("factSanAlejoFruta/load_silver_fact_san_alejo_fruta.py", False),
        ("factSanAlejoFruta/load_gold_fact_san_alejo_fruta.py", True),
    ],
    "sanalejo_despachos": [
        ("factSanAlejoDespachos/extract_fact_san_alejo_despachos.py", True),
        ("factSanAlejoDespachos/load_silver_fact_san_alejo_despachos.py", False),
        ("factSanAlejoDespachos/load_gold_fact_san_alejo_despachos.py", True),
    ],
    "sanalejo_ingresos": [
        ("factSanAlejoIngresos/extract_fact_san_alejo_ingresos.py", True),
        ("factSanAlejoIngresos/load_silver_fact_san_alejo_ingresos.py", False),
        ("factSanAlejoIngresos/load_gold_fact_san_alejo_ingresos.py", True),
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
