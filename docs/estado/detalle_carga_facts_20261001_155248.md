# Detalle de la carga de las tablas de hechos

Generado el 2026-10-01 15:52 (hora local). Cifras consultadas en produccion (`172.20.6.6\FINANZAS`, base `JAREMAR`, SQL Server 2016). Repositorio en `master` = `origin/master` `99ca91a`; migraciones hasta la 245.

Hay 15 tablas `fact` en `dw`: 9 vienen del AS400 (extract propio) y 6 del dominio Solar (las deposita en `stg` un proceso externo). Todas corrieron con exito hoy entre 09:43 y 14:18, **a mano**: ninguna tarea programada esta registrada en el servidor.

## Resumen

| Hecho | Origen | Filas `dw` | Datos desde - hasta | Estrategia | Llave | Ultima corrida |
|---|---|---|---|---|---|---|
| factVentas | AS400 `SIH` + `SIL` | 1.648.771 | 2026-05-04 - 2026-10-01 (`FechaCreacion`) | Incremental, ventana 30 dias, MERGE | Cia + prefijo + documento + año + tipo + linea (`ILCOMP`...`ILLINE`) | 01/10 09:54 |
| factCompras | AS400 `APH` + `APL` | 716.261 | 2017-10-17 - 2026-10-01 (`FechaContable`) | Incremental, ventana 30 dias, MERGE | Cia + prefijo + año + secuencia + linea (`PLCMPY`...`PLLINE`) | 01/10 13:59 |
| factEnvios | AS400 `ENCROU` | 212.836 | 2001-08-22 - 2026-10-01 (`FechaGeneracion`) | Extract FULL; silver/gold MERGE | Numero de envio (`ENCENV`) | 01/10 14:15 |
| factGuiasRemision | AS400 `PROLXUSRF.UNDIS100` | 2.491.428 | 2025-01-04 - 2026-10-01 (`FechaRegistro`) | Reemplazo de ventana (DELETE + INSERT) | No tiene | 01/10 14:03 |
| factManifiestos | AS400 `PROLXUSRF.UNDIS002` | 2.724.410 | 2026-01-05 - 2026-10-01 (`FechaCreacion`) | Reemplazo de ventana (DELETE + INSERT) | No tiene | 01/10 14:10 |
| factBasculaBufalo | AS400 `PROLXUSRF.BASMASTNN` | 90.834 | 2024-09-02 - 2026-10-01 (`FechaGeneracion`) | Incremental + abiertas, MERGE, nunca borra | Construida (4 campos) | 01/10 13:31 |
| factSanAlejoFruta | AS400 `PIDSA.SPVHST00` | 46.350 | 2025-01-02 - 2026-09-30 (`FechaDocumento`) | Incremental por fecha o modificacion, MERGE, nunca borra | `CODCIA + NUMDOC` | 01/10 14:16 |
| factSanAlejoDespachos | AS400 `PIDSA.SPVHST01` | 21.510 | 2025-01-02 - 2026-09-30 | Igual que fruta | `CODCIA + NUMDOC` | 01/10 14:17 |
| factSanAlejoIngresos | AS400 `PIDSA.SPVHST02` | 12.871 | 2025-01-02 - 2026-09-30 | Igual que fruta | `CODCIA + NUMDOC` | 01/10 14:17 |
| factSmaPower15Minutes | `stg` (API SMA) | 432.019 | 2026-03-01 - 2026-10-01 14:00 (`Time`) | Incremental por `CreationTime`/`LastModificationTime` | `Id` | 01/10 14:17 |
| factGrowattEnergyAndPowerPv | `stg` (API Growatt) | 84.353 | 2026-06-16 - 2026-10-01 14:13 | Igual que SMA | `Id` | 01/10 14:18 |
| factSoliscloudEnergyAndPowerPv | `stg` (API Soliscloud) | 19.382 | 2026-07-21 - 2026-10-01 13:30 | Igual que SMA | `Id` | 01/10 14:18 |
| factHuaweiEnergyAndPowerPv | `stg` (API Huawei) | 642 | 2026-03-01 - 2026-09-30 | Igual que SMA (1 fila diaria por estacion) | `Id` | 01/10 14:17 |
| factMeteoDaily | `stg` (NASA POWER, curada a mano) | 234 | 2026-09-03 - 2026-09-28 (`MeasuredDate`) | FULL + SCD Tipo 1 | `Site + MeasuredDate` | 01/10 14:18 |
| factSmaPowerPlanta | `stg` (API SMA) | **0** | - | Igual que SMA | `Id` | 01/10 14:17 |

## Como funciona cada estrategia

### 1. Incremental con ventana de 30 dias y MERGE (ventas, compras)

- **Bronze:** el extract trae del AS400 lo que tenga fecha `>=` watermark de silver `- 30 dias` (`MARGEN_DIAS = 30`). Encabezados y lineas usan **el mismo** watermark (`Ventas` / `Compras`) para que silver pueda cruzarlos. `stg` es `TRUNCATE` + `INSERT`.
- **Silver:** antes de mezclar verifica que los dos extracts terminaron bien y despues del ultimo silver; si no, aborta sin tocar nada. MERGE por llave de negocio (inserta, actualiza o ignora). Avanza el watermark con el `MAX` real de fecha en `[int]`.
- **Gold:** procesa solo `[int]` con `FechaCargaInt >` watermark gold (`Ventas_Gold`, `Compras_Gold`).
- **Reconciliacion semanal (`--reconciliar`):** extrae todo el historico y gold recorre todo `[int]`. Recupera ediciones fuera de la ventana y llaves de dimension (`EmpresaKey`, `ProductoKey`, `ProveedorKey`) que quedaron NULL. **No propaga borrados del origen.**
- **Volumen de hoy:**
  - Ventas: 78.436 encabezados + 336.204 lineas leidas -> 36.381 nuevas / 374 actualizadas.
  - Compras: 8.184 + 8.074 -> 1.561 / 1.019.
- **Lo mas lento:**
  - Lineas de ventas: 620 s (10 min).
  - Encabezados de compras: **1.087 s (18 min) para 8.184 filas**; el promedio de 7 dias es 548 s. Es lento para su tamano, conviene revisarlo.
- **Dimensiones que actualiza su orquestador:** solo `dimProducto` (ventas) y `dimProveedor` (compras).

### 2. Extract FULL con MERGE (envios)

- El origen `ENCROU` no tiene fecha de modificacion confiable, asi que el extract trae **toda** la tabla en cada corrida (212.837 filas, ~3 min).
- Silver hace MERGE y **si da de baja** lo que desaparece del AS400 (es el unico hecho del AS400 que propaga borrados).
- Gold es incremental (`Envios_Gold`). En cada corrida tambien toma los envios cuya `VehiculoKey` cambio porque la dimension se actualizo despues.
- Hoy: 449 nuevos / 103 actualizados. Sin reconciliacion programada (no hace falta).

### 3. Reemplazo de ventana sin llave (guias de remision, manifiestos)

- El origen no tiene llave unica ni fecha de modificacion: hay lineas repetidas y duplicados exactos. Por eso silver y gold **no hacen MERGE**: borran el rango desde la fecha mas antigua que trajo el extract y lo vuelven a insertar.
- **Ventana:** watermark `- 30 dias`, nunca antes del historico acordado (guias desde 2025-01-01, manifiestos desde 2026-01-01).
- **Hoy, desde 2026-08-29:**
  - Guias: 116.716 borradas -> 131.981 insertadas.
  - Manifiestos: 289.331 -> 323.848.
- **Consecuencia:** `GuiaRemisionKey` y `ManifiestoKey` cambian en cada corrida. No sirven como referencia estable.
- **Manifiestos sin fechas futuras en el watermark:** el origen trae fechas 2027-2031 (542 filas en `dw`). Silver no deja que el watermark pase de hoy.
- **Reconciliacion semanal:** re-extrae todo el historico acordado (guias ~29 min, manifiestos ~24 min, y creciendo).

### 4. Incremental con llave propia, nunca borra (bascula, SanAlejo)

- **Bascula:**
  - **Llave construida por nosotros:** bascula + boleta + fecha + hora de generacion.
  - **Extract:** `FECHAGEN >=` watermark `- 30 dias`, mas las boletas que siguen abiertas (`ESTATUS = 'T'`) en el AS400 y en `[int]`, para que llegue su cierre.
- **SanAlejo:**
  - **Llave:** `CODCIA + NUMDOC`.
  - **Extract:** `FECDOC` **o** `FECMOD >=` watermark `- 30 dias`, nunca antes de 2025.
- **Silver (los dos):**
  - MERGE con `HashDiff`.
  - Lo que falta en el AS400 dentro de la ventana queda con `EsVigente = 0`; no se borra.
  - Si una corrida daria de baja mas de 200 registros, aborta (`--max-bajas` lo autoriza).
- **Gold:** MERGE incremental con llave estable (`BoletaKey`, `FrutaKey`, `DespachoKey`, `IngresoKey`), y rellena llaves de dimension que llegan tarde.
- **Hoy:**
  - Bascula: 4.151 leidas -> 249 nuevas / 46 actualizadas (boletas cerradas) / 0 bajas.
  - Fruta: 306 / 294.
  - Despachos: 112 / 0.
  - Ingresos: 50 / 0.
- **Rezago:** SanAlejo va con ~1 dia de rezago (las boletas del dia estan en `SPVTRA*` hasta cerrarse); por eso su ultimo dato es el 30/09.

### 5. Solar: desde `stg` que llena un proceso externo

- No hay extract en este repo: el proceso externo deposita en `stg` los datos de las APIs (SMA, Huawei, Soliscloud, Growatt) y meteo. Este pipeline arranca en silver.
- **SMA, Growatt, Soliscloud, Huawei:** silver procesa solo filas con `CreationTime`/`LastModificationTime` posteriores a su watermark y lo avanza con el maximo visto (no con la hora actual). Gold es incremental por `FechaCargaInt`.
- **Meteo:** serie diaria curada a mano, sin `Id`; FULL + SCD Tipo 1.
- **Hoy:** SMA 6.735 filas nuevas, Growatt 2.920, Soliscloud 865, Huawei 6, Meteo 27 nuevas / 18 actualizadas. Los 30 pasos tardan menos de 1 min.
- **Watermarks con hora UTC:** algunos de silver quedan "adelantados" respecto a la hora local (SMA 20:01, Growatt 20:16). Es esperado: son marcas de tiempo del origen en UTC.

## Watermarks actuales

| Hecho | Watermark de silver / extract | Watermark de gold |
|---|---|---|
| factVentas | `Ventas` 2026-10-01 | `Ventas_Gold` 01/10 09:54 |
| factCompras | `Compras` 2026-10-01 | `Compras_Gold` 01/10 13:59 |
| factEnvios | `Envios` 01/10 14:15 (FULL) | `Envios_Gold` 01/10 14:15 |
| factGuiasRemision | `GuiasRemision` 2026-10-01 | `GuiasRemision_Gold` 01/10 14:03 |
| factManifiestos | `Manifiestos` 2026-10-01 | `Manifiestos_Gold` 01/10 14:10 |
| factBasculaBufalo | `BasculaBufalo_Silver` 2026-10-01 (ventana completa: `BasculaBufalo` 2026-08-30) | `BasculaBufalo_Gold` 01/10 13:31 |
| factSanAlejo (los 3) | `*_Silver` 2026-09-30 (ventana completa: 2026-08-29) | `*_Gold` 01/10 14:16-14:17 |
| Solar | por tabla, del origen (UTC) | por tabla, 01/10 14:17-14:18 |
| factSmaPowerPlanta | 1900-01-01 (nunca recibio datos) | 1900-01-01 |

## Orquestacion y horarios previstos

| Hecho | Orquestador | Diaria (hora local) | Reconciliacion | Vigilante |
|---|---|---|---|---|
| Ventas | `run_ventas.py` | 05:00 (no dom.) y 13:00 | dom. 02:00 | 07:00 / 15:00 |
| Guias | `run_guias.py` | 05:30 (no dom.) y 13:30 | dom. 03:00 | 07:30 / 15:30 |
| Compras | `run_compras.py` | 06:00 (no dom.) y 14:00 | dom. 04:00 | 08:00 / 16:00 |
| Manifiestos | `run_manifiestos.py` | 06:30 (no dom.) y 14:30 | dom. 05:00 | 08:30 / 16:30 |
| Envios | `run_envios.py` | 07:00 y 15:00 | - (ya es FULL) | 09:00 / 17:00 |
| Bascula | `run_bascula.py` | 07:30 (no dom.) y 15:30 | dom. 06:00 | 09:30 / 17:30 |
| SanAlejo (3) | `run_sanalejo.py` | 08:00 (no dom.) y 16:00 | dom. 06:30 | 10:00 / 18:00 |
| Solar (6) | `run_solar.py` | 10:30, 17:30, 20:30 | - | 12:00 / 22:00 |

Ninguna de estas tareas esta registrada en el servidor; todo se corre a mano.

## Observaciones

| Tema | Detalle |
|---|---|
| Tareas sin registrar | Todo lo anterior se corrio a mano hoy; mañana vuelve a atrasarse |
| Encabezados de compras lentos | 18 min hoy para 8.184 filas (promedio 7 dias: 9 min); las lineas tardan 6 s. Revisar el filtro o el indice que usa la consulta al AS400 |
| `factVentas` desde 2026-05-04 | Es lo que hay en `dw` hoy; `factCompras` tiene desde 2017. Confirmar si es el limite del origen o del historico cargado |
| Fechas futuras del origen | `factEnvios` 270 filas, `factManifiestos` 542, `factSanAlejoFruta` 22 (fechas mal digitadas en el AS400; los watermarks no pasan de hoy) |
| Claves no estables | `GuiaRemisionKey` y `ManifiestoKey` cambian en cada reemplazo de ventana |
| Borrados del origen | Solo envios los propaga. Ventas y compras no. Bascula y SanAlejo marcan `EsVigente = 0`. Guias y manifiestos los reflejan dentro de la ventana que reemplazan |
| Crecimiento de reconciliaciones | Guias y manifiestos re-extraen todo su historico cada domingo; manifiestos superaria el limite de 60 min por paso en ~1 año |
| `factSmaPowerPlanta` | 0 filas: el proceso externo no deposita esa tabla en `stg` |
