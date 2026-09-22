"""
Discovery: busca tablas candidatas en el AS400/LX por palabra clave, usando
el catalogo del sistema QSYS2.SYSTABLES (nombre + descripcion de negocio).

Util para encontrar la tabla de origen correcta antes de armar un pipeline
nuevo, sin tener que adivinar el nombre tecnico de memoria (ej. el maestro
de clientes puede llamarse ARCUST, CUST, CLIMTA, etc. segun el ERP).

Uso:
    python db/discovery/buscar_tablas.py --like CUST [--schema PROLX835F] [--env-file .env]
    python db/discovery/buscar_tablas.py --like CLIENTE --schema PROLXUSRF
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--like", required=True, help="Palabra clave a buscar en nombre o descripcion de la tabla")
    parser.add_argument("--schema", default=None, help="Limitar la busqueda a un esquema/biblioteca (ej. PROLX835F)")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    conn = connect_as400(env)
    cur = conn.cursor()

    filas = buscar(cur, args.like, args.schema)
    conn.close()

    if not filas:
        print(f"Sin resultados para '{args.like}'" + (f" en {args.schema}" if args.schema else ""))
        return 0

    print(f"{len(filas)} tabla(s) encontradas:\n")
    print(f"{'ESQUEMA':<12} {'TABLA':<12} {'TIPO':<6} DESCRIPCION")
    print("-" * 80)
    for esquema, tabla, texto, tipo in filas:
        print(f"{esquema:<12} {tabla:<12} {(tipo or ''):<6} {texto or ''}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
