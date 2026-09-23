"""
Extraccion Bronze: AS400/LX (PROLX835F.SIL, ILID='IL') -> stg.factVentasLineas
en JAREMAR.

SIL es el detalle de linea de factura del ERP (Infor Distribution SX.e).
Ademas de las filas 'IL' (linea normal) tiene un pequeno subconjunto 'IX'
(otro layout logico dentro del mismo archivo fisico) que se excluye por
completo -- no comparte el mismo significado de columnas.

Columnas elegidas tras analisis de poblacion real sobre 1546529 filas
(2026-09-22): se descartaron ~60 columnas con 0% de uso (bloque POD salvo
ILPCST, catch-weight, comisiones de articulo/cliente sin uso, 8 de los 10
pares de impuesto, etc). Llave de negocio verificada casi unica:
ILCOMP+ILDPFX+ILDOCN+ILDYR+ILDTYP+ILLINE (1546520 distintos de 1546529).

FASE 1 (backfill completo, 2026-09-22): ya se hizo -- 1550710 filas, en
lotes de 10000 (un solo fetchall()+executemany() sobre las 1.5M filas
resulto en que el driver ODBC del AS400 (iSeries Access) muriera a mitad de
la extraccion sin excepcion capturable; lotes mas chicos lo resuelven).

FASE 2 (incremental, desde 2026-09-22): SIL no tiene columna de ultima
modificacion propia, pero SI comparte encabezado con SIH via
IHDPFX+IHDOCN+IHDYR+IHDTYP, y SIH.IHENDT (fecha de creacion del documento)
es confiable. La extraccion incremental filtra por esa fecha con un JOIN al
propio AS400 contra SIH (no se puede filtrar SIL solo, no tiene la columna).
El watermark ("Ventas", compartido con extract_fact_ventas_encabezados.py)
lo actualiza SOLO load_silver_fact_ventas.py tras un merge exitoso -- este
script solo lo LEE.

La estructura de stg.factVentasLineas se auto-provisiona a partir de la
metadata real de las columnas en el AS400.

Uso:
    python db/etl/factVentas/extract_fact_ventas_lineas.py [--env-file .env]
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "Ventas_Lineas"
PROCESO_WATERMARK = "Ventas"
MARGEN_DIAS = 30
AS400_ESQUEMA_ORIGEN = "PROLX835F"
AS400_TABLA_ORIGEN = "SIL"
AS400_TABLA_ENCABEZADO = "SIH"
FILTRO_COLUMNA = "ILID"
FILTRO_VALOR = "IL"
FILTRO_COLUMNA_ENCABEZADO = "SIID"
FILTRO_VALOR_ENCABEZADO = "IH"
# Empresas excluidas del extract por pedido explicito del usuario (2026-09-22),
# sin justificacion de negocio documentada aqui -- confirmar con el usuario
# antes de tocar esta lista.
EMPRESAS_EXCLUIDAS = (63, 65, 67, 69)
STG_ESQUEMA = "stg"
STG_TABLA = "factVentasLineas"

COLUMNAS_DESEADAS = [
    "ILCOMP", "ILDPFX", "ILDOCN", "ILDYR", "ILDTYP", "ILLINE",
    "ILSEQ", "ILINVN", "ILORD", "ILDATE", "ILSDTE",
    "ILPROD", "ILCUST", "ILCUSB", "ILWHS",
    "ILLTYP", "ILOCLS",
    "ILQTY", "ILQINS",
    "ILNET", "ILNETS", "ILLIST", "ILBLST", "ILEXTA", "ILREV", "ILPCST",
    "ILUM", "ILSLUM", "ILCWUM",
    "ILTR01", "ILTA01", "ILTR02", "ILTA02",
    "ILSAL1", "ILSAL3", "ILCCOM",
    "ILCPO", "ILCONS",
    "ILNPSC", "ILLPSC", "ILPFAC", "ILPKGG",
]


def load_env(path: Path) -> dict:
    env = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k] = v
    return env


def connect_jaremar(env: dict) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{{env['JAREMAR_ODBC_DRIVER']}}};"
        f"SERVER={env['JAREMAR_SERVER']},{env['JAREMAR_PORT']};"
        f"DATABASE={env['JAREMAR_DATABASE']};"
    )
    if env.get("JAREMAR_AUTH_MODE", "sql").lower() == "windows":
        conn_str += "Trusted_Connection=yes;"
    else:
        conn_str += f"UID={env['JAREMAR_USER']};PWD={env['JAREMAR_PASSWORD']};"
    conn_str += "TrustServerCertificate=yes;"
    return pyodbc.connect(conn_str, timeout=15)


def connect_as400(env: dict) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{{env['AS400_DRIVER']}}};"
        f"SYSTEM={env['AS400_HOST']};"
        f"UID={env['AS400_USER']};PWD={env['AS400_PASSWORD']};"
    )
    return pyodbc.connect(conn_str, timeout=30)


# --- Registro / logging en el framework de control -------------------------

def registrar_proceso(jrm_cur: pyodbc.Cursor) -> int:
    jrm_cur.execute(
        """
        DECLARE @pid INT;
        EXEC dbo.usp_Etl_ProcesoRegistrar
            @Proceso = ?, @Dominio = ?, @SistemaOrigen = ?,
            @EsquemaOrigen = ?, @TablaOrigen = ?,
            @EsquemaDestino = ?, @TablaDestino = ?, @TipoCarga = ?,
            @ProcesoId = @pid OUTPUT;
        SELECT @pid;
        """,
        PROCESO, "Ventas", "AS400/LX",
        AS400_ESQUEMA_ORIGEN, AS400_TABLA_ORIGEN,
        STG_ESQUEMA, STG_TABLA, "Incremental",
    )
    return jrm_cur.fetchone()[0]


def iniciar_run(jrm_cur: pyodbc.Cursor) -> int:
    jrm_cur.execute("EXEC dbo.usp_Etl_RunIniciar @Proceso = ?", PROCESO)
    return jrm_cur.fetchone()[0]


def finalizar_run(jrm_cur, run_id, estado, **kwargs):
    jrm_cur.execute(
        """
        EXEC dbo.usp_Etl_RunFinalizar
            @RunId = ?, @Estado = ?,
            @FilasLeidas = ?, @FilasInsertadas = ?, @FilasRechazadas = ?,
            @MensajeError = ?, @TareaError = ?
        """,
        run_id, estado,
        kwargs.get("filas_leidas"), kwargs.get("filas_insertadas"), kwargs.get("filas_rechazadas"),
        kwargs.get("mensaje_error"), kwargs.get("tarea_error"),
    )


def obtener_watermark(jrm_cur: pyodbc.Cursor) -> "datetime.date | None":
    jrm_cur.execute("EXEC dbo.usp_Etl_WatermarkObtener @Proceso = ?", PROCESO_WATERMARK)
    row = jrm_cur.fetchone()
    if row is None or row[1] is None:
        return None
    return row[1].date() if hasattr(row[1], "date") else row[1]


def registrar_error_fila(jrm_cur, run_id, llave_negocio, payload, mensaje_error):
    jrm_cur.execute(
        "EXEC dbo.usp_Etl_ErrorRegistrar @RunId = ?, @LlaveNegocio = ?, @Payload = ?, @MensajeError = ?",
        run_id, llave_negocio, payload, mensaje_error,
    )


# --- Introspección del origen y auto-provisión de stg -----------------------

def mapear_tipo_sql_server(type_name: str, column_size: int, decimal_digits) -> str:
    t = (type_name or "").upper()
    if "CHAR" in t:
        size = column_size if column_size and column_size > 0 else 255
        return f"NVARCHAR({size})"
    if "DECIMAL" in t or "NUMERIC" in t:
        precision = column_size or 18
        scale = decimal_digits or 0
        return f"DECIMAL({precision},{scale})"
    if t in ("INTEGER", "INT"):
        return "INT"
    if t == "SMALLINT":
        return "SMALLINT"
    if t == "BIGINT":
        return "BIGINT"
    if t == "DATE":
        return "DATE"
    if t == "TIME":
        return "TIME"
    if "TIMESTAMP" in t:
        return "DATETIME2"
    if "FLOAT" in t or "DOUBLE" in t or "REAL" in t:
        return "FLOAT"
    return "NVARCHAR(255)"


def obtener_columnas_origen(as400_cur: pyodbc.Cursor) -> list:
    deseadas = {c.upper() for c in COLUMNAS_DESEADAS}
    encontradas = {}
    for row in as400_cur.columns(table=AS400_TABLA_ORIGEN, schema=AS400_ESQUEMA_ORIGEN):
        if row.column_name.upper() in deseadas:
            encontradas[row.column_name.upper()] = {
                "nombre": row.column_name,
                "tipo_sql_server": mapear_tipo_sql_server(row.type_name, row.column_size, row.decimal_digits),
            }

    faltantes = deseadas - encontradas.keys()
    if faltantes:
        raise RuntimeError(
            f"Estas columnas no existen en {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}: {sorted(faltantes)}"
        )

    return [encontradas[c.upper()] for c in COLUMNAS_DESEADAS]


def _columnas_actuales_stg(jrm_cur: pyodbc.Cursor) -> set:
    jrm_cur.execute(
        "SELECT UPPER(c.name) FROM sys.columns c WHERE c.object_id = OBJECT_ID(?)",
        f"{STG_ESQUEMA}.{STG_TABLA}",
    )
    return {row[0] for row in jrm_cur.fetchall()}


def asegurar_tabla_stg(jrm_cur: pyodbc.Cursor, columnas: list) -> str:
    esperadas = {c["nombre"].upper() for c in columnas} | {"FECHACARGASTG", "RUNID"}
    actuales = _columnas_actuales_stg(jrm_cur)

    if actuales and actuales != esperadas:
        jrm_cur.execute(f"DROP TABLE {STG_ESQUEMA}.{STG_TABLA}")
        actuales = set()

    cols_ddl = ",\n    ".join(f"[{c['nombre']}] {c['tipo_sql_server']} NULL" for c in columnas)
    ddl = f"""IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = '{STG_ESQUEMA}' AND t.name = '{STG_TABLA}'
)
BEGIN
    CREATE TABLE {STG_ESQUEMA}.{STG_TABLA} (
    {cols_ddl},
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_{STG_TABLA}_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END
"""
    SCHEMA_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = SCHEMA_CACHE_DIR / f"{STG_ESQUEMA}_{STG_TABLA}.generated.sql"
    cache_path.write_text(ddl, encoding="utf-8")
    jrm_cur.execute(ddl)
    return ddl


# --- Extraccion / carga ------------------------------------------------------

TAMANO_LOTE = 10000


def ejecutar_consulta_origen(as400_cur: pyodbc.Cursor, columnas: list, desde_yyyymmdd: int) -> None:
    # SIL no tiene columna de ultima modificacion propia -- se acota la
    # ventana incremental via JOIN a SIH (encabezado) por IHENDT, la unica
    # fecha de auditoria confiable del par de tablas.
    nombres = ", ".join(f'l."{c["nombre"]}"' for c in columnas)
    as400_cur.execute(
        f'SELECT {nombres} '
        f'FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN} l '
        f'JOIN {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ENCABEZADO} h '
        f'  ON l."ILDPFX" = h."IHDPFX" AND l."ILDOCN" = h."IHDOCN" '
        f' AND l."ILDYR" = h."IHDYR" AND l."ILDTYP" = h."IHDTYP" '
        f'WHERE l."{FILTRO_COLUMNA}" = ? AND h."{FILTRO_COLUMNA_ENCABEZADO}" = ? AND h."IHENDT" >= ? '
        f' AND l."ILCOMP" NOT IN ({", ".join(str(c) for c in EMPRESAS_EXCLUIDAS)})',
        FILTRO_VALOR, FILTRO_VALOR_ENCABEZADO, desde_yyyymmdd,
    )


def cargar_lote(jrm_conn, jrm_cur, insert_sql: str, nombres_cols: list, llave_idx, lote: list, run_id: int) -> tuple:
    lote_con_run = [tuple(f) + (run_id,) for f in lote]
    try:
        jrm_cur.executemany(insert_sql, lote_con_run)
        jrm_conn.commit()
        return len(lote_con_run), 0
    except pyodbc.Error:
        jrm_conn.rollback()

    insertadas, rechazadas = 0, 0
    for fila in lote_con_run:
        try:
            jrm_cur.execute(insert_sql, fila)
            jrm_conn.commit()
            insertadas += 1
        except pyodbc.Error as exc:
            jrm_conn.rollback()
            rechazadas += 1
            llave = str(fila[llave_idx]) if llave_idx is not None else None
            payload = json.dumps(dict(zip(nombres_cols, [str(v) for v in fila[:-1]])), ensure_ascii=False)
            registrar_error_fila(jrm_cur, run_id, llave, payload, str(exc))
            jrm_conn.commit()
    return insertadas, rechazadas


def extraer_y_cargar_por_lotes(jrm_conn, jrm_cur, as400_cur, columnas: list, run_id: int) -> tuple:
    """
    Trae filas del AS400 en lotes (fetchmany) y las inserta en stg en el
    mismo tamaño de lote, en vez de un unico fetchall()+executemany() sobre
    toda la tabla -- necesario dado el volumen de PROLX835F.SIL (~1.5M filas),
    que con un solo lote gigante tarda demasiado y no da visibilidad de avance.
    """
    nombres_cols = [c["nombre"] for c in columnas]
    llave_idx = nombres_cols.index("ILLINE") if "ILLINE" in nombres_cols else None

    jrm_cur.execute(f"TRUNCATE TABLE {STG_ESQUEMA}.{STG_TABLA}")

    col_list_sql = ", ".join(f"[{n}]" for n in nombres_cols) + ", [RunId]"
    placeholders = ", ".join(["?"] * (len(nombres_cols) + 1))
    insert_sql = f"INSERT INTO {STG_ESQUEMA}.{STG_TABLA} ({col_list_sql}) VALUES ({placeholders})"

    total_leidas = total_insertadas = total_rechazadas = 0
    while True:
        lote = as400_cur.fetchmany(TAMANO_LOTE)
        if not lote:
            break
        total_leidas += len(lote)
        insertadas, rechazadas = cargar_lote(jrm_conn, jrm_cur, insert_sql, nombres_cols, llave_idx, lote, run_id)
        total_insertadas += insertadas
        total_rechazadas += rechazadas
        print(f"  Lote de {len(lote)} filas -> insertadas {insertadas} / rechazadas {rechazadas} (acumulado: {total_leidas})", flush=True)

    return total_leidas, total_insertadas, total_rechazadas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument(
        "--reconciliar", action="store_true",
        help="Ignora el watermark y extrae todo el historico (reconciliacion semanal).",
    )
    args = parser.parse_args()

    env = load_env(Path(args.env_file))

    jrm_conn = connect_jaremar(env)
    jrm_conn.autocommit = False
    jrm_cur = jrm_conn.cursor()
    jrm_cur.fast_executemany = True

    registrar_proceso(jrm_cur)
    jrm_conn.commit()
    run_id = iniciar_run(jrm_cur)
    jrm_conn.commit()
    print(f"RunId: {run_id}")

    try:
        as400_conn = connect_as400(env)
    except Exception as exc:
        finalizar_run(jrm_cur, run_id, "ERROR", mensaje_error=str(exc), tarea_error="Conexion AS400")
        jrm_conn.commit()
        print(f"ERROR conectando a AS400: {exc}", file=sys.stderr)
        return 1

    try:
        as400_cur = as400_conn.cursor()
        columnas = obtener_columnas_origen(as400_cur)
        print(f"Columnas detectadas en {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}: {len(columnas)}")

        asegurar_tabla_stg(jrm_cur, columnas)
        jrm_conn.commit()

        watermark = obtener_watermark(jrm_cur)
        if args.reconciliar:
            desde = datetime.date(1900, 1, 1)
            print("Modo RECONCILIACION: se extrae todo el historico (se ignora el watermark).")
        else:
            desde = (watermark or datetime.date(1900, 1, 1)) - datetime.timedelta(days=MARGEN_DIAS)
        desde_yyyymmdd = int(desde.strftime("%Y%m%d"))
        print(f"Watermark actual ({PROCESO_WATERMARK}): {watermark} -> extrayendo desde {desde} (margen {MARGEN_DIAS}d)")

        ejecutar_consulta_origen(as400_cur, columnas, desde_yyyymmdd)
        filas_leidas, insertadas, rechazadas = extraer_y_cargar_por_lotes(
            jrm_conn, jrm_cur, as400_cur, columnas, run_id
        )
        print(f"Total leidas: {filas_leidas} / Insertadas: {insertadas} / Rechazadas: {rechazadas}")

        finalizar_run(
            jrm_cur, run_id, "EXITO" if rechazadas == 0 else "ADVERTENCIA",
            filas_leidas=filas_leidas, filas_insertadas=insertadas, filas_rechazadas=rechazadas,
        )
        jrm_conn.commit()
    except Exception as exc:
        jrm_conn.rollback()
        finalizar_run(jrm_cur, run_id, "ERROR", mensaje_error=str(exc), tarea_error="Extraccion/Carga")
        jrm_conn.commit()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        as400_conn.close()
        jrm_conn.close()

    print("Carga completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
