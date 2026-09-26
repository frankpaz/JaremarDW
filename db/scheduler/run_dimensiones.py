"""
Orquestador de las dimensiones del AS400: corre extract -> silver -> gold de cada
dimension y luego el monitor de alertas acotado a esos procesos.

Cada dimension es un grupo independiente (una que falla no bloquea a las demas); dentro
de un grupo, ante el primer error se omiten los pasos siguientes. Al crear una dimension
nueva, agregarla a GRUPOS.

No incluye las dimensiones Solar (las corre run_solar.py) ni dimPlanGeneracion (carga
manual desde Excel). La geografia (departamento/municipio) va dentro del grupo "pais"
porque depende de dw.dimPais.

Uso:
    python db/scheduler/run_dimensiones.py --env-file .env.prod
    python db/scheduler/run_dimensiones.py --env-file .env.prod --solo viaje ruta
    python db/scheduler/run_dimensiones.py --dry-run

Codigos de salida:
    0  todo correcto        1  algun paso fallo      2  ya hay otra corrida en curso
    3  pasos correctos pero el monitor detecto alertas criticas

Cada corrida escribe logs/run_dimensiones_AAAAMMDD_HHMMSS.log (se conservan 30 dias) y usa
logs/run_dimensiones.lock para no solaparse.
"""
import argparse
import datetime
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_solar import (  # noqa: E402
    ETL, MONITOR, ROOT, LOG_DIR_DEFECTO, RETENCION_DIAS, TIMEOUT_PASO_DEFECTO,
    Registro, correr, ejecutar_subproceso, imprimir_resumen, liberar_bloqueo, tomar_bloqueo,
)

# grupo -> (carpeta, [scripts en orden]).
GRUPOS = {
    "sector": ("dimSector", ["extract_dim_sector.py", "load_silver_dim_sector.py", "load_gold_dim_sector.py"]),
    "centrocosto": ("dimCentroCosto", ["extract_dim_centro_costo.py", "load_silver_dim_centro_costo.py", "load_gold_dim_centro_costo.py"]),
    "cuenta": ("dimCuenta", ["extract_dim_cuenta.py", "load_silver_dim_cuenta.py", "load_gold_dim_cuenta.py"]),
    "subcuenta": ("dimSubCuenta", ["extract_dim_subcuenta.py", "load_silver_dim_subcuenta.py", "load_gold_dim_subcuenta.py"]),
    # dimEmpresas: la moneda funcional (stg.dimEmpresaMoneda) debe estar fresca antes del silver.
    "empresas": ("dimEmpresas", ["extract_dim_empresas.py", "extract_dim_empresa_moneda.py",
                                 "load_silver_dim_empresas.py", "load_gold_dim_empresas.py"]),
    "clasesproducto": ("dimClasesProducto", ["extract_dim_clases_producto.py", "load_silver_dim_clases_producto.py",
                                             "load_gold_dim_clases_producto.py"]),
    "producto": ("dimProducto", ["extract_dim_producto.py", "load_silver_dim_producto.py", "load_gold_dim_producto.py"]),
    "cliente": ("dimCliente", ["extract_dim_cliente.py", "load_silver_dim_cliente.py", "load_gold_dim_cliente.py"]),
    "proveedor": ("dimProveedor", ["extract_dim_proveedor.py", "load_silver_dim_proveedor.py", "load_gold_dim_proveedor.py"]),
    "terminosventa": ("dimTerminosVenta", ["extract_dim_terminos_venta.py", "load_silver_dim_terminos_venta.py",
                                           "load_gold_dim_terminos_venta.py"]),
    "terminoscompra": ("dimTerminosCompra", ["extract_dim_terminos_compra.py", "load_silver_dim_terminos_compra.py",
                                             "load_gold_dim_terminos_compra.py"]),
    "ruta": ("dimRuta", ["extract_dim_ruta.py", "load_silver_dim_ruta.py", "load_gold_dim_ruta.py"]),
    "viaje": ("dimViaje", ["extract_dim_viaje.py", "load_silver_dim_viaje.py", "load_gold_dim_viaje.py"]),
    # Geografia depende de dw.dimPais: va al final del mismo grupo.
    "pais": ("dimPais", ["extract_dim_pais.py", "load_silver_dim_pais.py", "load_gold_dim_pais.py",
                         "../dimGeografia/load_dim_geografia.py"]),
    # Resuelve ProveedorKey/PaisKey en gold: va despues de proveedor y pais.
    "vehiculo": ("dimVehiculo", ["extract_dim_vehiculo.py", "load_silver_dim_vehiculo.py", "load_gold_dim_vehiculo.py"]),
}

# Prefijos de sus procesos en dbo.EtlProcess (para acotar el monitor).
PREFIJOS_MONITOR = ["Sector", "CentroCosto", "Cuenta", "SubCuenta", "Empresas", "EmpresaMoneda", "ClasesProducto",
                    "Producto", "Cliente", "Proveedor", "TerminosVenta", "TerminosCompra", "Ruta", "Viaje", "Pais",
                    "DimDepartamento", "DimMunicipio", "Vehiculo"]


def pasos_del_grupo(grupo: str) -> list:
    """[(etiqueta, ruta_script)] en el orden declarado."""
    carpeta, scripts = GRUPOS[grupo]
    salida = []
    for s in scripts:
        ruta = (ETL / carpeta / s).resolve()
        salida.append((f"{ruta.parent.name}/{ruta.stem}", ruta))
    return salida


def purgar_logs(log_dir: Path, dias: int) -> int:
    limite = time.time() - dias * 86400
    n = 0
    for f in log_dir.glob("run_dimensiones_*.log"):
        if f.stat().st_mtime < limite:
            f.unlink()
            n += 1
    return n


def correr_monitor(env_file: str, log: Registro) -> int:
    cmd = [sys.executable, str(MONITOR), "--procesos", *PREFIJOS_MONITOR]
    if env_file:
        cmd += ["--env-file", env_file]
    log("\n##### Monitor de alertas (solo dimensiones AS400) #####")
    rc, salida, seg = ejecutar_subproceso(cmd, 120)
    for linea in salida.strip().splitlines():
        log(f"      {linea}")
    log(f"--- monitor: rc={rc} ({seg:.0f}s)")
    return rc


def main() -> int:
    parser = argparse.ArgumentParser(description="Corre extract, silver y gold de las dimensiones AS400 y el monitor.")
    parser.add_argument("--env-file", default=None, help="Archivo .env con las credenciales (default: .env de la raiz).")
    parser.add_argument("--solo", nargs="+", choices=sorted(GRUPOS), default=None, metavar="GRUPO",
                        help=f"Corre solo estas dimensiones ({', '.join(GRUPOS)}).")
    parser.add_argument("--dry-run", action="store_true", help="Muestra el plan y verifica los scripts; no ejecuta nada.")
    parser.add_argument("--timeout-paso", type=int, default=TIMEOUT_PASO_DEFECTO, help="Segundos maximos por paso (default 900).")
    parser.add_argument("--log-dir", default=str(LOG_DIR_DEFECTO), help="Carpeta de registros y bloqueo (default <repo>/logs).")
    parser.add_argument("--sin-monitor", action="store_true", help="No corre el monitor de alertas al final.")
    args = parser.parse_args()

    grupos = args.solo or list(GRUPOS)

    if args.dry_run:
        faltan = []
        for g in grupos:
            print(f"\n[{g}]")
            for etiqueta, script in pasos_del_grupo(g):
                existe = script.is_file()
                print(f"  {'OK ' if existe else 'FALTA'} {etiqueta:44} {script.relative_to(ROOT)}")
                if not existe:
                    faltan.append(str(script))
        print(f"\n{sum(len(pasos_del_grupo(g)) for g in grupos)} pasos en {len(grupos)} grupo(s); "
              f"monitor {'omitido' if args.sin_monitor else 'al final'}.")
        return 1 if faltan else 0

    log_dir = Path(args.log_dir)
    bloqueo = log_dir / "run_dimensiones.lock"
    if not tomar_bloqueo(bloqueo):
        print(f"Ya hay una corrida en curso ({bloqueo}); esta se cancela.", file=sys.stderr)
        return 2
    try:
        inicio = datetime.datetime.now()
        log = Registro(log_dir / f"run_dimensiones_{inicio:%Y%m%d_%H%M%S}.log")
        log(f"Corrida de dimensiones AS400 iniciada {inicio:%Y-%m-%d %H:%M:%S} | grupos: {grupos} | env: {args.env_file or '(.env)'}")
        purgados = purgar_logs(log_dir, RETENCION_DIAS)
        if purgados:
            log(f"Logs con mas de {RETENCION_DIAS} dias eliminados: {purgados}")

        resultados = correr(grupos, args.env_file, log, args.timeout_paso, pasos_por_grupo=pasos_del_grupo)
        imprimir_resumen(resultados, log)
        hubo_fallo = any(r["estado"] == "FALLO" for r in resultados)

        rc_monitor = None if args.sin_monitor else correr_monitor(args.env_file, log)

        log(f"\nCorrida terminada {datetime.datetime.now():%Y-%m-%d %H:%M:%S} ({(datetime.datetime.now() - inicio).total_seconds():.0f}s)")
        if hubo_fallo:
            return 1
        return 3 if rc_monitor == 1 else 0
    finally:
        liberar_bloqueo(bloqueo)


if __name__ == "__main__":
    raise SystemExit(main())
