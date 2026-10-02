"""
Huella por fila calculada en el AS400 y comparacion por periodo (carga incremental por hash).

El AS400 (IBM i 7.3) no tiene HASH_MD5/HASH_SHA*, y HASH() es de particion (0-1023; sobre
columnas numericas de una tabla devuelve 0). La huella se arma con ENCRYPT_RC2, que es
determinista y encadena los bloques (CBC): su ultimo bloque de 8 bytes depende de toda la
fila, asi que cambia si cambia cualquier valor. Se toma como BIGINT con INTERPRET.

SQL Server no puede recalcular ese numero, por eso el extract trae la huella de cada fila y
[int] la guarda (HuellaOrigen). Para saber que cambio sin traer todo, se compara por periodo
(normalmente la fecha del documento, tal cual viene del AS400) la cantidad de filas y la suma
de huellas en el AS400 contra lo mismo en [int]; solo se extraen los periodos que no cuadran.

Las sumas se hacen en DECIMAL(31,0) para que no desborden (cada huella llega a 9,2e18).

Uso tipico en un extract:
    expr = expresion_huella(columnas)                       # columnas: [{"nombre", "es_texto"}]
    origen = checksum_as400(as400_cur, "ESQ.TABLA", "FECDOC", "FECDOC >= ?", [20260801])
    local = checksum_local(jrm_cur, "[int].tabla", "PeriodoOrigen", "PeriodoOrigen >= ?", [20260801])
    periodos = periodos_distintos(origen, local)
"""
# Clave fija del cifrado: no protege nada, solo hace falta que sea siempre la misma.
# Si se cambia, todas las huellas guardadas dejan de cuadrar y la siguiente corrida
# vuelve a extraer todo.
CLAVE_HUELLA = "JaremarDW"

# Separador entre columnas y marca de NULL dentro del texto que se cifra.
SEPARADOR = "|"
MARCA_NULL = "~"

TAMANO_BLOQUE_IN = 500


def es_tipo_texto(type_name: str) -> bool:
    return "CHAR" in (type_name or "").upper() or "GRAPHIC" in (type_name or "").upper()


def expresion_huella(columnas: list, alias: str = "") -> str:
    """Expresion DB2 for i (BIGINT) con la huella de la fila.

    columnas: lista de dicts con "nombre" y "es_texto", en un orden fijo (el orden forma parte
    de la huella). El texto va con RTRIM para que los blancos de relleno no cuenten.
    """
    partes = []
    for c in columnas:
        col = f'{alias}"{c["nombre"]}"'
        valor = f"RTRIM({col})" if c["es_texto"] else f"CHAR({col})"
        partes.append(f"COALESCE({valor}, '{MARCA_NULL}')")
    texto = f" || '{SEPARADOR}' || ".join(partes)
    cifrado = f"ENCRYPT_RC2({texto}, '{CLAVE_HUELLA}')"
    return f"INTERPRET(CAST(SUBSTR({cifrado}, LENGTH({cifrado}) - 7, 8) AS BINARY(8)) AS BIGINT)"


def checksum_as400(as400_cur, tabla: str, col_periodo: str, filtro: str, params: list,
                   expr_huella: str) -> dict:
    """{periodo: (filas, suma_huellas)} del AS400. filtro es SQL DB2 con '?' (sin WHERE)."""
    as400_cur.execute(
        f'SELECT "{col_periodo}", COUNT(*), SUM(CAST({expr_huella} AS DECIMAL(31,0))) '
        f"FROM {tabla} WHERE {filtro} GROUP BY \"{col_periodo}\"",
        *params,
    )
    return {_entero(p): (int(n), _entero(s)) for p, n, s in as400_cur.fetchall()}


def checksum_local(jrm_cur, tabla: str, col_periodo: str, filtro: str, params: list,
                   col_filas: str = "Repeticiones", col_huella: str = "HuellaOrigen") -> dict:
    """{periodo: (filas, suma_huellas)} de [int], solo filas vigentes. Una huella NULL (fila
    cargada antes de guardar huellas) deja la suma en NULL y el periodo no cuadra."""
    jrm_cur.execute(
        f"SELECT {col_periodo}, SUM({col_filas}), "
        f"CASE WHEN COUNT({col_huella}) = COUNT(*) THEN SUM(CAST({col_huella} AS DECIMAL(38,0))) END "
        f"FROM {tabla} WHERE EsVigente = 1 AND {col_periodo} IS NOT NULL AND {filtro} "
        f"GROUP BY {col_periodo}",
        *params,
    )
    return {_entero(p): (int(n), _entero(s)) for p, n, s in jrm_cur.fetchall()}


def periodos_distintos(origen: dict, local: dict) -> list:
    """Periodos que no cuadran: con distinta cantidad o suma, o que estan de un solo lado."""
    return sorted(p for p in origen.keys() | local.keys() if origen.get(p) != local.get(p))


def en_bloques(valores: list, tamano: int = TAMANO_BLOQUE_IN):
    for i in range(0, len(valores), tamano):
        yield valores[i:i + tamano]


TAMANO_BLOQUE_TUPLAS = 100


def condicion_tuplas(expresiones: list, cantidad: int) -> str:
    """'(e1 = ? AND e2 = ?) OR (...)' para buscar en el AS400 por llaves compuestas.

    expresiones: SQL DB2 de cada parte de la llave (ej. '"PLCMPY"', 'RTRIM("PLINV")').
    Los parametros van aplanados, tupla por tupla, en el mismo orden.
    """
    una = "(" + " AND ".join(f"{e} = ?" for e in expresiones) + ")"
    return " OR ".join([una] * cantidad)


def _entero(valor):
    # Periodos y sumas llegan como Decimal (DB2 y SQL Server); se comparan como int.
    return None if valor is None else int(valor)
