# Validación de `stg` del dominio Solar y plan de pasos — 2026-10-06 10:19

Cifras consultadas en producción (`172.20.6.6\FINANZAS`, base JAREMAR), solo lectura. La última corrida de
`run_solar.py` fue la manual del 2026-10-05 08:35; desde entonces no se ha procesado nada, así que `[int]`/`dw` van
un día atrás de `stg`.

## Qué hay de nuevo en `stg`

No hay tablas solares nuevas: siguen siendo las 15 que procesa `run_solar.py` (más sus copias `test.*_TEST`).
Lo nuevo es esto:

### 1. Huawei: cuenta nueva `san-alejo` (planta nueva "Jaremar San Alejo")

- El 2026-10-05 el proceso externo agregó la columna **`Account`** a `stg.dimHuaweiStations`, `stg.dimHuaweiDevices`
  y `stg.factHuaweiEnergyAndPowerPv` (y a sus `_TEST`). Valores: `edif-admin` (lo que ya había) y `san-alejo`.
  También actualizó sus vistas `stg.vwDailyGenerationSummary` y `stg.vwDailyPerformance` para incluir `Account`.
  Nuestros SPs silver no leen `Account` (no se rompen, pero tampoco la guardan).
- **Estación** `NE=59869602` "Jaremar San Alejo" (San Alejo, La 13, Tela, Atlántida), 2.352 kWp, conectada a la red
  el 2026-08-18.
- **6 inversores** Huawei SUN2000-330KTL-H1 (`Inversor-1` … `Inversor-6`). La capacidad DC viene en el hecho
  (`KpiData.installed_capacity`): Inversor-1 y 2 = 420 kWp, los otros 4 = 378 kWp (suma 2.352 = la de la estación).
- **Hecho:** 30 filas (6 equipos × 01 al 05/10/2026), una diaria por equipo, ~1.000–2.300 kWh/día por inversor
  (~5.400–13.900 kWh/día la planta). **No trae nada antes del 01/10**, aunque la planta está conectada desde el 18/08.
- Nada de esto está en `[int]`/`dw` todavía: estaciones 2 en stg vs 1 en dw, equipos 9 vs 3, hecho 690 vs 657.
- Revisado: los `Id` del hecho (PK en `[int]`/`dw`) no chocan entre cuentas (690 distintos, una sola secuencia) y los
  `DeviceId`/`StationCode` son nuevos. **La corrida normal los carga sin cambios de código.**
- **No entra al reporte** por sí sola: no tiene filas en `dimDeviceCapacity` ni en `dimPlanGeneracion`, y no está
  en el mapeo de `vwRptPlanta`/`vwRptPlantel`.

### 2. Meteo: histórico completo desde 2025-01-01 y sitio nuevo `san-alejo`

- `stg.factMeteoDaily` tiene ahora 6.410 filas = **10 sitios × 641 días** (2025-01-01 al 2026-10-03), cargadas hoy
  15:46–15:52 UTC. Antes `dw` solo tenía 270 (9 sitios, 2026-09-03 al 2026-10-02).
- Esto **resuelve el pendiente de meteo marzo–agosto** (y trae además todo 2025 y enero–febrero de 2026).
- Sitio nuevo **`san-alejo`** (el MeteoSite que usaría la planta nueva).
- 3 días por sitio vienen con HSF NULL (los más recientes; es el rezago normal de NASA POWER).
- El silver de meteo deduplica por sitio + fecha y no filtra fechas: la corrida normal los carga completos.

### 3. Datos del día (sin novedad estructural)

| Fuente | Último dato en `stg` | Último en `dw` |
|---|---|---|
| SMA 15 min | 2026-10-06 07:00 | 2026-10-05 07:00 |
| Growatt | 2026-10-06 07:31 | 2026-10-05 07:31 |
| Soliscloud | 2026-10-06 13:29 UTC | (día anterior) |
| Huawei | 2026-10-06 | (día anterior) |

Siguen igual que el 05/10: **JABÓN sin datos desde 2026-10-03 19:45** (ya son 3 días), **JABON-2
(`SN 3006256658`) sin datos desde 2026-08-11**, `factSmaPowerPlanta` vacía. Las demás plantas SMA tienen datos de hoy.

## Plan de pasos

### A. Sin decisiones pendientes (se puede hacer ya)

1. **Correr `run_solar.py --env-file .env.prod`** y validar después:
   - Huawei: estaciones 2, equipos 9, hecho = filas de stg; 0 filas sin `HuaweiDeviceKey`.
   - Meteo: `dw.factMeteoDaily` = 6.410 filas, 10 sitios, 2025-01-01 al 2026-10-03.
   - `stg` = `[int]` = `dw` en las 15 tablas.
2. **Revisar el reporte con la meteo nueva:** al llenarse marzo–agosto, `vwRptPlantaDia` empieza a calcular PR en
   esos meses. Comparar PR mensual por planta y ver si reaparecen los PR > 100 % (REFINERÍA, PROALSA, HARINA-SOLIS)
   en todo el histórico (la decisión vigente es dejar las capacidades como están).
3. **Guardar `Account` en Huawei** (migración nueva: columna en `[int]`/`dw` de las 3 tablas + SPs silver/gold que la
   copien). No es urgente, pero deja trazable a qué cuenta pertenece cada equipo y la tabla queda fiel al origen.

### B. Para incorporar San Alejo al reporte (necesita decisiones del usuario)

4. **Nombre y lugar en el reporte:** nombre de planta (ej. `SAN ALEJO`), `Orden` 10, `MeteoSite` `san-alejo` y
   **plantel nuevo** (hoy `vwRptPlantel` solo tiene 'Km 13.5' y 'Km 15'; San Alejo está en Tela).
5. **Capacidad DC** de los 6 inversores. Opciones:
   - (a) que el proceso externo agregue 6 filas a `stg.dimDeviceCapacity` (como EDIF ADMIN, pero con `JoinKey`), o
   - (b) que el reporte tome `installed_capacity` del hecho Huawei (Huawei la informa para San Alejo, pero vale 0 en
     EDIF ADMIN, así que serviría solo para esta planta).
   En cualquier caso, cambiar el cruce de Huawei en `vwRptInversor` a `DeviceId` en vez de `DeviceName = SourceSn`:
   los nombres `Inversor-1..6` son genéricos y pueden repetirse en otra cuenta.
6. **Plan de generación:** San Alejo no está en `dimPlanGeneracion`. Hace falta una versión nueva del Excel con sus
   6 inversores (Proveedor `huawei`) y cargarla con `cargar_plan_generacion.py`; sin plan, su cumplimiento sale NULL.
7. **Migración de las vistas** (256): agregar la planta en `vwRptInversor`/`vwRptPlanta`/`vwRptPlantel` y probar el RDL.

### C. Con el proceso externo / operación de plantas

8. **Histórico de San Alejo** del 2026-08-18 al 2026-09-30: pedir que la cuenta `san-alejo` se descargue desde la
   conexión (EDIF ADMIN sí tiene desde 2026-03-01).
9. **JABÓN** (3 días sin datos) y **JABON-2** (casi 2 meses): siguen pendientes en el origen.
10. Siguen abiertos del 2026-10-05: `factSmaPowerPlanta` vacía, planta vieja `PI1-MARGARINA`, marcadores de
    MARGARINA/EDIF ADMIN en `dimDeviceCapacity`, **registrar las tareas programadas en el servidor** (sin ellas `dw`
    se atrasa cada día que no se corre a mano) y la **alerta de frescura por dispositivo** (el monitor no detecta lo
    de JABÓN).
