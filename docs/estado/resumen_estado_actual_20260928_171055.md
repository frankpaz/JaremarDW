# Resumen del estado actual

Generado el 2026-09-28 17:10 (hora local). Cifras consultadas en produccion (`172.20.6.6\FINANZAS`, base `JAREMAR`, SQL Server 2016).

- **Repositorio:** `master` = `origin/master` en `b31a6b0`.
- **Migraciones en produccion:** hasta la 185.

## Hechos (produccion)

| Hecho | Origen AS400 | Filas en `dw` | Ultima carga | Tipo de carga | Orquestador | Notas |
|---|---|---|---|---|---|---|
| factVentas | `SIL` + `SIH` | 1.612.390 | 28/09 09:22 | Incremental (30 dias) + reconciliacion | `run_ventas.py` | Ventas sin cliente: 0 (tras incluir clientes de baja) |
| factCompras | `APL` + `APH` | 714.700 | 28/09 14:43 | Incremental (30 dias) + reconciliacion | `run_compras.py` | Compras sin proveedor: 0 (tras incluir proveedores de baja) |
| factGuiasRemision | `PROLXUSRF.UNDIS100` | 2.476.163 | 28/09 13:58 | Reemplazo de ventana (sin llave unica), desde 2025 | `run_guias.py` | Cuadra exacto con el AS400; sin cliente 0,58 % (internos `6`/`600`) |
| factManifiestos | `PROLXUSRF.UNDIS002` | 2.689.893 | 28/09 16:57 | Reemplazo de ventana (sin llave unica), desde 2026 | `run_manifiestos.py` | **Nueva**; creada como `factPedidos` y renombrada (migracion 185). Cuadra exacto con el AS400 |
| factEnvios | `ENCROU` (FULL) | 211.475 | **23/09 14:51** | FULL | Solo `run_fact.py envios` | **Desactualizado; sin orquestador** |

## Dimensiones (produccion)

| Dimension | Filas | Ultima carga | Notas |
|---|---|---|---|
| dimCliente | 137.094 | 28/09 16:10 | Activos (`CM`) y de baja (`CZ`); `EsActivo = 1` en 33.753 |
| dimProveedor | 25.450 | 28/09 14:43 | Activos (`VM`) y de baja (`VZ`); `EsActivo = 1` en 19.801 |
| dimProducto | 36.573 | 28/09 16:10 | - |
| dimVehiculo | 5.466 | 28/09 14:12 | 555 vehiculos con proveedor borrado de `AVM`; se dejan asi |
| dimRuta | 514 | 28/09 16:10 | - |
| dimMotivoTraslado | 12 | 28/09 11:23 | Nueva (`UNDIS901`) |
| 12 dimensiones mas (sector, centro de costo, cuentas, empresas, clases, terminos, viaje, pais, departamento, municipio) | 12 a 1.042 c/u | 28/09 | Al dia |

Las 16 dimensiones del AS400 se corren con `run_dimensiones.py` (50 pasos); cada hecho programado refresca ademas las que usa.

## Orquestadores y tareas

| Proceso | Orquestador | Script de tareas | Horario (hora local) | Registrado |
|---|---|---|---|---|
| Solar (15 tablas) | `run_solar.py` | `registrar_tareas_solar.ps1` | 10:30, 17:30, 20:30; vigilante 12:00/22:00 | No en el servidor |
| Dimensiones AS400 | `run_dimensiones.py` | - | Sin horario (manual) | No hay script de tareas |
| Ventas | `run_ventas.py` | `registrar_tareas_ventas.ps1` | 05:00 (no dom.) y 13:00; dom. 02:00; vigilante 07:00/15:00 | No |
| Guias | `run_guias.py` | `registrar_tareas_guias.ps1` | 05:30 (no dom.) y 13:30; dom. 03:00; vigilante 07:30/15:30 | No |
| Compras | `run_compras.py` | `registrar_tareas_compras.ps1` | 06:00 (no dom.) y 14:00; dom. 04:00; vigilante 08:00/16:00 | No |
| Manifiestos | `run_manifiestos.py` | `registrar_tareas_manifiestos.ps1` | 06:30 (no dom.) y 14:30; dom. 05:00; vigilante 08:30/16:30 | No |
| Envios | - | - | - | No existe |

Ventas, guias, compras y manifiestos comparten `hecho_programado.py` (dimensiones -> hecho -> monitor, con bloqueo y log propios).

## Cambios del 2026-09-28

| Cambio | Resultado |
|---|---|
| `factGuiasRemision` + `dimMotivoTraslado` (migraciones 171-178) | 2,48 M filas desde 2025, cuadra exacto con el AS400 |
| `dimCliente` con clientes de baja (179) | Guias sin cliente 7,2 % -> 0,58 %; ventas 534 clientes -> 0 |
| `dimProveedor` con proveedores de baja (180) | Compras sin proveedor 412 lineas -> 0 |
| `factManifiestos` (181-185) | 2,69 M filas desde 2026, cuadra exacto; renombrada desde `factPedidos` |
| Orquestadores de ventas, guias, compras y manifiestos | Con reconciliacion semanal y vigilante; sin registrar |
| `db/migrate.py` | Corregido: con varios `sp_rename` en un lote, lo dejaba a medias sin error (146/147 verificadas completas) |

## Pendientes

| Pendiente | Detalle |
|---|---|
| Registrar las tareas en el servidor | 14 tareas (Solar 2; ventas, guias, compras y manifiestos 3 c/u) |
| Programar envios | Crear `run_envios.py` y su script de tareas; atrasado desde el 23/09 |
| Programar dimensiones | `run_dimensiones.py` no tiene tarea |
| Crecimiento de las reconciliaciones | Guias: extract completo 29 min (crece ~1,4 M filas/anio). Manifiestos: 24 min y crece ~3,4 M filas/anio; superaria el limite de 60 min en ~1 anio |
| Significado de columnas de `factManifiestos` | `CodigoRuta1`, `CodigoRuta2` y `MarcaProceso` sin significado confirmado |
| Filtros `EsActivo` | Reportes que usen `dimCliente`/`dimProveedor` como lista de activos deben filtrar `EsActivo = 1` |
| `factSmaPowerPlanta` | 0 filas: el proceso externo no deposita esa tabla en `stg` |
| Pendientes anteriores | `VehiculoKey` en factEnvios (cruce verificado al 99,98 %), relacion `ENCROU`/factEnvios; `RutaKey` en ventas y envios |
