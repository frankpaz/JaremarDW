"""
Runner de migraciones para JAREMAR.

Aplica en orden los scripts .sql de db/migrations/ que aún no se han corrido,
registrando cada uno en dbo.SchemaMigrations. Idempotente: correrlo de nuevo no
repite migraciones ya aplicadas.

Uso:
    python db/migrate.py                      # usa .env en la raíz del proyecto
    python db/migrate.py --env-file .env.prod  # para aplicar lo mismo en producción
    python db/migrate.py --dry-run             # solo muestra qué se aplicaría
"""
import argparse
import hashlib
import os
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = Path(__file__).resolve().parent / "migrations"


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


def build_connection(env: dict) -> pyodbc.Connection:
    server = env["JAREMAR_SERVER"]
    # Con instancia con nombre (server\instancia) no forzamos el puerto: la instancia
    # suele escuchar en un puerto dinámico y SQL Browser lo resuelve solo. Si se fuerza
    # ",puerto" el driver conecta por TCP directo a ese puerto, que puede ser el de otra
    # instancia (ej. la default en 1433), y falla el login con un 18456 engañoso.
    if "\\" not in server:
        server = f"{server},{env['JAREMAR_PORT']}"
    conn_str = (
        f"DRIVER={{{env['JAREMAR_ODBC_DRIVER']}}};"
        f"SERVER={server};"
        f"DATABASE={env['JAREMAR_DATABASE']};"
    )
    if env.get("JAREMAR_AUTH_MODE", "sql").lower() == "windows":
        conn_str += "Trusted_Connection=yes;"
    else:
        conn_str += f"UID={env['JAREMAR_USER']};PWD={env['JAREMAR_PASSWORD']};"
    conn_str += "TrustServerCertificate=yes;"
    return pyodbc.connect(conn_str, timeout=15)


def ensure_migrations_table(cur: pyodbc.Cursor) -> None:
    cur.execute(
        """
        IF NOT EXISTS (
            SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE s.name = 'dbo' AND t.name = 'SchemaMigrations'
        )
        BEGIN
            CREATE TABLE dbo.SchemaMigrations (
                MigrationId  VARCHAR(200) NOT NULL CONSTRAINT PK_SchemaMigrations PRIMARY KEY,
                Checksum     VARCHAR(64)  NOT NULL,
                AppliedAt    DATETIME2(7) NOT NULL CONSTRAINT DF_SchemaMigrations_AppliedAt DEFAULT (SYSDATETIME())
            );
        END
        """
    )
    cur.commit()


def applied_migrations(cur: pyodbc.Cursor) -> set:
    cur.execute("SELECT MigrationId FROM dbo.SchemaMigrations")
    return {row[0] for row in cur.fetchall()}


def split_batches(sql_text: str) -> list:
    batches, current = [], []
    for line in sql_text.splitlines():
        if line.strip().upper() == "GO":
            if current:
                batches.append("\n".join(current))
                current = []
        else:
            current.append(line)
    if current:
        batches.append("\n".join(current))
    return [b for b in batches if b.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not files:
        print("No hay archivos de migración en", MIGRATIONS_DIR)
        return 0

    cnxn = build_connection(env)
    cnxn.autocommit = False
    cur = cnxn.cursor()
    ensure_migrations_table(cur)
    done = applied_migrations(cur)

    pending = [f for f in files if f.name not in done]
    if not pending:
        print("Todo al día, nada por aplicar.")
        cnxn.close()
        return 0

    for f in pending:
        text = f.read_text(encoding="utf-8")
        checksum = hashlib.sha256(text.encode("utf-8")).hexdigest()
        if args.dry_run:
            print(f"[dry-run] aplicaría: {f.name}")
            continue

        print(f"Aplicando {f.name} ...")
        try:
            for batch in split_batches(text):
                cur.execute(batch)
            cur.execute(
                "INSERT INTO dbo.SchemaMigrations (MigrationId, Checksum) VALUES (?, ?)",
                f.name,
                checksum,
            )
            cnxn.commit()
            print(f"  OK: {f.name}")
        except Exception as exc:
            cnxn.rollback()
            print(f"  ERROR en {f.name}: {exc}", file=sys.stderr)
            cnxn.close()
            return 1

    cnxn.close()
    print("Migraciones aplicadas correctamente.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
