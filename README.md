# JaremarDW

Data warehouse de Jaremar en SQL Server (base `JAREMAR`). Un ETL en Python (`pyodbc`) mueve datos desde el AS400/LX (DB2 for i) hacia el warehouse, siguiendo arquitectura medallion (Bronze `stg` -> Silver `[int]` -> Gold `dw`), con un framework de control propio en el esquema `dbo` que registra cada corrida (proceso, run, watermark, errores).

## Setup

```
cp .env.example .env
```

Completar en `.env`:

- Conexión a JAREMAR (SQL Server): `JAREMAR_SERVER`, `JAREMAR_PORT`, `JAREMAR_DATABASE`, `JAREMAR_AUTH_MODE` (`sql` o `windows`), `JAREMAR_USER`/`JAREMAR_PASSWORD`, `JAREMAR_ODBC_DRIVER` (ej. `ODBC Driver 17 for SQL Server`).
- Conexión al AS400/LX (origen): `AS400_HOST`, `AS400_USER`, `AS400_PASSWORD`, `AS400_DRIVER` (ej. `iSeries Access ODBC Driver`).

`.env` nunca se sube a git. La única dependencia externa de los scripts es `pyodbc`.

## Migraciones

Los cambios de esquema (tablas de control, tablas `[int]`/`dw` y sus stored procedures) viven en `db/migrations/` como scripts `.sql` numerados secuencialmente. Se aplican con el runner idempotente `db/migrate.py`, que registra cada script aplicado en `dbo.SchemaMigrations`:

```
python db/migrate.py                      # usa .env de la raíz
python db/migrate.py --env-file .env.prod # aplicar lo mismo en otro ambiente
python db/migrate.py --dry-run            # solo muestra qué se aplicaría
```

## Correr un pipeline

Cada tabla (dimensión o hecho) tiene su propia carpeta en `db/etl/<Tabla>/` con tres scripts, uno por capa. Ejemplo con `dimSector`:

```
python db/etl/dimSector/extract_dim_sector.py        # Bronze: AS400 -> stg
python db/etl/dimSector/load_silver_dim_sector.py     # Silver: stg -> [int]
python db/etl/dimSector/load_gold_dim_sector.py       # Gold: [int] -> dw
```

Todos aceptan `--env-file <ruta>`.

## Arquitectura

**Bronze (`stg`)** — se conecta al AS400/LX y a JAREMAR, introspecciona las columnas reales del origen y mapea sus tipos a SQL Server. Auto-provisiona la tabla `stg.<Tabla>` (la crea o, si su estructura cambió, la recrea) y hace carga FULL (`TRUNCATE` + `INSERT`). El DDL generado se cachea en `db/etl/<Tabla>/schema_cache/`.

**Silver (`[int]`)** — script delgado que solo orquesta el ciclo de control; el trabajo de tipado y dedup lo hace un stored procedure `[int].usp_MergeDim<Tabla>` (o `usp_MergeFact<Tabla>`).

**Gold (`dw`)** — mismo patrón, vía `dw.usp_MergeDim<Tabla>`/`usp_MergeFact<Tabla>`, moviendo `[int].<Tabla>` a `dw.<Tabla>`.

Todas las corridas quedan registradas en el framework de control ETL del esquema `dbo` (catálogo de procesos, log de corridas, watermarks y errores por fila).

Ver [CLAUDE.md](CLAUDE.md) para el detalle completo de convenciones y del framework de control.

## Estado

Dimensiones completas (AS400 -> stg -> int -> dw): dimProducto, dimClasesProducto, dimEmpresas, dimSector, dimCentroCosto, dimCuenta, dimSubCuenta.

En progreso: `factEnvios`, la primera tabla de hechos del proyecto.
