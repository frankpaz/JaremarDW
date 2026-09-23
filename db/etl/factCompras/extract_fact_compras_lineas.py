"""
Extraccion Bronze: AS400/LX (PROLX835F.APL, PLID='PL') -> stg.factComprasLineas
en JAREMAR.

APL es el detalle contable de facturas de proveedor del ERP (Infor
Distribution SX.e, "Payables Line File") -- no tiene detalle de producto ni
cantidad (a diferencia de SIL en ventas), es mas bien la distribucion
contable/centro de costo de cada factura.

INCREMENTAL desde el arranque (a diferencia de factVentas, que empezo FULL
y migro despues): APH/APL tienen historia completa desde 2004 (no una
ventana viva del ERP), y APL.PLEDTE ("Created On Date") es una columna de
auditoria confiable -- a diferencia de SIL, aqui el campo de auditoria vive
en la linea, no en el encabezado. Se extrae con margen de seguridad hacia
atras (MARGEN_DIAS) por si hay correcciones tardias. El watermark
("Compras", compartido con extract_fact_compras_encabezados.py) lo
actualiza SOLO load_silver_fact_compras.py tras un merge exitoso -- este
script solo lo LEE.

Columnas elegidas tras analisis de poblacion real sobre 715323 filas
(2026-09-22, ver db/discovery/discover_columnas.py --poblacion): se
descartaron columnas con 0% de uso (PLDSC, PLBDSC, PLSOUR, PLCCEX, PLBCEX,
PLRVDT, PLRPDT). Llave de negocio PLCMPY+PLDCPX+PLDCYR+PLDCSQ+PLLINE, casi
unica (714415 distintos de 715323 filas).

Se extrae e inserta en lotes (fetchmany) porque el volumen (>700k filas en
la primera corrida) puede hacer que el driver ODBC del AS400 muera a mitad
de la extraccion sin excepcion capturable (ver factVentas, Fase 1).

Uso:
    python db/etl/factCompras/extract_fact_compras_lineas.py [--env-file .env]
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "Compras_Lineas"
PROCESO_WATERMARK = "Compras"
MARGEN_DIAS = 30
AS400_ESQUEMA_ORIGEN = "PROLX835F"
AS400_TABLA_ORIGEN = "APL"
FILTRO_COLUMNA = "PLID"
FILTRO_VALOR = "PL"
STG_ESQUEMA = "stg"
STG_TABLA = "factComprasLineas"
TAMANO_LOTE = 10000

COLUMNAS_DESEADAS = [
    "PLCMPY", "PLDCPX", "PLDCYR", "PLDCSQ", "PLLINE",
    "PLVNDR", "PLINV", "PLTYPE", "PLGLDT", "PLAMT", "PLBAMT",
    "PLDESC", "PLUSER", "PLEDTE", "PLETIM", "PLRESN",
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
        PROCESO, "Compras", "AS400/LX",
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


# --- Extraccion / carga por lotes -------------------------------------------

def ejecutar_consulta_origen(as400_cur: pyodbc.Cursor, columnas: list, desde_yyyymmdd: int) -> None:
    nombres = ", ".join(f'"{c["nombre"]}"' for c in columnas)
    as400_cur.execute(
        f'SELECT {nombres} FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN} '
        f'WHERE "{FILTRO_COLUMNA}" = ? AND "PLEDTE" >= ?',
        FILTRO_VALOR, desde_yyyymmdd,
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
    nombres_cols = [c["nombre"] for c in columnas]
    llave_idx = nombres_cols.index("PLLINE") if "PLLINE" in nombres_cols else None

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
