# Puesta al día de PROD — 2026-10-12 08:29

Foto del estado tras actualizar manualmente todo el warehouse en PROD (`172.20.6.6\FINANZAS`, base `JAREMAR`) después de ~1 semana sin corridas (no hay tareas registradas en el servidor). Todas las cifras salen de las corridas de hoy y de consultas de solo lectura en PROD.

## Estado antes de empezar

| Dominio | Último éxito | Días sin actualizar |
|---|---|---|
| Dimensiones AS400, Guías, Manifiestos, Báscula, SanAlejo | 2026-10-01 | 11 |
| Envíos, Compras (y Vehículo/Proveedor) | 2026-10-02 | 10 |
| Ventas | 2026-10-05 | 7 |
| Solar | 2026-10-06 | 6 |

- Migraciones aplicadas hasta la 264 (igual que `master`); `migrate.py --dry-run`: nada pendiente.
- Sin corridas colgadas (`EN PROCESO`).
- Todos los atrasos caben en las ventanas normales: no hizo falta `--reconciliar`.

## Orden seguido

1. `migrate.py --dry-run`
2. `run_dimensiones.py` (todas las dimensiones AS400)
3. Hechos AS400, uno a la vez, con `--solo <hecho>` (las dimensiones ya estaban al día): ventas → compras → envíos → guías → manifiestos → báscula → SanAlejo
4. `run_solar.py` (antes de las 10:00, para no enviar el reporte diario)
5. `monitor_etl.py --sin-notificar --alertas-solar`

## Resultados

### Dimensiones (`run_dimensiones.py`, 385 s, terminó 07:26)

26 grupos, todos los pasos OK, monitor sin alertas. Solo cuatro tuvieron cambios en gold:

| Dimensión | Filas | Insertadas | Actualizadas |
|---|---|---|---|
| dimProducto | 36.825 | 238 | 1.786 |
| dimCliente | 137.160 | 36 | 21.152 |
| dimProveedor | 25.486 | 13 | 623 |
| dimVehiculo | 5.485 | 8 | 52 |

### Hechos AS400

| Hecho | Duración | Alcance | Insertadas | Actualizadas | Bajas / eliminadas |
|---|---|---|---|---|---|
| factVentas (huella) | 186 s | 10 días no cuadraron; 74.227 líneas, 17.505 encabezados | 33.547 | 18 | 0 bajas |
| factCompras (huella) | 48 s | Encabezados: 42 de 53 días; líneas: 7 de 38 días + 365 documentos con encabezado cambiado | 862 | 365 | 0 bajas |
| factEnvios (huella) | 43 s | 20 de 80 días no cuadraron; 3.062 envíos | 813 | 128 | 0 bajas |
| factGuiasRemision (reemplazo de ventana) | 205 s | Desde 2026-09-01; 145.687 filas | 145.687 | — | 119.682 eliminadas (+26.005 netas) |
| factManifiestos (reemplazo de ventana) | 345 s | Desde 2026-09-01; 353.445 líneas | 353.445 | — | 294.266 eliminadas (+59.179 netas) |
| factBasculaBufalo | 31 s | Desde 2026-09-01 + abiertas (271 en `[int]`); 4.642 boletas | 662 | 53 | 0 bajas |
| factSanAlejoFruta | — | Desde 2026-08-31; 4.630 boletas | 878 | 384 | 0 bajas |
| factSanAlejoDespachos | — | Desde 2026-08-31; 1.881 | 465 | 0 | 0 bajas |
| factSanAlejoIngresos | — | Desde 2026-08-31; 967 | 282 | 0 | 0 bajas |

SanAlejo (3 hechos): 137 s en total. En todos los hechos gold reprodujo exactamente lo de silver, 0 filas rechazadas en stg y el monitor de cada flujo sin alertas.

### Solar (`run_solar.py`, 49 s, terminó 08:25)

30/30 pasos OK. No se envió reporte (antes de las 10:00 y sin fallos). Dimensiones y referencia sin cambios.

| Hecho | Insertadas | Actualizadas |
|---|---|---|
| factSmaPower15Minutes | 11.912 | 39 |
| factGrowattEnergyAndPowerPv | 4.809 | 0 |
| factSoliscloudEnergyAndPowerPv | 1.621 | 0 |
| factMeteoDaily | 60 | 20 |
| factHuaweiEnergyAndPowerPv | 18 | 3 |
| factSmaPowerPlanta | 0 (sigue sin datos en stg) | — |

### Monitor general

0 críticas, 10 advertencias, todas `INVERSOR_SIN_DATOS`:

| Inversor | Proveedor | Sin producción desde | Días |
|---|---|---|---|
| SAN ALEJO GR2629032720, GR2649060873, GR2649060880, GR2649060900, GR2649060910, GR2649060940 | Huawei | 2026-10-05 | 7 |
| HARINAS 3009155068 | SMA | 2026-10-06 | 6 |
| REFINERÍA 3014275523 | SMA | 2026-10-07 | 5 |
| PERFECTOR 3006383105 | SMA | 2026-09-09 | 33 (ya conocido) |
| JABÓN 3006256658 | SMA | 2026-05-12 | 153 (ya conocido) |

## Hallazgo: Huawei SAN ALEJO no llega en el lote diario

| Estación | Cuenta del portal | Lote diario 13:31 UTC | Último dato |
|---|---|---|---|
| NE=46378894 JAREMAR (EDIF ADMIN, 3 inversores) | `edif-admin` | Llega todos los días | 2026-10-12 |
| NE=59869602 Jaremar San Alejo (6 inversores) | `san-alejo` | No llega | 2026-10-05 |

- Lo de SAN ALEJO en `stg.factHuaweiEnergyAndPowerPv` entró solo en dos cargas sueltas: 2026-10-05 16:41 (30 filas) y 2026-10-06 21:05 (252 filas). Desde entonces no hay nada de esa cuenta.
- Hasta el 05/10 los 6 inversores producían 840-2.300 kWh/día: la alerta es por falta de datos, no por inversores apagados.
- **Acción:** pedir al proceso externo que el lote diario incluya la cuenta `san-alejo` y que traiga los días desde el 2026-10-06. Del lado del DW no hay que cambiar nada: silver toma lo nuevo por `CreationTime`.
- Aparte: EDIF ADMIN produjo casi 0 del 04/10 al 07/10 (0,03-2 kWh/día) y se recuperó el 08/10; es dato del portal (parece una caída real de la planta).

## Pendientes abiertos

1. Pedir al proceso externo la cuenta Huawei `san-alejo` (y los días faltantes).
2. SMA HARINAS (desde 06/10) y REFINERÍA (desde 07/10) sin producción: nuevos, revisar con el proceso externo / planta.
3. SanAlejo: el último documento de los tres hechos es del 2026-10-08 (lo normal es ~1 día de rezago); revisar si hay boletas sin cerrar en `SPVTRA*`.
4. dimCliente: 21.152 actualizaciones (15 % de la tabla) en 11 días, sin investigar qué columnas cambiaron.
5. Registrar las tareas en el servidor (`/programar-en-server`) para que el warehouse no se vuelva a atrasar.
