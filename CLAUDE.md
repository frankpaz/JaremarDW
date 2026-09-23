# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este repo

JaremarDW es el data warehouse de Jaremar en SQL Server (base `JAREMAR`). Es un ETL en Python (`pyodbc`) que mueve datos desde un AS400/LX (DB2 for i) hacia el warehouse, siguiendo arquitectura medallion (Bronze `stg` -> Silver `[int]` -> Gold `dw`), con un framework de control propio en el esquema `dbo` que registra cada corrida.

No hay build ni tests automatizados; el trabajo es escribir scripts Python de extracción/carga y migraciones SQL.

## Setup

```
cp .env.example .env   # completar credenciales AS400 y JAREMAR (SQL Server)
```

Variables clave en `.env`: `JAREMAR_SERVER`, `JAREMAR_PORT`, `JAREMAR_DATABASE`, `JAREMAR_AUTH_MODE` (`sql` o `windows`), `JAREMAR_USER`/`JAREMAR_PASSWORD`, `JAREMAR_ODBC_DRIVER`; `AS400_HOST`, `AS400_USER`, `AS400_PASSWORD`, `AS400_DRIVER`. No hay `requirements.txt`; la única dependencia externa es `pyodbc`.

## Comandos

Aplicar migraciones pendientes (idempotente, registra cada script en `dbo.SchemaMigrations`):
```
python db/migrate.py                      # usa .env de la raíz
python db/migrate.py --env-file .env.prod
python db/migrate.py --dry-run            # solo muestra qué se aplicaría
```

Correr un pipeline completo (ejemplo con `dimSector`, mismo patrón para cualquier tabla):
```
python db/etl/dimSector/extract_dim_sector.py        # Bronze: AS400 -> stg
python db/etl/dimSector/load_silver_dim_sector.py     # Silver: stg -> [int]
python db/etl/dimSector/load_gold_dim_sector.py       # Gold: [int] -> dw
```
Todos aceptan `--env-file <ruta>`.

## Arquitectura

### Las 3 capas

1. **Bronze (`stg`)** — `db/etl/<Tabla>/extract_*.py`. Se conecta al AS400/LX y a JAREMAR. Introspecciona las columnas reales del origen vía `cursor.columns()` y mapea tipos DB2 -> SQL Server (`mapear_tipo_sql_server`). **Auto-provisiona** `stg.<Tabla>`: si la tabla no existe la crea, y si existe con una estructura distinta a la esperada la recrea (stg es truncate+reload, no hay nada que preservar). El DDL generado se cachea en `db/etl/<Tabla>/schema_cache/` (no se versiona a mano). Carga FULL (`TRUNCATE` + `INSERT`, con `executemany`; si falla en bloque cae a fila por fila y registra rechazos). Siempre agrega `FechaCargaStg` y `RunId` como columnas de auditoría.

2. **Silver (`[int]`)** — `db/etl/<Tabla>/load_silver_*.py`. Script delgado: solo orquesta el ciclo de control. El trabajo real (tipado, dedup por llave de negocio) lo hace un stored procedure `[int].usp_MergeDim<Tabla>` (o `usp_MergeFact<Tabla>` para hechos) que recibe `@RunId` y devuelve `(FilasLeidas, FilasInsertadas, FilasActualizadas, FilasIgnoradas)`.

3. **Gold (`dw`)** — `db/etl/<Tabla>/load_gold_*.py`. Mismo patrón delgado, pero via `dw.usp_MergeDim<Tabla>`/`usp_MergeFact<Tabla>`, moviendo `[int].<Tabla>` -> `dw.<Tabla>`.

El DDL y los SPs de merge de cada capa/tabla viven en `db/migrations/`, numerados secuencialmente: `0NN_create_int_<tabla>.sql`, `0NN_create_int_<tabla>_procedures.sql`, `0NN_create_dw_<tabla>.sql`, `0NN_create_dw_<tabla>_procedures.sql`.

### Framework de control ETL (`dbo`)

Todas las corridas (de cualquier capa) se registran contra estas tablas/SPs, definidos en `db/migrations/001-004`:

- `dbo.EtlProcess` — catálogo de procesos, poblado vía `usp_Etl_ProcesoRegistrar` (idempotente, se llama en cada corrida).
- `usp_Etl_RunIniciar` — abre una corrida y devuelve `RunId`.
- `usp_Etl_RunFinalizar` — cierra la corrida con estado (`EXITO`/`ADVERTENCIA`/`ERROR`), métricas de filas y, si hubo error, `@MensajeError`/`@TareaError`.
- `usp_Etl_WatermarkActualizar` / `usp_Etl_WatermarkObtener` — watermark de última corrida exitosa por proceso.
- `usp_Etl_ErrorRegistrar` — registra filas rechazadas (llave de negocio + payload JSON + mensaje de error) durante la carga a stg.

Patrón estándar en cada script: `registrar_proceso()` -> `iniciar_run()` -> trabajo (con `try/except`, rollback en error) -> `finalizar_run()` -> `actualizar_watermark()`.

**Nota técnica importante:** no mezclar `?` (parámetro) con expresiones literales (ej. `SYSDATETIME()`) en el mismo `EXEC` — el driver ODBC de SQL Server falla al preparar el RPC ("Incorrect syntax near ')'"). Pasar el datetime como parámetro normal en vez de como literal SQL.

### Convenciones

- Nombres de funciones/variables/comentarios en español; identificadores SQL en PascalCase.
- DB2 for i (AS400) no soporta corchetes para identificadores — usar comillas dobles en las queries contra el origen.
- Un pipeline nuevo por tabla vive en su propia carpeta `db/etl/<Tabla>/`, replicando los tres scripts (`extract_`, `load_silver_`, `load_gold_`) y las 4 migraciones correspondientes (int DDL, int SP, dw DDL, dw SP).
- Las dimensiones se cargan FULL. Los hechos son incrementales (ver "Hechos incrementales" abajo), salvo `factEnvios`, cuyo extract es FULL porque el origen no tiene fecha de modificación confiable (211k filas).

### Hechos incrementales (ventas, compras, envíos)

Flujo completo con `python db/etl/run_fact.py <ventas|compras|envios> [--env-file ...]` (corre extract -> silver -> gold en orden y se detiene al primer error).

- **Extract (Bronze):** ventana de `MARGEN_DIAS = 30` hacia atrás desde el watermark compartido `Ventas`/`Compras`. Encabezados y líneas usan **el mismo** watermark a propósito: silver cruza líneas con encabezados, y con ventanas distintas las líneas quedarían con columnas de encabezado en NULL. Solo silver avanza ese watermark (con el `MAX` real de fecha en `[int]`); los extracts solo lo leen.
- **Silver:** `load_silver_fact_ventas/compras.py` verifica antes de mezclar que los dos extracts terminaron en `EXITO`/`ADVERTENCIA` y se corrieron después del último silver exitoso; si no, aborta sin tocar datos ni watermark.
- **Gold:** incremental real, con watermark propio (`Ventas_Gold`, `Compras_Gold`, `Envios_Gold`) = `MAX(FechaCargaInt)` de lo ya procesado, no la hora del cliente. `dw.usp_MergeFact*` procesa solo `[int]` con `FechaCargaInt > watermark`.
- **Reconciliación semanal:** `run_fact.py <flujo> --reconciliar` extrae todo el histórico (ignora el watermark) y hace que gold recorra todo `[int]`. Captura ediciones/altas tardías fuera de la ventana de 30 días y rellena llaves de dimensión (`EmpresaKey`, `ProductoKey`, `ProveedorKey`) que quedaron NULL por llegada tardía. **No propaga borrados del origen** (silver no da de baja lo que desaparece del AS400; solo `factEnvios` lo hace, por ser FULL).
