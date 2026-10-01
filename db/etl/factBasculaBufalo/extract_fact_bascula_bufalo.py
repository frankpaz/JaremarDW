"""
Extraccion Bronze: AS400/LX (PROLXUSRF.BASMASTNN, boletas de bascula de las 4 basculas)
-> stg.factBasculaBufalo en JAREMAR.

BASMASTNN es la tabla vigente de boletas (desde 2024-09-02; BASMAST esta vacia y el historico
2018-2024 esta en respaldos que no se cargan, decision del usuario 2026-09-29). No tiene llave
unica ni fecha de modificacion, y las boletas se completan despues de creadas (el bruto llega
horas o dias despues de la tara). Silver hace MERGE por una llave construida (BASCIA + NUMBOLET
+ FECHAGEN + HORAGEN, ver migracion 203); este extract solo decide que filas traer:

  - incremental: FECHAGEN >= watermark "BasculaBufalo_Silver" - MARGEN_DIAS, mas las boletas
    abiertas (ESTATUS = 'T') de cualquier fecha, mas las que siguen abiertas en [int] aunque en
    el AS400 ya se hayan cerrado (si no, su cierre no llegaria nunca).
  - --reconciliar (o sin watermark): toda la tabla (~90 k filas, ~2 min).

Deja en su propio watermark ("BasculaBufalo") la fecha desde la que trajo TODO: silver solo
da de baja (EsVigente = 0) lo que falte a partir de esa fecha. 1900-01-01 = extract completo.

No se cargan la pesada 4 (vacia), IMPRESO (siempre 'S') ni FECHAIN/FECHAOUT (texto ambiguo).

Uso:
    python db/etl/factBasculaBufalo/extract_fact_bascula_bufalo.py [--env-file .env] [--reconciliar]
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "BasculaBufalo"
PROCESO_WATERMARK = "BasculaBufalo_Silver"   # lo avanza SOLO silver; este script solo lo lee
MARGEN_DIAS = 30
VENTANA_COMPLETA = datetime.datetime(1900, 1, 1)
AS400_ESQUEMA_ORIGEN = "PROLXUSRF"
AS400_TABLA_ORIGEN = "BASMASTNN"
COLUMNA_FECHA = "FECHAGEN"
STG_ESQUEMA = "stg"
STG_TABLA = "factBasculaBufalo"
INT_TABLA = "[int].factBasculaBufalo"

# 72 de las 86 columnas del origen (discovery 2026-09-29, QSYS2.SYSCOLUMNS).
COLUMNAS_DESEADAS = [
    "BASCIA", "NUMBOLET", "FECHAGEN", "HORAGEN", "BASCUSER", "NUMENVIO", "BOLETY", "NUMPLACA",
    "MOTORITA", "ORIGEN", "NUMLUGAR", "PESOGEMAN", "PESOTARA", "FECHATAR", "HORATARA", "PESOBRUT",
    "FECHBRUT", "HORABRUT", "PESONETO", "DIFPESO", "RIMPRESO", "ESTATUS", "NUMPROD", "NUMPROV",
    "MARCHAMO", "OBSERBA", "NUMDOCTS", "PESOAUDI", "BASAUDIT", "MONTAR1", "MONTAR2", "MONTAR3",
    "MOMBRU1", "MOMBRU2", "MOMBRU3", "FECHATAR1", "HORATARA1", "PESOTARA1", "FECHATAR2",
    "HORATARA2", "PESOTARA2", "FECHATAR3", "HORATARA3", "PESOTARA3", "FECHBRUT1", "HORABRUT1",
    "PESOBRUT1", "FECHBRUT2", "HORABRUT2", "PESOBRUT2", "FECHBRUT3", "HORABRUT3", "PESOBRUT3",
    "PESOGEMAN1", "PESOGEMAN2", "PESOGEMAN3", "PESONETO1", "PESONETO2", "PESONETO3", "DIFPESO1",
    "DIFPESO2", "DIFPESO3", "MARCACAM", "COLORCAM", "NUMDOCTO", "FECDCTOO", "STATUS1", "STATUS2",
    "ENCARGADO", "ONLINE", "IDENTIN", "IDENTOUT",
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
        PROCESO, "Basculas", "AS400/LX",
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


def boletas_abiertas_en_int(jrm_cur: pyodbc.Cursor, desde: datetime.date) -> list:
    """NUMBOLET de las boletas que en [int] siguen abiertas (ESTATUS 'T') y son anteriores a la ventana."""
    jrm_cur.execute(
        f"SELECT DISTINCT NUMBOLET FROM {INT_TABLA} WHERE ESTATUS = 'T' AND EsVigente = 1 AND FECHAGEN < ?",
        desde,
    )
    return sorted(int(r[0]) for r in jrm_cur.fetchall())


def ejecutar_consulta_origen(as400_cur: pyodbc.Cursor, columnas: list, desde_yyyymmdd, abiertas: list) -> None:
    """desde_yyyymmdd None = toda la tabla. Si no, la ventana + abiertas en el AS400 + abiertas en [int]."""
    nombres = ", ".join(f'"{c["nombre"]}"' for c in columnas)
    sql = f"SELECT {nombres} FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}"
    if desde_yyyymmdd is None:
        as400_cur.execute(sql)
        return
    condiciones = [f'"{COLUMNA_FECHA}" >= ?', "\"ESTATUS\" = 'T'"]
    # Son enteros tomados de [int] (no texto libre): se incrustan en listas IN de 500.
    for i in range(0, len(abiertas), 500):
        condiciones.append('"NUMBOLET" IN (' + ", ".join(str(n) for n in abiertas[i:i + 500]) + ")")
    as400_cur.execute(f"{sql} WHERE " + " OR ".join(condiciones), desde_yyyymmdd)


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
    llave_idx = nombres_cols.index("NUMBOLET") if "NUMBOLET" in nombres_cols else None

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
        help="Ignora el watermark y extrae toda la tabla (reconciliacion semanal).",
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
        if args.reconciliar or watermark is None:
            desde, desde_yyyymmdd, abiertas = None, None, []
            print(f"Modo {'RECONCILIACION' if args.reconciliar else 'CARGA INICIAL'}: se extrae toda la tabla.")
        else:
            desde = watermark - datetime.timedelta(days=MARGEN_DIAS)
            desde_yyyymmdd = int(desde.strftime("%Y%m%d"))
            abiertas = boletas_abiertas_en_int(jrm_cur, desde)
            print(f"Watermark actual ({PROCESO_WATERMARK}): {watermark} -> extrayendo desde {desde} "
                  f"(margen {MARGEN_DIAS}d) + abiertas en el AS400 + {len(abiertas)} numeros abiertos en [int]")

        ejecutar_consulta_origen(as400_cur, columnas, desde_yyyymmdd, abiertas)
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
