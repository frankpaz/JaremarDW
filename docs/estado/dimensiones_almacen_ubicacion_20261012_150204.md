# Dimensiones de almacén y ubicación — 2026-10-12 15:02

Foto del estado después de agregar `dimAlmacen`, `AlmacenKey`, `dimUbicacion` y `UbicacionKey` el 2026-10-12 (por la tarde, después de la puesta al día de la mañana: ver `puesta_al_dia_prod_20261012_082952.md`). Cifras consultadas en PROD (`172.20.6.6\FINANZAS`, base `JAREMAR`) con consultas de solo lectura.

## Código y migraciones

| Commit | Contenido | Migraciones |
|---|---|---|
| `82cf745` | `dimAlmacen` desde `PROLX835F.IWM` | 265-268 |
| `00c7aed` | `AlmacenKey` en `factVentas`, `factManifiestos` y `dimCliente` | 269 |
| `e0c68bc` | `dimUbicacion` desde `PROLX835F.ILM` y `UbicacionKey` en `factManifiestos` | 270-274 |

- `master` = `origin/master` = `e0c68bc` (push hecho; sin branches pendientes).
- PROD tiene aplicadas hasta la **274** (10 migraciones aplicadas hoy, 265-274); nada pendiente.

## Corridas en PROD después de la mañana

14 corridas entre 11:19 y 11:47, **todas `EXITO`**:

| Proceso | Leídas | Insertadas | Actualizadas |
|---|---|---|---|
| Almacen (primera carga, 11:19) | 330 | 330 | — |
| Almacen (11:39, tras la 269) | 330 | 0 | 2 |
| Cliente (stg / silver / gold, 11:39) | 137.160 | 0 | 1.696 |
| Ventas_Gold, Manifiestos_Gold (11:41) | 0 | 0 | 0 (sin filas nuevas: prueba del SP nuevo) |
| Ubicacion (primera carga, 11:47) | 4.741 | 4.741 | — |

`UbicacionKey` (274) y el relleno de `AlmacenKey`/`UbicacionKey` se hicieron con scripts en lotes de 100 k filas (commit por lote), fuera de `dbo.EtlRunLog`. El gold de manifiestos todavía no ha corrido en PROD con el SP de la 274 (sí en dev: reconciliación completa, 2.689.862 líneas con llave salvo 1).

## dimAlmacen (`dw.dimAlmacen`)

| Dato | Valor |
|---|---|
| Almacenes | 330 (295 activos `WM`, 35 dados de baja `WZ`), todos vigentes |
| Sin `EmpresaKey` | 1 (`DS` Default/Standard, empresa 0) |
| Sin `PaisKey` | 0 |

## dimUbicacion (`dw.dimUbicacion`)

| Dato | Valor |
|---|---|
| Ubicaciones | 4.741 (4.383 activas `WL`, 358 dadas de baja `WZ`), todas vigentes |
| Almacenes con ubicaciones | 286 |
| Sin `AlmacenKey` | 0 |

`CodigoCentroBeneficio` (`LMPRF`) queda como código: solo ~78 % coincide con `dimCentroCosto`.

## Llaves en hechos y en dimCliente

| Tabla | Filas | `AlmacenKey` NULL | `UbicacionKey` NULL |
|---|---|---|---|
| `dw.factVentas` | 1.716.935 | 0 | — |
| `dw.factManifiestos` | 2.783.589 | 0 | 1 (`JND`/`110`, no existe en `ILM`) |
| `dw.dimCliente` | 137.160 | 0 con bodega (2.273 clientes sin bodega) | — |

- 3.113 clientes tienen como bodega por defecto un almacén dado de baja (`EsActivo = 0`).
- Ninguna línea de manifiestos apunta a una ubicación dada de baja.

## Orquestadores

- `run_dimensiones.py`: `almacen` → `ubicacion` → `cliente` (prefijos `Almacen`, `Ubicacion` en el monitor).
- `run_ventas.py`: `producto`, `almacen` antes de `factVentas`.
- `run_manifiestos.py`: `empresas`, `almacen`, `ubicacion`, `cliente`, `producto`, `ruta` antes de `factManifiestos`.

## Pendientes abiertos

1. Registrar las tareas en el servidor (`/programar-en-server`), en pausa en el paso 0 esperando la cuenta de servicio de TI. El clon del paso 5 debe quedar en `e0c68bc` (la guía todavía dice `f54e05d`). Mientras tanto, dimensiones y hechos solo se actualizan corriendo a mano.
2. Pedir al proceso externo la cuenta Huawei `san-alejo` (y los días desde el 2026-10-06).
3. SMA HARINAS (desde 06/10) y REFINERÍA (desde 07/10) sin producción.
4. SanAlejo: último documento del 2026-10-08.
5. dimCliente: 21.152 actualizaciones en la puesta al día de la mañana (más 1.696 en la corrida de las 11:39), sin investigar qué columnas cambian.
