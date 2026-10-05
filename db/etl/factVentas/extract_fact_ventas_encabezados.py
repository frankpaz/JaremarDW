"""
Extraccion Bronze: AS400/LX (PROLX835F.SIH, SIID='IH') -> stg.factVentasEncabezados
en JAREMAR.

SIH es el encabezado de factura del ERP, 1:N con PROLX835F.SIL (factVentasLineas). Solo se
extraen columnas que enriquecen la linea con datos que no existen en SIL: moneda/conversion
(SICURR/SICNFC/SIGCNV), terminos de pago y transporte (SITERM/SICARR/SIROUT) y auditoria de
creacion (IHENDT/IHENTM/IHENUS), mas la llave.

Carga incremental por huella (migraciones 253-255, ver db/etl/huella_as400.py). Corre DESPUES
del extract de lineas: este decide que dias de factura no cuadran con el AS400 (los deja en
stg.factVentas_Periodos) y aqui se traen todos los encabezados de esos dias (SIINVD), para que
silver le ponga a cada linea su encabezado. La llave del encabezado es compania + prefijo +
documento + anio + tipo + fecha de factura (SICOMP + IHDPFX/IHDOCN/IHDYR/IHDTYP + SIINVD):
sin compania ni fecha se repite (facturas distintas que reusan el numero). SIINVD = ILDATE en
todas las lineas.

Los cambios de un encabezado se detectan por la huella de sus lineas, que incluye las columnas
de COLUMNAS_DATOS (ver extract_fact_ventas_lineas.py).

Uso:
    python db/etl/factVentas/extract_fact_ventas_encabezados.py [--env-file .env] [--reconciliar]
    (--reconciliar se acepta por compatibilidad con run_fact.py; los dias los decide el extract de lineas)
"""
import argparse
import json
import sys
from pathlib import Path

import pyodbc

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import huella_as400  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "Ventas_Encabezados"
PROCESO_LINEAS = "Ventas_Lineas"
AS400_ESQUEMA_ORIGEN = "PROLX835F"
AS400_TABLA_ORIGEN = "SIH"
FILTRO_COLUMNA = "SIID"
FILTRO_VALOR = "IH"
COLUMNA_PERIODO = "SIINVD"
STG_ESQUEMA = "stg"
STG_TABLA = "factVentasEncabezados"
STG_PERIODOS = "stg.factVentas_Periodos"
TAMANO_LOTE = 10000

# Datos del encabezado que viajan a cada linea (y forman parte de la huella de la linea).
COLUMNAS_DATOS = [
    "SICURR", "SICNFC", "SIGCNV",
    "SITERM", "SICARR", "SIROUT",
    "IHENDT", "IHENTM", "IHENUS",
]
COLUMNAS_DESEADAS = ["SICOMP", "IHDPFX", "IHDOCN", "IHDYR", "IHDTYP", "SIINVD"] + COLUMNAS_DATOS


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


def obtener_columnas_origen(as400_cur: pyodbc.Cursor, nombres: list = None) -> list:
    """Columnas de SIH (por defecto COLUMNAS_DESEADAS) con su tipo en SQL Server y si son texto."""
    nombres = nombres or COLUMNAS_DESEADAS
    deseadas = {c.upper() for c in nombres}
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

    return [encontradas[c.upper()] for c in nombres]


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


# --- Dias a traer -------------------------------------------------------------

def verificar_extract_lineas(jrm_cur) -> None:
    """Los dias los decide el extract de lineas de este mismo ciclo (corre antes)."""
    jrm_cur.execute(
        """
        SELECT TOP 1 r.FechaInicio FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE p.ProcesoNombre = 'Ventas_Silver' AND r.Estado = 'EXITO' ORDER BY r.RunId DESC
        """
    )
    row = jrm_cur.fetchone()
    ultimo_silver = row[0] if row else None
    jrm_cur.execute(
        """
        SELECT TOP 1 r.Estado, r.FechaFin FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE p.ProcesoNombre = ? ORDER BY r.RunId DESC
        """,
        PROCESO_LINEAS,
    )
    row = jrm_cur.fetchone()
    if row is None or row[0] not in ("EXITO", "ADVERTENCIA"):
        raise RuntimeError(f"El extract {PROCESO_LINEAS} no termino bien; correrlo antes que los encabezados.")
    if ultimo_silver is not None and row[1] is not None and row[1] <= ultimo_silver:
        raise RuntimeError(f"El extract {PROCESO_LINEAS} no se ha vuelto a correr desde el ultimo Silver; correrlo antes que los encabezados.")


def periodos_registrados(jrm_cur) -> list:
    jrm_cur.execute(f"SELECT Periodo FROM {STG_PERIODOS} ORDER BY Periodo")
    return [int(r[0]) for r in jrm_cur.fetchall()]


# --- Extraccion / carga por lotes -------------------------------------------

def consulta_origen(columnas: list) -> str:
    # DB2 for i no soporta corchetes para identificadores -- se usan comillas dobles.
    nombres = ", ".join(f'"{c["nombre"]}"' for c in columnas)
    return (f"SELECT {nombres} FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN} "
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


def extraer_y_cargar(jrm_conn, jrm_cur, as400_cur, columnas: list, periodos: list, run_id: int) -> tuple:
    """Encabezados de los dias de factura indicados, en lotes (fetchmany)."""
    nombres_cols = [c["nombre"] for c in columnas]
    llave_idx = nombres_cols.index("IHDOCN")
    col_list_sql = ", ".join(f"[{n}]" for n in nombres_cols) + ", [RunId]"
    placeholders = ", ".join(["?"] * (len(nombres_cols) + 1))
    insert_sql = f"INSERT INTO {STG_ESQUEMA}.{STG_TABLA} ({col_list_sql}) VALUES ({placeholders})"

    base = consulta_origen(columnas)
    total_leidas = total_insertadas = total_rechazadas = 0
    for bloque in huella_as400.en_bloques(periodos):
        marcas = ", ".join(["?"] * len(bloque))
        as400_cur.execute(f'{base} AND "{COLUMNA_PERIODO}" IN ({marcas})', *bloque)
        while True:
            lote = as400_cur.fetchmany(TAMANO_LOTE)
            if not lote:
                break
            total_leidas += len(lote)
            insertadas, rechazadas = cargar_lote(jrm_conn, jrm_cur, insert_sql, nombres_cols, llave_idx, lote, run_id)
            total_insertadas += insertadas
            total_rechazadas += rechazadas
        print(f"  {total_leidas} encabezados traidos", flush=True)

    return total_leidas, total_insertadas, total_rechazadas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--reconciliar", action="store_true",
                        help="Sin efecto: los dias a traer los decide el extract de lineas.")
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
        verificar_extract_lineas(jrm_cur)
        as400_cur = as400_conn.cursor()
        columnas = obtener_columnas_origen(as400_cur)
        print(f"Columnas detectadas en {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}: {len(columnas)}")

        asegurar_tabla_stg(jrm_cur, columnas)
        jrm_cur.execute(f"TRUNCATE TABLE {STG_ESQUEMA}.{STG_TABLA}")
        jrm_conn.commit()

        periodos = periodos_registrados(jrm_cur)
        print(f"Dias de factura a traer (los que no cuadraron en las lineas): {len(periodos)}")
        filas_leidas, insertadas, rechazadas = extraer_y_cargar(jrm_conn, jrm_cur, as400_cur, columnas, periodos, run_id)
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
