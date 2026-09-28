# Resumen del estado actual

Generado el 2026-09-28 14:49 (hora local). Cifras consultadas en produccion (`172.20.6.6\FINANZAS`, base `JAREMAR`, SQL Server 2016).

- **Repositorio:** `master` = `origin/master` en `b18c2cb`.
- **Migraciones en produccion:** hasta la 180.

## Hechos (produccion)

| Hecho | Origen AS400 | Filas en `dw` | Ultima carga | Tipo de carga | Orquestador | Cambios del 2026-09-28 |
|---|---|---|---|---|---|---|
| factVentas | `SIL` + `SIH` | 1.612.390 | 28/09 09:22 | Incremental (30 dias) + reconciliacion | `run_ventas.py` | Primera incremental en produccion (+56.755 lineas) |
| factCompras | `APL` + `APH` | 714.700 | 28/09 14:43 | Incremental (30 dias) + reconciliacion | `run_compras.py` | Puesta al dia desde el 23/09; proveedores sin match 412 -> 0 |
| factGuiasRemision | `PROLXUSRF.UNDIS100` | 2.476.163 | 28/09 13:58 | Reemplaza la ventana de 30 dias (sin llave unica), desde 2025 | `run_guias.py` | **Nueva**. Cuadra exacto con el AS400 en 21 meses; sin cliente 7,2 % -> 0,58 % |
| factEnvios | `ENCROU` (FULL) | 211.475 | **23/09 14:51** | FULL | Solo `run_fact.py envios` | **Desactualizado; sin orquestador** |

## Dimensiones (produccion)

| Dimension | Filas | Ultima carga | Cambios del 2026-09-28 |
|---|---|---|---|
| dimCliente | 137.094 | 28/09 | Incluye clientes dados de baja (`CZ`), con `EsActivo` (33.760 activos) |
| dimProveedor | 25.450 | 28/09 | Incluye proveedores dados de baja (`VZ`), con `EsActivo` (19.801 activos) |
| dimMotivoTraslado | 12 | 28/09 | **Nueva** (`UNDIS901`) |
| dimProducto | 36.571 | 28/09 | Sin cambios de estructura |
| dimVehiculo | 5.466 | 28/09 | 555 vehiculos con proveedor borrado de `AVM`; se dejan asi |
| 13 dimensiones mas (sector, centro de costo, cuentas, empresas, clases, terminos, ruta, viaje, pais, departamento, municipio) | 12 a 1.042 c/u | 28/09 | Sin cambios; todas al dia |

Las 16 dimensiones del AS400 se corren con `run_dimensiones.py` (50 pasos); la geografia va dentro del grupo `pais`.

## Orquestadores y tareas

| Proceso | Orquestador | Script de tareas | Horario (hora local) | Registrado |
|---|---|---|---|---|
| Solar (15 tablas) | `run_solar.py` | `registrar_tareas_solar.ps1` | 10:30, 17:30, 20:30; vigilante 12:00/22:00 | No en el servidor |
| Dimensiones AS400 | `run_dimensiones.py` | - | Sin horario (manual) | No hay script de tareas |
| Ventas | `run_ventas.py` | `registrar_tareas_ventas.ps1` | 05:00 (no dom.) y 13:00; dom. 02:00; vigilante 07:00/15:00 | No |
| Guias | `run_guias.py` | `registrar_tareas_guias.ps1` | 05:30 (no dom.) y 13:30; dom. 03:00; vigilante 07:30/15:30 | No |
| Compras | `run_compras.py` | `registrar_tareas_compras.ps1` | 06:00 (no dom.) y 14:00; dom. 04:00; vigilante 08:00/16:00 | No |
| Envios | - | - | - | No existe |

Ventas, guias y compras usan el mismo modulo, `hecho_programado.py`: actualizan sus dimensiones, corren el hecho y el monitor, con bloqueo y log propios.

## Pendientes

| Pendiente | Detalle |
|---|---|
| Registrar las tareas en el servidor | 11 tareas (Solar 2, ventas 3, guias 3, compras 3). Requiere Python + `pyodbc`, `.env.prod` y una cuenta con "Iniciar sesion como trabajo por lotes" |
| Programar envios | Crear `run_envios.py` y su script de tareas; hoy esta atrasado desde el 23/09 |
| Programar dimensiones | `run_dimensiones.py` no tiene tarea; ventas, guias y compras solo refrescan las dimensiones que usan |
| `factSmaPowerPlanta` | 0 filas: el proceso externo no deposita esa tabla en `stg` |
| Revisar filtros de `EsActivo` | Si algun reporte usa `dimCliente` o `dimProveedor` como lista de activos, debe filtrar `EsActivo = 1` |
| Limite de la reconciliacion de guias | Hoy el extract completo tarda 29 min y el limite es 60; crece ~1,4 M filas por anio |
| Pendientes anteriores | `VehiculoKey` en factEnvios (cruce verificado al 99,98 %), relacion `ENCROU`/factEnvios; `RutaKey` en ventas y envios |
