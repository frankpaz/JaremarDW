"""
Discovery: busca o lista tablas del AS400/LX usando el catalogo del sistema
QSYS2.SYSTABLES (nombre + descripcion de negocio).

Util para encontrar la tabla de origen correcta antes de armar un pipeline
nuevo, sin tener que adivinar el nombre tecnico de memoria (ej. el maestro
de clientes puede llamarse ARCUST, CUST, CLIMTA, etc. segun el ERP).

Dos modos:
- Busqueda por palabra clave (--like): filtra por nombre o descripcion.
- Listado completo de una libreria (--schema sin --like): trae TODAS las
  tablas fisicas (TABLE_TYPE='P' por defecto, --tipo para cambiarlo) --
  util para reconocimiento general de una libreria nueva, no solo cuando
  ya se tiene una palabra clave en mente.

Uso:
    python db/discovery/buscar_tablas.py --like CUST [--schema PROLX835F] [--env-file .env]
    python db/discovery/buscar_tablas.py --like CLIENTE --schema PROLXUSRF
    python db/discovery/buscar_tablas.py --schema PROLX835F              # todas las tablas fisicas
    python db/discovery/buscar_tablas.py --schema PROLX835F --tipo L     # solo logicas (indices)
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


def buscar(cur: pyodbc.Cursor, patron: str, esquema: str | None) -> list:
    like = f"%{patron.upper()}%"
    if esquema:
        cur.execute(
            """
            SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TEXT, TABLE_TYPE
            FROM QSYS2.SYSTABLES
            WHERE TABLE_SCHEMA = ?
              AND (UPPER(TABLE_NAME) LIKE ? OR UPPER(COALESCE(TABLE_TEXT, '')) LIKE ?)
            ORDER BY TABLE_NAME
            """,
            esquema, like, like,
        )
    else:
        cur.execute(
            """
            SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TEXT, TABLE_TYPE
            FROM QSYS2.SYSTABLES
            WHERE UPPER(TABLE_NAME) LIKE ? OR UPPER(COALESCE(TABLE_TEXT, '')) LIKE ?
            ORDER BY TABLE_SCHEMA, TABLE_NAME
            """,
            like, like,
        )
    return cur.fetchall()


def listar(cur: pyodbc.Cursor, esquema: str, tipo: str) -> list:
    cur.execute(
        """
        SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TEXT, TABLE_TYPE
        FROM QSYS2.SYSTABLES
        WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = ?
        ORDER BY TABLE_NAME
        """,
        esquema, tipo,
    )
    return cur.fetchall()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--like", default=None, help="Palabra clave a buscar en nombre o descripcion de la tabla (omitir para listar todo)")
    parser.add_argument("--schema", default=None, help="Esquema/biblioteca (ej. PROLX835F). Obligatorio si no se pasa --like")
    parser.add_argument("--tipo", default="P", help="TABLE_TYPE a listar cuando no hay --like: P=fisica (defecto), L=logica, V=vista")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    if not args.like and not args.schema:
        parser.error("--schema es obligatorio cuando no se pasa --like (listado completo de una libreria)")

    env = load_env(Path(args.env_file))
    conn = connect_as400(env)
    cur = conn.cursor()

    if args.like:
        filas = buscar(cur, args.like, args.schema)
    else:
        filas = listar(cur, args.schema, args.tipo)
    conn.close()

    if not filas:
        if args.like:
            print(f"Sin resultados para '{args.like}'" + (f" en {args.schema}" if args.schema else ""))
        else:
            print(f"Sin tablas tipo '{args.tipo}' en {args.schema}")
        return 0

    print(f"{len(filas)} tabla(s) encontradas:\n")
    print(f"{'ESQUEMA':<12} {'TABLA':<12} {'TIPO':<6} DESCRIPCION")
    print("-" * 80)
    for esquema, tabla, texto, tipo in filas:
        print(f"{esquema:<12} {tabla:<12} {(tipo or ''):<6} {texto or ''}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
