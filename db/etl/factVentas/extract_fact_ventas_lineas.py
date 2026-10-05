"""
Extraccion Bronze: AS400/LX (PROLX835F.SIL, ILID='IL') -> stg.factVentasLineas
en JAREMAR.

SIL es el detalle de linea de factura del ERP. Ademas de las filas 'IL' (linea normal) tiene un
pequeno subconjunto 'IX' (otro layout logico dentro del mismo archivo fisico) que se excluye por
completo -- no comparte el mismo significado de columnas. Columnas elegidas tras analisis de
poblacion real (2026-09-22): se descartaron ~60 columnas con 0% de uso.

Carga incremental por huella (migraciones 253-255, ver db/etl/huella_as400.py). Corre ANTES del
extract de encabezados:
  1. Compara por dia de factura (ILDATE tal cual del AS400) la cantidad de lineas y la suma de sus
     huellas contra [int].factVentas. La huella de cada linea incluye las columnas del encabezado
     que viajan a la linea (JOIN exacto a SIH por compania + documento + SIINVD = ILDATE), asi que
     un cambio en el encabezado tambien hace que el dia no cuadre. La corrida normal compara los
     ultimos DIAS_RECIENTES dias y las fechas posteriores; --reconciliar compara todos.
  2. Trae las lineas de los dias que no cuadran y deja esos dias en stg.factVentas_Periodos (el
     extract de encabezados trae los encabezados de los mismos dias).
Las lineas vigentes de [int] de un dia revisado que no vinieron ya no estan en el AS400 (la fecha
es parte de la llave): silver las da de baja.

Purga: el AS400 solo conserva ~4 meses de ventas (desde 2026-06-03 al 2026-10-05). Los dias que
solo estan en [int] y son anteriores al horizonte (DIAS_HORIZONTE_BAJAS, el mismo default de silver)
fueron purgados en el origen: no se comparan y se conservan vigentes en [int], que es la unica copia.

Llave: compania + prefijo + documento + anio + tipo + linea + fecha de factura (ILDATE). Sin la
fecha se repite: facturas distintas que reusan el numero en otro dia.

Empresas excluidas (63, 65, 67, 69) por pedido del usuario (2026-09-22). Se extrae e inserta en
lotes (fetchmany): el driver ODBC del AS400 puede morir a mitad de una extraccion grande sin
excepcion capturable.

Uso:
    python db/etl/factVentas/extract_fact_ventas_lineas.py [--env-file .env] [--reconciliar]
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import pyodbc

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import huella_as400  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_fact_ventas_encabezados as enc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "Ventas_Lineas"
AS400_ESQUEMA_ORIGEN = "PROLX835F"
AS400_TABLA_ORIGEN = "SIL"
FILTRO_COLUMNA = "ILID"
FILTRO_VALOR = "IL"
COLUMNA_PERIODO = "ILDATE"
# Empresas excluidas del extract por pedido explicito del usuario (2026-09-22),
# sin justificacion de negocio documentada aqui -- confirmar con el usuario
# antes de tocar esta lista.
EMPRESAS_EXCLUIDAS = (63, 65, 67, 69)
STG_ESQUEMA = "stg"
STG_TABLA = "factVentasLineas"
STG_PERIODOS = enc.STG_PERIODOS
INT_TABLA = "[int].factVentas"
DIAS_RECIENTES = 45
DIAS_HORIZONTE_BAJAS = 90
TAMANO_LOTE = 10000

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


def registrar_error_fila(jrm_cur, run_id, llave_negocio, payload, mensaje_error):
    jrm_cur.execute(
        "EXEC dbo.usp_Etl_ErrorRegistrar @RunId = ?, @LlaveNegocio = ?, @Payload = ?, @MensajeError = ?",
        run_id, llave_negocio, payload, mensaje_error,
    )


# --- Introspección del origen y auto-provisión de stg -----------------------

def obtener_columnas_origen(as400_cur: pyodbc.Cursor) -> list:
    deseadas = {c.upper() for c in COLUMNAS_DESEADAS}
    encontradas = {}
    for row in as400_cur.columns(table=AS400_TABLA_ORIGEN, schema=AS400_ESQUEMA_ORIGEN):
        if row.column_name.upper() in deseadas:
            encontradas[row.column_name.upper()] = {
                "nombre": row.column_name,
                "tipo_sql_server": enc.mapear_tipo_sql_server(row.type_name, row.column_size, row.decimal_digits),
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


# --- Huella y comparacion por periodo ---------------------------------------

def tablas_origen() -> str:
    """SIL con su encabezado exacto (la huella de la linea incluye datos del encabezado)."""
    sil = f"{AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}"
    sih = f"{enc.AS400_ESQUEMA_ORIGEN}.{enc.AS400_TABLA_ORIGEN}"
    return (f'{sil} l JOIN {sih} h ON h."{enc.FILTRO_COLUMNA}" = \'{enc.FILTRO_VALOR}\' '
            f'AND h."SICOMP" = l."ILCOMP" AND h."IHDPFX" = l."ILDPFX" AND h."IHDOCN" = l."ILDOCN" '
            f'AND h."IHDYR" = l."ILDYR" AND h."IHDTYP" = l."ILDTYP" AND h."SIINVD" = l."ILDATE"')


def filtro_origen() -> str:
    excluidas = ", ".join(str(c) for c in EMPRESAS_EXCLUIDAS)
    return f'l."{FILTRO_COLUMNA}" = \'{FILTRO_VALOR}\' AND l."ILCOMP" NOT IN ({excluidas})'


def columnas_huella(columnas: list, columnas_enc: list) -> list:
    """Columnas de la linea (alias l.) y luego los datos del encabezado (alias h.), en orden fijo."""
    return ([{**c, "alias": "l."} for c in columnas]
            + [{**c, "alias": "h."} for c in columnas_enc])


def periodos_a_extraer(jrm_cur, as400_cur, expr: str, desde, horizonte: int) -> tuple:
    """Compara por dia de factura el AS400 contra [int].

    Devuelve (dias comparados, dias distintos a traer, dias purgados en el AS400 que se conservan).
    """
    filtro, params = filtro_origen(), []
    filtro_local, params_local = "1 = 1", []
    if desde is not None:
        filtro += f' AND l."{COLUMNA_PERIODO}" >= ?'
        params.append(desde)
        filtro_local, params_local = "PeriodoOrigen >= ?", [desde]
    origen = huella_as400.checksum_as400(as400_cur, tablas_origen(), COLUMNA_PERIODO, filtro, params, expr)
    local = huella_as400.checksum_local(jrm_cur, INT_TABLA, "PeriodoOrigen", filtro_local, params_local)
    distintos = huella_as400.periodos_distintos(origen, local)
    purgados = [p for p in distintos if p not in origen and p < horizonte]
    a_traer = [p for p in distintos if p not in purgados]
    return len(origen.keys() | local.keys()), a_traer, purgados


def registrar_periodos(jrm_conn, jrm_cur, periodos: list, run_id: int) -> None:
    """Deja en stg los dias que el extract trae completos (silver solo da de baja en ellos)."""
    jrm_cur.execute(f"TRUNCATE TABLE {STG_PERIODOS}")
    if periodos:
        jrm_cur.executemany(f"INSERT INTO {STG_PERIODOS} (Periodo, RunId) VALUES (?, ?)",
                            [(p, run_id) for p in periodos])
    jrm_conn.commit()


# --- Extraccion / carga por lotes -------------------------------------------

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


def extraer_y_cargar(jrm_conn, jrm_cur, as400_cur, columnas: list, expr: str, periodos: list, run_id: int) -> tuple:
    """Lineas (con su huella) de los dias indicados, en lotes (fetchmany)."""
    nombres_cols = [c["nombre"] for c in columnas] + ["HUELLA"]
    llave_idx = nombres_cols.index("ILDOCN")
    col_list_sql = ", ".join(f"[{n}]" for n in nombres_cols) + ", [RunId]"
    placeholders = ", ".join(["?"] * (len(nombres_cols) + 1))
    insert_sql = f"INSERT INTO {STG_ESQUEMA}.{STG_TABLA} ({col_list_sql}) VALUES ({placeholders})"

    # DB2 for i no soporta corchetes para identificadores -- se usan comillas dobles.
    nombres = ", ".join(f'l."{c["nombre"]}"' for c in columnas)
    base = f'SELECT {nombres}, {expr} AS "HUELLA" FROM {tablas_origen()} WHERE {filtro_origen()}'

    total_leidas = total_insertadas = total_rechazadas = 0
    for bloque in huella_as400.en_bloques(periodos):
        marcas = ", ".join(["?"] * len(bloque))
        as400_cur.execute(f'{base} AND l."{COLUMNA_PERIODO}" IN ({marcas})', *bloque)
        while True:
            lote = as400_cur.fetchmany(TAMANO_LOTE)
            if not lote:
                break
            total_leidas += len(lote)
            insertadas, rechazadas = cargar_lote(jrm_conn, jrm_cur, insert_sql, nombres_cols, llave_idx, lote, run_id)
            total_insertadas += insertadas
            total_rechazadas += rechazadas
            print(f"  {total_leidas} lineas traidas", flush=True)

    return total_leidas, total_insertadas, total_rechazadas


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
        columnas_enc = enc.obtener_columnas_origen(as400_cur, enc.COLUMNAS_DATOS)
        print(f"Columnas detectadas en {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}: {len(columnas)} "
              f"(+ {len(columnas_enc)} del encabezado en la huella)")
        expr = huella_as400.expresion_huella(columnas_huella(columnas, columnas_enc))

        asegurar_tabla_stg(jrm_cur, columnas)
        jrm_cur.execute(f"TRUNCATE TABLE {STG_ESQUEMA}.{STG_TABLA}")
        jrm_conn.commit()

        hoy = datetime.date.today()
        desde = None
        if not args.reconciliar:
            desde = int((hoy - datetime.timedelta(days=DIAS_RECIENTES)).strftime("%Y%m%d"))
        horizonte = int((hoy - datetime.timedelta(days=DIAS_HORIZONTE_BAJAS)).strftime("%Y%m%d"))
        comparados, periodos, purgados = periodos_a_extraer(jrm_cur, as400_cur, expr, desde, horizonte)
        alcance = "todos los dias" if desde is None else f"dias desde {desde}"
        print(f"Comparacion ({alcance}): {comparados} dias, {len(periodos)} no cuadran")
        if purgados:
            print(f"Dias purgados en el AS400 (solo en [int], anteriores a {horizonte}; se conservan): "
                  f"{len(purgados)} ({purgados[0]} a {purgados[-1]})")
        registrar_periodos(jrm_conn, jrm_cur, periodos, run_id)

        filas_leidas, insertadas, rechazadas = extraer_y_cargar(
            jrm_conn, jrm_cur, as400_cur, columnas, expr, periodos, run_id
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
