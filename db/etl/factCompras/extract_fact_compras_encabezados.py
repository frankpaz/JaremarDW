"""
Extraccion Bronze: AS400/LX (PROLX835F.APH, APHID='PH') -> stg.factComprasEncabezados
en JAREMAR.

APH es el encabezado de factura de proveedor del ERP, 1:N con PROLX835F.APL
(factComprasLineas). ~13 % de los encabezados (casi todos 2015-2019) no tienen
lineas porque el ERP purgo el detalle; factCompras es a grano de linea y no los
usa (decision del usuario, 2026-09-22), pero su huella se controla igual.

Carga incremental por huella (migraciones 248-250, ver db/etl/huella_as400.py).
APH no tiene fecha de modificacion y el encabezado cambia despues de sus lineas
(pagos: APCAMP, APSTAT, APCOUT), asi que se compara por dia de factura (AINVDT tal
cual del AS400) la cantidad de encabezados y la suma de sus huellas contra el
control [int].factComprasEncabezados, y se traen todos los encabezados de los dias
que no cuadran (quedan en stg.factComprasEncabezados_Periodos). La corrida normal
compara los ultimos DIAS_RECIENTES dias y las fechas posteriores; --reconciliar
compara todos los dias (los pagos de facturas viejas aparecen ahi).

El extract de lineas (que corre despues) usa estos encabezados para refrescar las
lineas de los que cambiaron y agrega a stg los encabezados que les falten.

Llave: compania + prefijo + anio + secuencia + proveedor + factura (APVNDR/APINV).
Los 479 encabezados con secuencia 0 (facturas que no se terminaron de registrar)
comparten compania + prefijo + anio + secuencia; con proveedor y factura es unica.

Uso:
    python db/etl/factCompras/extract_fact_compras_encabezados.py [--env-file .env] [--reconciliar]
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import pyodbc

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import huella_as400  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "Compras_Encabezados"
AS400_ESQUEMA_ORIGEN = "PROLX835F"
AS400_TABLA_ORIGEN = "APH"
FILTRO_COLUMNA = "APHID"
FILTRO_VALOR = "PH"
COLUMNA_PERIODO = "AINVDT"
STG_ESQUEMA = "stg"
STG_TABLA = "factComprasEncabezados"
STG_PERIODOS = "stg.factComprasEncabezados_Periodos"
INT_CONTROL = "[int].factComprasEncabezados"
DIAS_RECIENTES = 45
TAMANO_LOTE = 10000

COLUMNAS_DESEADAS = [
    "APCMPY", "PHDCPX", "PHDCYR", "PHDCSQ", "APVNDR", "APINV",
    "APHPND", "APHBNK", "APHCUR", "APHOLD",
    "AINVDT", "ADUEDT", "ADISCD",
    "APCINA", "APCAMP", "APCOUT", "APPORD", "APTERM", "APSTAT", "APPAYS",
    "PHHTRT", "PHTXBA", "APVNTX", "APPAYT",
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
                "es_texto": huella_as400.es_tipo_texto(row.type_name),
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
    esperadas = {c["nombre"].upper() for c in columnas} | {"HUELLA", "FECHACARGASTG", "RUNID"}
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
    [HUELLA] BIGINT NULL,
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


# --- Comparacion por periodo ------------------------------------------------

def periodos_a_extraer(jrm_cur, as400_cur, columnas: list, desde) -> tuple:
    """Compara por dia de factura el AS400 contra el control de [int]; (dias comparados, distintos)."""
    expr = huella_as400.expresion_huella(columnas)
    filtro_origen, params_origen = f'"{FILTRO_COLUMNA}" = ?', [FILTRO_VALOR]
    filtro_local, params_local = "1 = 1", []
    if desde is not None:
        filtro_origen += f' AND "{COLUMNA_PERIODO}" >= ?'
        params_origen.append(desde)
        filtro_local, params_local = "PeriodoOrigen >= ?", [desde]
    origen = huella_as400.checksum_as400(
        as400_cur, f"{AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}", COLUMNA_PERIODO,
        filtro_origen, params_origen, expr,
    )
    local = huella_as400.checksum_local(jrm_cur, INT_CONTROL, "PeriodoOrigen", filtro_local, params_local)
    return len(origen.keys() | local.keys()), huella_as400.periodos_distintos(origen, local)


def registrar_periodos(jrm_conn, jrm_cur, periodos: list, run_id: int) -> None:
    """Deja en stg los dias que el extract trae completos (silver solo da de baja en ellos)."""
    jrm_cur.execute(f"TRUNCATE TABLE {STG_PERIODOS}")
    if periodos:
        jrm_cur.executemany(f"INSERT INTO {STG_PERIODOS} (Periodo, RunId) VALUES (?, ?)",
                            [(p, run_id) for p in periodos])
    jrm_conn.commit()


# --- Extraccion / carga por lotes -------------------------------------------

def consulta_origen(columnas: list) -> str:
    # DB2 for i no soporta corchetes para identificadores -- se usan comillas dobles.
    nombres = ", ".join(f'"{c["nombre"]}"' for c in columnas)
    expr = huella_as400.expresion_huella(columnas)
    return (f'SELECT {nombres}, {expr} AS "HUELLA" FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN} '
            f"WHERE \"{FILTRO_COLUMNA}\" = '{FILTRO_VALOR}'")


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


def extraer_periodos(jrm_conn, jrm_cur, as400_cur, columnas: list, periodos: list, run_id: int) -> tuple:
    """Trae a stg todos los encabezados de los dias de factura que no cuadran."""
    nombres_cols = [c["nombre"] for c in columnas] + ["HUELLA"]
    col_list_sql = ", ".join(f"[{n}]" for n in nombres_cols) + ", [RunId]"
    placeholders = ", ".join(["?"] * (len(nombres_cols) + 1))
    insert_sql = f"INSERT INTO {STG_ESQUEMA}.{STG_TABLA} ({col_list_sql}) VALUES ({placeholders})"
    llave_idx = nombres_cols.index("PHDCSQ")

    base = consulta_origen(columnas)
    leidas = insertadas = rechazadas = 0
    for bloque in huella_as400.en_bloques(periodos):
        marcas = ", ".join(["?"] * len(bloque))
        as400_cur.execute(f'{base} AND "{COLUMNA_PERIODO}" IN ({marcas})', *bloque)
        while True:
            lote = as400_cur.fetchmany(TAMANO_LOTE)
            if not lote:
                break
            leidas += len(lote)
            ins, rech = cargar_lote(jrm_conn, jrm_cur, insert_sql, nombres_cols, llave_idx, lote, run_id)
            insertadas += ins
            rechazadas += rech
        print(f"  {leidas} encabezados traidos", flush=True)
    return leidas, insertadas, rechazadas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--reconciliar", action="store_true",
                        help="Compara todos los dias de factura, no solo los recientes.")
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
        jrm_cur.execute(f"TRUNCATE TABLE {STG_ESQUEMA}.{STG_TABLA}")
        jrm_conn.commit()

        desde = None
        if not args.reconciliar:
            desde = int((datetime.date.today() - datetime.timedelta(days=DIAS_RECIENTES)).strftime("%Y%m%d"))
        comparados, periodos = periodos_a_extraer(jrm_cur, as400_cur, columnas, desde)
        alcance = "todos los dias" if desde is None else f"dias desde {desde}"
        print(f"Comparacion de encabezados ({alcance}): {comparados} dias, {len(periodos)} no cuadran")
        registrar_periodos(jrm_conn, jrm_cur, periodos, run_id)

        leidas, insertadas, rechazadas = extraer_periodos(jrm_conn, jrm_cur, as400_cur, columnas, periodos, run_id)
        print(f"Total leidas: {leidas} / Insertadas: {insertadas} / Rechazadas: {rechazadas}")

        finalizar_run(
            jrm_cur, run_id, "EXITO" if rechazadas == 0 else "ADVERTENCIA",
            filas_leidas=leidas, filas_insertadas=insertadas, filas_rechazadas=rechazadas,
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
