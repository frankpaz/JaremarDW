"""
Extraccion Bronze: AS400/LX (PROLX835F.APL, PLID='PL') -> stg.factComprasLineas
en JAREMAR.

APL es el detalle contable de facturas de proveedor del ERP ("Payables Line
File"): no tiene producto ni cantidad, es la distribucion contable de cada
factura. Historia desde 2004, util desde 2019 (antes el ERP purgo lineas).

Carga incremental por huella (migraciones 248-250, ver db/etl/huella_as400.py).
Corre DESPUES del extract de encabezados (usa lo que este dejo en stg):
  1. Compara por dia de creacion (PLEDTE tal cual del AS400; 0 para las 1.302
     lineas sin fecha, que antes nunca se cargaban) la cantidad de lineas y la
     suma de sus huellas contra [int].factCompras, y trae las lineas de los dias
     que no cuadran (quedan en stg.factComprasLineas_Periodos). La corrida normal
     compara los ultimos DIAS_RECIENTES dias y las fechas posteriores;
     --reconciliar compara todos.
  2. Trae tambien las lineas de los encabezados nuevos o cambiados (pagos) que
     esten en [int] fuera de esos dias, para refrescar sus datos de encabezado.
  3. Agrega a stg.factComprasEncabezados los encabezados que les falten a las
     lineas traidas (todos los del documento, para que silver sepa si es uno solo).
Las lineas vigentes de [int] de un dia revisado que no vinieron ya no estan en el
AS400 (la fecha es parte de la llave): silver las da de baja.

Llave: compania + prefijo + anio + secuencia + linea + proveedor + factura
(PLVNDR/PLINV) + fecha de creacion (PLEDTE; el ERP recaptura algunas lineas otro
dia con la misma llave). Las lineas repetidas del mismo dia se guardan una vez en
[int] con Repeticiones y la suma de sus huellas.

Se extrae e inserta en lotes (fetchmany): el driver ODBC del AS400 puede morir a
mitad de una extraccion grande sin excepcion capturable (ver factVentas).

Uso:
    python db/etl/factCompras/extract_fact_compras_lineas.py [--env-file .env] [--reconciliar]
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
import extract_fact_compras_encabezados as enc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA_CACHE_DIR = Path(__file__).resolve().parent / "schema_cache"

PROCESO = "Compras_Lineas"
AS400_ESQUEMA_ORIGEN = "PROLX835F"
AS400_TABLA_ORIGEN = "APL"
FILTRO_COLUMNA = "PLID"
FILTRO_VALOR = "PL"
COLUMNA_PERIODO = "PLEDTE"
STG_ESQUEMA = "stg"
STG_TABLA = "factComprasLineas"
STG_PERIODOS = "stg.factComprasLineas_Periodos"
INT_TABLA = "[int].factCompras"
DIAS_RECIENTES = 45
TAMANO_LOTE = 10000
# Con mas documentos sin encabezado que esto, se traen por dia en vez de documento por documento.
MAX_DOCUMENTOS_POR_TUPLAS = 2000

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

def verificar_extract_encabezados(jrm_cur) -> None:
    """Las lineas usan los encabezados que dejo en stg el extract de encabezados de este ciclo."""
    jrm_cur.execute(
        """
        SELECT TOP 1 r.FechaInicio FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE p.ProcesoNombre = 'Compras_Silver' AND r.Estado = 'EXITO' ORDER BY r.RunId DESC
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
        enc.PROCESO,
    )
    row = jrm_cur.fetchone()
    if row is None or row[0] not in ("EXITO", "ADVERTENCIA"):
        raise RuntimeError(f"El extract {enc.PROCESO} no termino bien; correrlo antes que las lineas.")
    if ultimo_silver is not None and row[1] is not None and row[1] <= ultimo_silver:
        raise RuntimeError(f"El extract {enc.PROCESO} no se ha vuelto a correr desde el ultimo Silver; correrlo antes que las lineas.")


def periodos_a_extraer(jrm_cur, as400_cur, columnas: list, desde) -> tuple:
    """Compara por dia de creacion el AS400 contra [int]; (dias comparados, distintos)."""
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
    local = huella_as400.checksum_local(jrm_cur, INT_TABLA, "PeriodoOrigen", filtro_local, params_local)
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


class Cargador:
    """Inserta en una tabla de stg filas del AS400 (columnas + HUELLA) y lleva la cuenta."""

    def __init__(self, jrm_conn, jrm_cur, tabla: str, columnas: list, llave: str, run_id: int):
        self.jrm_conn, self.jrm_cur, self.run_id = jrm_conn, jrm_cur, run_id
        self.nombres = [c["nombre"] for c in columnas] + ["HUELLA"]
        cols = ", ".join(f"[{n}]" for n in self.nombres) + ", [RunId]"
        marcas = ", ".join(["?"] * (len(self.nombres) + 1))
        self.insert_sql = f"INSERT INTO {tabla} ({cols}) VALUES ({marcas})"
        self.llave_idx = self.nombres.index(llave)
        self.leidas = self.insertadas = self.rechazadas = 0

    def cargar(self, filas: list) -> None:
        for i in range(0, len(filas), TAMANO_LOTE):
            lote = filas[i:i + TAMANO_LOTE]
            self.leidas += len(lote)
            ins, rech = cargar_lote(self.jrm_conn, self.jrm_cur, self.insert_sql, self.nombres,
                                    self.llave_idx, lote, self.run_id)
            self.insertadas += ins
            self.rechazadas += rech

    def cargar_cursor(self, as400_cur, filtro=None) -> None:
        while True:
            lote = as400_cur.fetchmany(TAMANO_LOTE)
            if not lote:
                break
            self.cargar([f for f in lote if filtro is None or filtro(f)])


def buscar_por_tuplas(as400_cur, base: str, expresiones: list, tuplas: list):
    """Filas del AS400 de base (que ya trae su WHERE) cuya llave compuesta esta en tuplas."""
    filas = []
    for bloque in huella_as400.en_bloques(tuplas, huella_as400.TAMANO_BLOQUE_TUPLAS):
        condicion = huella_as400.condicion_tuplas(expresiones, len(bloque))
        as400_cur.execute(f"{base} AND ({condicion})", *[v for t in bloque for v in t])
        filas.extend(as400_cur.fetchall())
    return filas


def lineas_de_encabezados_cambiados(jrm_cur) -> list:
    """Documentos con algun encabezado nuevo o cambiado que tienen lineas en [int] fuera de los
    dias revisados: hay que volver a traer esas lineas para refrescar sus datos de encabezado."""
    jrm_cur.execute(
        f"""
        ;WITH Cambiados AS (
            SELECT DISTINCT e.APCMPY, e.PHDCPX, e.PHDCYR, e.PHDCSQ
            FROM {enc.STG_ESQUEMA}.{enc.STG_TABLA} e
            LEFT JOIN {enc.INT_CONTROL} c
              ON c.APCMPY = e.APCMPY AND c.PHDCPX = e.PHDCPX AND c.PHDCYR = e.PHDCYR AND c.PHDCSQ = e.PHDCSQ
             AND c.APVNDR = ISNULL(e.APVNDR, 0) AND c.APINV = ISNULL(RTRIM(e.APINV), N'')
            WHERE c.APCMPY IS NULL OR c.EsVigente = 0
               OR ISNULL(c.HuellaOrigen, -1) <> CAST(e.HUELLA AS DECIMAL(30,0))
        )
        SELECT DISTINCT i.PLCMPY, i.PLDCPX, i.PLDCYR, i.PLDCSQ
        FROM {INT_TABLA} i
        JOIN Cambiados c ON c.APCMPY = i.PLCMPY AND c.PHDCPX = i.PLDCPX AND c.PHDCYR = i.PLDCYR AND c.PHDCSQ = i.PLDCSQ
        WHERE i.EsVigente = 1
          AND NOT EXISTS (SELECT 1 FROM {STG_PERIODOS} p WHERE p.Periodo = i.PeriodoOrigen)
        """
    )
    return [tuple(r) for r in jrm_cur.fetchall()]


def documentos_sin_encabezado(jrm_cur) -> list:
    """Documentos de lineas de stg sin su encabezado exacto (documento + proveedor + factura) en stg."""
    jrm_cur.execute(
        f"""
        SELECT DISTINCT l.PLCMPY, l.PLDCPX, l.PLDCYR, l.PLDCSQ
        FROM {STG_ESQUEMA}.{STG_TABLA} l
        WHERE NOT EXISTS (SELECT 1 FROM {enc.STG_ESQUEMA}.{enc.STG_TABLA} e
                          WHERE e.APCMPY = l.PLCMPY AND e.PHDCPX = l.PLDCPX AND e.PHDCYR = l.PLDCYR
                            AND e.PHDCSQ = l.PLDCSQ AND ISNULL(e.APVNDR, 0) = ISNULL(l.PLVNDR, -1)
                            AND ISNULL(RTRIM(e.APINV), N'') = ISNULL(RTRIM(l.PLINV), N''))
        """
    )
    return [tuple(r) for r in jrm_cur.fetchall()]


def encabezados_en_stg(jrm_cur) -> set:
    """Llaves (documento + proveedor + factura) de los encabezados que ya estan en stg."""
    jrm_cur.execute(
        f"SELECT APCMPY, PHDCPX, PHDCYR, PHDCSQ, ISNULL(APVNDR, 0), ISNULL(RTRIM(APINV), N'') "
        f"FROM {enc.STG_ESQUEMA}.{enc.STG_TABLA}"
    )
    return {llave_encabezado(r) for r in jrm_cur.fetchall()}


def encabezados_de_dias(as400_cur, columnas_enc: list, periodos: list) -> list:
    """Encabezados de los documentos que tienen lineas en esos dias de creacion (una consulta por
    bloque de dias; mas rapido que buscar documento por documento cuando son muchos)."""
    tabla = f"{enc.AS400_ESQUEMA_ORIGEN}.{enc.AS400_TABLA_ORIGEN}"
    filas = []
    for bloque in huella_as400.en_bloques(periodos):
        marcas = ", ".join(["?"] * len(bloque))
        as400_cur.execute(
            f"{enc.consulta_origen(columnas_enc)} AND EXISTS ("
            f"SELECT 1 FROM {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN} l "
            f"WHERE l.\"{FILTRO_COLUMNA}\" = '{FILTRO_VALOR}' AND l.\"PLCMPY\" = {tabla}.\"APCMPY\" "
            f"AND l.\"PLDCPX\" = {tabla}.\"PHDCPX\" AND l.\"PLDCYR\" = {tabla}.\"PHDCYR\" "
            f"AND l.\"PLDCSQ\" = {tabla}.\"PHDCSQ\" AND l.\"{COLUMNA_PERIODO}\" IN ({marcas}))",
            *bloque,
        )
        filas.extend(as400_cur.fetchall())
    return filas


def llave_encabezado(fila) -> tuple:
    return (int(fila[0]), fila[1].strip(), int(fila[2]), int(fila[3]), int(fila[4] or 0), (fila[5] or "").strip())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--reconciliar", action="store_true",
                        help="Compara todos los dias de creacion, no solo los recientes.")
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
        verificar_extract_encabezados(jrm_cur)
        as400_cur = as400_conn.cursor()
        columnas = obtener_columnas_origen(as400_cur)
        print(f"Columnas detectadas en {AS400_ESQUEMA_ORIGEN}.{AS400_TABLA_ORIGEN}: {len(columnas)}")

        asegurar_tabla_stg(jrm_cur, columnas)
        jrm_cur.execute(f"TRUNCATE TABLE {STG_ESQUEMA}.{STG_TABLA}")
        jrm_conn.commit()

        # 1. Lineas de los dias de creacion que no cuadran.
        desde = None
        if not args.reconciliar:
            desde = int((datetime.date.today() - datetime.timedelta(days=DIAS_RECIENTES)).strftime("%Y%m%d"))
        comparados, periodos = periodos_a_extraer(jrm_cur, as400_cur, columnas, desde)
        alcance = "todos los dias" if desde is None else f"dias desde {desde}"
        print(f"Comparacion de lineas ({alcance}): {comparados} dias, {len(periodos)} no cuadran")
        registrar_periodos(jrm_conn, jrm_cur, periodos, run_id)

        lineas = Cargador(jrm_conn, jrm_cur, f"{STG_ESQUEMA}.{STG_TABLA}", columnas, "PLDCSQ", run_id)
        base = consulta_origen(columnas)
        for bloque in huella_as400.en_bloques(periodos):
            marcas = ", ".join(["?"] * len(bloque))
            as400_cur.execute(f'{base} AND "{COLUMNA_PERIODO}" IN ({marcas})', *bloque)
            lineas.cargar_cursor(as400_cur)
            print(f"  {lineas.leidas} lineas traidas", flush=True)

        # 2. Lineas de encabezados que cambiaron (fuera de los dias ya traidos).
        revisados = set(periodos)
        idx_periodo = [c["nombre"] for c in columnas].index(COLUMNA_PERIODO)
        documentos = lineas_de_encabezados_cambiados(jrm_cur)
        antes = lineas.leidas
        filas = buscar_por_tuplas(as400_cur, base, ['"PLCMPY"', '"PLDCPX"', '"PLDCYR"', '"PLDCSQ"'], documentos)
        lineas.cargar([f for f in filas if int(f[idx_periodo]) not in revisados])
        print(f"Lineas de encabezados que cambiaron: {lineas.leidas - antes} (de {len(documentos)} documentos)")

        # 3. Encabezados que les falten a las lineas traidas: se traen todos los del documento,
        #    para que silver sepa si el documento tiene un solo encabezado.
        faltan = documentos_sin_encabezado(jrm_cur)
        columnas_enc = enc.obtener_columnas_origen(as400_cur)
        encabezados = Cargador(jrm_conn, jrm_cur, f"{enc.STG_ESQUEMA}.{enc.STG_TABLA}", columnas_enc, "PHDCSQ", run_id)
        if faltan:
            presentes = encabezados_en_stg(jrm_cur)
            if len(faltan) <= MAX_DOCUMENTOS_POR_TUPLAS:
                filas = buscar_por_tuplas(as400_cur, enc.consulta_origen(columnas_enc),
                                          ['"APCMPY"', '"PHDCPX"', '"PHDCYR"', '"PHDCSQ"'], faltan)
            else:
                filas = encabezados_de_dias(as400_cur, columnas_enc, periodos)
            nombres = [c["nombre"] for c in columnas_enc]
            pos = [nombres.index(c) for c in ("APCMPY", "PHDCPX", "PHDCYR", "PHDCSQ", "APVNDR", "APINV")]
            encabezados.cargar([f for f in filas if llave_encabezado([f[i] for i in pos]) not in presentes])
        print(f"Encabezados agregados para las lineas: {encabezados.leidas} (de {len(faltan)} documentos)")

        rechazadas = lineas.rechazadas + encabezados.rechazadas
        print(f"Total leidas: {lineas.leidas} / Insertadas: {lineas.insertadas} / Rechazadas: {lineas.rechazadas}")

        finalizar_run(
            jrm_cur, run_id, "EXITO" if rechazadas == 0 else "ADVERTENCIA",
            filas_leidas=lineas.leidas, filas_insertadas=lineas.insertadas, filas_rechazadas=rechazadas,
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
