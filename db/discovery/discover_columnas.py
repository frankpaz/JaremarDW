"""
Discovery: estructura real de columnas de una tabla del AS400/LX, via el
catalogo del sistema QSYS2.SYSCOLUMNS (incluye COLUMN_TEXT -- la descripcion
de negocio del campo, cuando el origen la tiene cargada -- a diferencia de
cursor.columns() de pyodbc, que solo da tipo/tamano sin descripcion).

Opcionalmente (--poblacion) corre ademas un analisis de poblacion real por
columna (% de filas con valor distinto de blanco/cero), el mismo tipo de
chequeo que se hizo a mano para SIL/SIH antes de elegir columnas para
factVentas -- util para tablas ERP grandes (~100 columnas) donde muchas
resultan sin uso real.

Uso:
    python db/discovery/discover_columnas.py --schema PROLX835F --table SIL [--env-file .env]
    python db/discovery/discover_columnas.py --schema PROLX835F --table SIL --poblacion
    python db/discovery/discover_columnas.py --schema PROLX835F --table SIL --poblacion --filtro-columna ILID --filtro-valor IL
"""
import argparse
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent


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


def connect_as400(env: dict) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{{env['AS400_DRIVER']}}};"
        f"SYSTEM={env['AS400_HOST']};"
        f"UID={env['AS400_USER']};PWD={env['AS400_PASSWORD']};"
    )
    return pyodbc.connect(conn_str, timeout=30)


def obtener_columnas(cur: pyodbc.Cursor, esquema: str, tabla: str) -> list:
    cur.execute(
        """
        SELECT
            C.ORDINAL_POSITION  AS POSICION,
            C.COLUMN_NAME       AS COLUMNA,
            C.COLUMN_TEXT       AS DESCRIPCION,
            C.DATA_TYPE         AS TIPO_DATO,
            C.LENGTH            AS LONGITUD,
            C.NUMERIC_PRECISION AS PRECISION_,
            C.NUMERIC_SCALE     AS DECIMALES,
            C.IS_NULLABLE       AS PERMITE_NULL
        FROM QSYS2.SYSCOLUMNS C
        WHERE C.TABLE_SCHEMA = ?
          AND C.TABLE_NAME   = ?
        ORDER BY C.ORDINAL_POSITION
        """,
        esquema, tabla,
    )
    return cur.fetchall()


def imprimir_columnas(columnas: list) -> None:
    print(f"{len(columnas)} columna(s):\n")
    print(f"{'#':>3} {'COLUMNA':<10} {'TIPO':<12} {'LARGO':>6} {'PREC':>5} {'DEC':>4} {'NULL':<5} DESCRIPCION")
    print("-" * 100)
    for pos, col, desc, tipo, largo, precision, decimales, permite_null in columnas:
        print(
            f"{pos:>3} {col:<10} {(tipo or ''):<12} {largo if largo is not None else '':>6} "
            f"{precision if precision is not None else '':>5} {decimales if decimales is not None else '':>4} "
            f"{(permite_null or ''):<5} {desc or ''}"
        )


def analizar_poblacion(cur, esquema, tabla, columnas, filtro_columna=None, filtro_valor=None, batch=10):
    where = ""
    params = []
    if filtro_columna and filtro_valor:
        where = f' WHERE "{filtro_columna}" = ?'
        params.append(filtro_valor)

    cur.execute(f'SELECT COUNT(*) FROM {esquema}.{tabla}{where}', *params)
    total = cur.fetchone()[0]
    print(f"\nTotal filas{' (filtradas)' if where else ''}: {total}\n")
    if total == 0:
        return

    nombres_tipos = [(c[1], (c[3] or "").upper()) for c in columnas]
    resultados = {}
    for i in range(0, len(nombres_tipos), batch):
        lote = nombres_tipos[i:i + batch]
        exprs = []
        for nombre, tipo in lote:
            if "CHAR" in tipo:
                exprs.append(f"SUM(CASE WHEN TRIM(\"{nombre}\") <> '' THEN 1 ELSE 0 END)")
            elif "DEC" in tipo or "NUM" in tipo or "INT" in tipo:
                exprs.append(f"SUM(CASE WHEN \"{nombre}\" <> 0 THEN 1 ELSE 0 END)")
            else:
                exprs.append(f"SUM(CASE WHEN \"{nombre}\" IS NOT NULL THEN 1 ELSE 0 END)")
        sql = f"SELECT {', '.join(exprs)} FROM {esquema}.{tabla}{where}"
        cur.execute(sql, *params)
        fila = cur.fetchone()
        for (nombre, _), val in zip(lote, fila):
            resultados[nombre] = val

    print(f"{'COLUMNA':<10} {'POBLADO':>10} {'%':>7}")
    print("-" * 32)
    for nombre, _ in nombres_tipos:
        val = resultados[nombre]
        pct = (val / total * 100) if total else 0
        print(f"{nombre:<10} {val:>10} {pct:>6.1f}%")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", required=True, help="Esquema/biblioteca AS400 (ej. PROLX835F)")
    parser.add_argument("--table", required=True, help="Nombre de la tabla/archivo (ej. SIL)")
    parser.add_argument("--poblacion", action="store_true", help="Ademas corre analisis de poblacion real por columna")
    parser.add_argument("--filtro-columna", default=None, help="Columna a filtrar para el analisis de poblacion (ej. ILID)")
    parser.add_argument("--filtro-valor", default=None, help="Valor del filtro (ej. IL)")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    conn = connect_as400(env)
    cur = conn.cursor()

    columnas = obtener_columnas(cur, args.schema, args.table)
    if not columnas:
        print(f"No se encontraron columnas para {args.schema}.{args.table} -- revisa esquema/nombre.")
        conn.close()
        return 1

    imprimir_columnas(columnas)

    if args.poblacion:
        analizar_poblacion(cur, args.schema, args.table, columnas, args.filtro_columna, args.filtro_valor)

    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
