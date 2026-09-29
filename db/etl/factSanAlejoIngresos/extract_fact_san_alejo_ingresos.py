"""
Extraccion Bronze: AS400 (PIDSA.SPVHST02, "Historico de Ingresos de Productos") -> stg.factSanAlejoIngresos en JAREMAR.
Dominio SanAlejo: ingresos (recepciones) de productos en las extractoras -- sobre todo aceite crudo y fruta de
otras extractoras, fincas y proveedores --, con el documento y peso del envio de origen.

La llave CODCIA + NUMDOC es unica en el origen, pero no hay fecha de modificacion confiable para
todo: el origen marca MARMOD/FECMOD cuando se corrige una boleta. Silver hace MERGE por la llave
(migracion 240); este extract solo decide que filas traer (nunca antes de FECHA_INICIO,
historico acordado con el usuario):

  - incremental: FECDOC >= watermark "SanAlejoIngresos_Silver" - MARGEN_DIAS, o FECMOD >= esa fecha (boletas
    viejas corregidas).
  - --reconciliar (o sin watermark): todo desde FECHA_INICIO.

Deja en su propio watermark ("SanAlejoIngresos") la fecha desde la que trajo TODO: silver solo da de baja
(EsVigente = 0) lo que falte a partir de esa fecha. 1900-01-01 = todo desde FECHA_INICIO.

Uso:
    python db/etl/factSanAlejoIngresos/extract_fact_san_alejo_ingresos.py [--env-file .env] [--reconciliar]
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "SanAlejoIngresos"
PROCESO_WATERMARK = "SanAlejoIngresos_Silver"   # lo avanza SOLO silver; este script solo lo lee
MARGEN_DIAS = 30
FECHA_INICIO = datetime.date(2025, 1, 1)
VENTANA_COMPLETA = datetime.datetime(1900, 1, 1)
AS400_ESQUEMA_ORIGEN = "PIDSA"
AS400_TABLA_ORIGEN = "SPVHST02"
COLUMNA_FECHA = "FECDOC"
STG_ESQUEMA = "stg"
STG_TABLA = "factSanAlejoIngresos"

# 69 de las 92 columnas del origen: sin las vacias desde 2025 ni DIA/MES/AÑO
# (discovery 2026-09-29, QSYS2.SYSCOLUMNS).
COLUMNAS_DESEADAS = [
    "CODCIA", "CODSUC", "NUMDOC", "FECDOC", "HORDOC", "PLACA", "NOMBRE", "CODCLI", "CONDUC",
    "TIPOP", "COMEN1", "COMEN2", "COMEN3", "BRUTO", "TARA", "NETO", "CODTRA", "CODLOC", "SELLO1",
    "SELLO2", "SELLO3", "SELLO4", "SELLO5", "SELLO6", "SELLO7", "SELLO8", "SELLO9", "USUARI",
    "PORACI", "PORHUM", "REFDOC", "REFPES", "FECENV", "MARMOD", "USUMOD", "FECMOD", "NUMTIK",
    "FECSAL", "HORSAL", "CERTIF", "MODEL", "PROSUS", "BOLVEN", "NOPEDI", "FEPEDI", "NUMFAC",
    "SEMAN", "PEROPR", "MESC", "AÑOC", "P1NPLA", "P2NPLAC", "M1IDM", "T1CTRA", "CARAC1", "CARAC3",
    "CARAC5", "DIGIT1", "DIGIT2", "DIGIT6", "DIGIT7", "HORAB", "HORAT", "FECHAT", "FECHAB", "IDING",
    "IDSAL", "CONRAC", "CONCAL",
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
        PROCESO, "SanAlejo", "AS400/PIDSA",
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


def ejecutar_consulta_origen(as400_cur: pyodbc.Cursor, columnas: list, inicio: int, desde) -> None:
    """desde None = todo desde FECHA_INICIO. Si no, FECDOC >= desde o FECMOD >= desde (corregidas)."""
    nombres = ", ".join(f'"{c["nombre"]}"' for c in columnas)
    sql = f'SELECT {nombres} FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN} WHERE "{COLUMNA_FECHA}" >= ?'
    if desde is None:
        as400_cur.execute(sql, inicio)
    else:
        as400_cur.execute(f'{sql} AND ("{COLUMNA_FECHA}" >= ? OR "FECMOD" >= ?)', inicio, desde, desde)


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
    mismo tamaño de lote, en vez de un unico fetchall()+executemany(): con
    volumenes grandes el driver ODBC del
    AS400 puede morir a mitad de la extraccion sin excepcion capturable.
    """
    nombres_cols = [c["nombre"] for c in columnas]
    llave_idx = nombres_cols.index("NUMDOC") if "NUMDOC" in nombres_cols else None

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
        help="Ignora el watermark y extrae todo desde FECHA_INICIO (reconciliacion semanal).",
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
        inicio = int(FECHA_INICIO.strftime("%Y%m%d"))
        if args.reconciliar or watermark is None:
            desde, desde_yyyymmdd = None, None
            print(f"Modo {'RECONCILIACION' if args.reconciliar else 'CARGA INICIAL'}: se extrae todo desde {FECHA_INICIO}.")
        else:
            desde = max(watermark - datetime.timedelta(days=MARGEN_DIAS), FECHA_INICIO)
            desde_yyyymmdd = int(desde.strftime("%Y%m%d"))
            print(f"Watermark actual ({PROCESO_WATERMARK}): {watermark} -> extrayendo FECDOC o FECMOD desde {desde} "
                  f"(margen {MARGEN_DIAS}d)")

        ejecutar_consulta_origen(as400_cur, columnas, inicio, desde_yyyymmdd)
        filas_leidas, insertadas, rechazadas = extraer_y_cargar_por_lotes(
            jrm_conn, jrm_cur, as400_cur, columnas, run_id
        )
        print(f"Total leidas: {filas_leidas} / Insertadas: {insertadas} / Rechazadas: {rechazadas}")

        # La ventana que silver puede dar por completa (solo se da de baja lo que falte desde aqui).
        ventana = VENTANA_COMPLETA if desde is None else datetime.datetime.combine(desde, datetime.time())
        jrm_cur.execute(
            "EXEC dbo.usp_Etl_WatermarkActualizar @Proceso = ?, @NuevaFechaHora = ?, @TipoCarga = ?",
            PROCESO, ventana, "FULL" if desde is None else "Incremental",
        )

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
