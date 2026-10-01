# Estado de las corridas por tabla

Generado el 2026-10-01 13:33 (hora local). Cifras consultadas en produccion (`172.20.6.6\FINANZAS`, base `JAREMAR`, SQL Server 2016) desde `dbo.EtlProcess`, `dbo.EtlRunLog`, `dbo.EtlWatermark` y `dbo.usp_Etl_AlertasObtener`.

- **Repositorio:** `master` = `origin/master` en `8dc2b84`.
- **Migraciones en produccion:** hasta la 244 (243-244: dominios `Basculas`, `TerminosVenta`, `ClasesProducto`; monitor con `--dominios`).
- **Salud general:** 0 errores, 0 rechazos y 0 corridas colgadas en los ultimos 7 dias. Las ultimas corridas de **todos** los procesos terminaron en `EXITO`.
- **Alertas (umbral 26 h):** 119, todas `SIN_EXITO`. No hay fallas: son tablas que no se corren desde hace mas de 26 h porque **ninguna tarea esta registrada en el servidor** y todo se corre a mano.

## Hechos

| Hecho | Dominio | Filas en `dw` | Ultima corrida (gold) | Antiguedad | Ultima corrida: leidas / insertadas / actualizadas | Orquestador | Estado |
|---|---|---|---|---|---|---|---|
| factVentas | Ventas | 1.648.771 | 01/10 09:54 | hoy | 36.755 / 36.381 / 374 | `run_ventas.py` | Al dia |
| factBasculaBufalo | Basculas | 90.834 | 01/10 13:31 | hoy | 295 / 249 / 46 | `run_bascula.py` | Al dia |
| factEnvios | Envios | 212.387 | 29/09 09:31 | 2 dias | 121.367 / 912 / 120.455 | `run_envios.py` | Atrasado |
| factSanAlejoFruta | SanAlejo | 46.044 | 29/09 16:41 | 2 dias | 0 / 0 / 0 | `run_sanalejo.py` | Atrasado |
| factSanAlejoDespachos | SanAlejo | 21.398 | 29/09 16:41 | 2 dias | 0 / 0 / 0 | `run_sanalejo.py` | Atrasado |
| factSanAlejoIngresos | SanAlejo | 12.821 | 29/09 16:41 | 2 dias | 0 / 0 / 0 | `run_sanalejo.py` | Atrasado |
| factCompras | Compras | 714.700 | 28/09 14:43 | 3 dias | 2.108 / 1.343 / 765 | `run_compras.py` | Atrasado |
| factGuiasRemision | GuiasRemision | 2.476.163 | 28/09 13:58 | 3 dias | 2.476.163 / 2.476.163 / 0 (reemplazo) | `run_guias.py` | Atrasado |
| factManifiestos | Manifiestos | 2.689.893 | 28/09 16:57 | 3 dias | 289.331 / 289.331 / 0 (reemplazo) | `run_manifiestos.py` | Atrasado |

Watermarks de silver: `Ventas` 01/10, `BasculaBufalo` 01/10, `GuiasRemision` 28/09, `Manifiestos` 28/09, `Compras` 28/09, SanAlejo (los 3) 28/09.

## Dimensiones AS400

| Dimension | Dominio | Filas en `dw` | Ultima corrida | Antiguedad | Ultima corrida: insertadas / actualizadas | La refresca |
|---|---|---|---|---|---|---|
| dimProducto | Producto | 36.587 | 01/10 09:43 | hoy | 14 / 1.220 | ventas, guias, manifiestos, dimensiones |
| dimEmpresas (+ moneda) | Empresas | 64 | 01/10 09:42 | hoy | 0 / 0 | compras, guias, manifiestos, dimensiones |
| dimBascula | Basculas | 4 | 01/10 13:31 | hoy | 0 / 0 | bascula, dimensiones |
| dimTipoBoleta | Basculas | 8 | 01/10 13:31 | hoy | 0 / 0 | bascula, dimensiones |
| dimLugarBascula | Basculas | 1.432 | 01/10 13:31 | hoy | 0 / 0 | bascula, dimensiones |
| dimProductoBascula | Basculas | 441 | 01/10 13:31 | hoy | 0 / 0 | bascula, dimensiones |
| dimCliente | Cliente | 137.101 | 29/09 09:36 | 2 dias | 7 / 1.937 | guias, manifiestos, dimensiones |
| dimProveedor | Proveedor | 25.457 | 29/09 09:37 | 2 dias | 7 / 207 | compras, dimensiones |
| dimVehiculo | Vehiculo | 5.468 | 29/09 09:38 | 2 dias | 1 / 0 | envios, guias, dimensiones |
| dimRuta | Ruta | 514 | 29/09 09:37 | 2 dias | 0 / 0 | manifiestos, dimensiones |
| dimMotivoTraslado | MotivoTraslado | 12 | 29/09 09:38 | 2 dias | 0 / 0 | guias, dimensiones |
| dimSector | Sector | 291 | 29/09 09:32 | 2 dias | 0 / 0 | dimensiones |
| dimCentroCosto | CentroCosto | 255 | 29/09 09:32 | 2 dias | 0 / 0 | dimensiones |
| dimCuenta | Cuenta | 300 | 29/09 09:33 | 2 dias | 0 / 0 | dimensiones |
| dimSubCuenta | SubCuenta | 1.042 | 29/09 09:33 | 2 dias | 0 / 0 | dimensiones |
| dimClasesProducto | ClasesProducto | 99 | 29/09 09:33 | 2 dias | 0 / 0 | dimensiones |
| dimTerminosVenta | TerminosVenta | 107 | 29/09 09:37 | 2 dias | 0 / 0 | dimensiones |
| dimTerminosCompra | Compras | 12 | 29/09 09:37 | 2 dias | 0 / 0 | dimensiones |
| dimViaje | Viaje | 107 | 29/09 09:37 | 2 dias | 0 / 0 | dimensiones |
| dimPais / dimDepartamento / dimMunicipio | Geografia | 244 / 54 / 675 | 29/09 09:38 | 2 dias | 0 / 0 | dimensiones (geografia al final) |
| 6 catalogos SanAlejo (producto 75, localizacion 551, transportista 1.984, cliente 254, productor 4.113, finca 123) | SanAlejo | - | 29/09 16:36 | 2 dias | carga inicial | sanalejo, dimensiones |

## Dominio Solar (proceso externo -> `stg`)

Las 15 tablas (30 pasos silver/gold) corrieron por ultima vez el **28/09 08:39-08:40** (3 dias). Filas en `dw`: `factSmaPower15Minutes` 425.284, `factGrowattEnergyAndPowerPv` 81.433, `factSoliscloudEnergyAndPowerPv` 18.517, `factHuaweiEnergyAndPowerPv` 636, `factMeteoDaily` 207, `factSmaPowerPlanta` **0** (el proceso externo no deposita esa tabla).

## Carga manual

| Tabla | Filas | Ultima carga | Nota |
|---|---|---|---|
| dimPlanGeneracion | 14.235 | 24/09 09:44 | Desde Excel; no se programa |

## Tareas programadas

Ninguna esta registrada en el servidor. Son 24 tareas en total:

| Script | Tareas | Horario (hora local) |
|---|---|---|
| `registrar_tareas_solar.ps1` | 2 | 10:30, 17:30, 20:30; vigilante 12:00/22:00 |
| `registrar_tareas_dimensiones.ps1` | 2 | 21:30; vigilante 23:00 |
| `registrar_tareas_ventas.ps1` | 3 | 05:00 (no dom.) y 13:00; dom. 02:00; vigilante 07:00/15:00 |
| `registrar_tareas_guias.ps1` | 3 | 05:30 (no dom.) y 13:30; dom. 03:00; vigilante 07:30/15:30 |
| `registrar_tareas_compras.ps1` | 3 | 06:00 (no dom.) y 14:00; dom. 04:00; vigilante 08:00/16:00 |
| `registrar_tareas_manifiestos.ps1` | 3 | 06:30 (no dom.) y 14:30; dom. 05:00; vigilante 08:30/16:30 |
| `registrar_tareas_envios.ps1` | 2 | 07:00 y 15:00; vigilante 09:00/17:00 |
| `registrar_tareas_bascula.ps1` | 3 | 07:30 (no dom.) y 15:30; dom. 06:00; vigilante 09:30/17:30 |
| `registrar_tareas_sanalejo.ps1` | 3 | 08:00 (no dom.) y 16:00; dom. 06:30; vigilante 10:00/18:00 |

## Pendientes

| Pendiente | Detalle |
|---|---|
| Registrar las 24 tareas en el servidor | Lo unico que explica las 119 alertas `SIN_EXITO`. Requiere Python 3 + `pyodbc`, ODBC Driver 17, `.env.prod` y una cuenta con "Iniciar sesion como trabajo por lotes" |
| Ponerse al dia mientras tanto | Correr a mano: `run_compras.py`, `run_guias.py`, `run_manifiestos.py`, `run_envios.py`, `run_sanalejo.py`, `run_dimensiones.py` y `run_solar.py` (todos con `--env-file .env.prod`) |
| Dominio de `TerminosCompra` | Sigue en `Compras`; si el monitor de compras pasa a filtrar por dominio, tendria el mismo problema que tenia ventas |
| Watermark `Compras` en `SinClasificar` | Igual que tenia `Ventas` antes de la migracion 243 |
| Diferencias silver -> gold en catalogos | `dimLugarBascula` 1.434 -> 1.432, `dimSanAlejoTransportista` 1.995 -> 1.984, `dimSanAlejoCliente` 255 -> 254, sin rechazos: confirmar si es dedup por llave |
| `factSmaPowerPlanta` | 0 filas: el proceso externo no deposita esa tabla en `stg` |
| Pendientes anteriores | `RutaKey` en ventas y envios; crecimiento de las reconciliaciones de guias y manifiestos (limite de 60 min en ~1 anio); significado de `CodigoRuta1`, `CodigoRuta2` y `MarcaProceso` en `factManifiestos` |
