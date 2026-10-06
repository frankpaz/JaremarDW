# Validación de la carga Solar (pasos 1-3) — 2026-10-06 10:38

Cifras de producción (`172.20.6.6\FINANZAS`, JAREMAR) tras aplicar las migraciones 256-257 (Huawei guarda
`Account`) y correr `run_solar.py --env-file .env.prod` a las 10:37 (30/30 pasos OK, 44 s, monitor sin alertas).
Sigue a `validacion_stg_dominio_solar_20261006_101911.md`.

## Paso 1 — Carga

- **Las 15 tablas cuadran:** `stg` = `[int]` = `dw` (SMA 15 min 439.868; Growatt 88.563; Soliscloud 20.880;
  Huawei 690; meteo 6.410; dimensiones sin diferencias).
- **Huawei:** 2 estaciones (`edif-admin` JAREMAR, `san-alejo` Jaremar San Alejo 2.352 kWp), 9 equipos (3 + 6),
  0 sin estación. Hecho: `edif-admin` 660 filas (2026-03-01 al 2026-10-06), `san-alejo` 30 filas (01 al 05/10,
  43.744,78 kWh). 0 filas sin `HuaweiDeviceKey`; `Account` lleno en todas.
- **SMA / Soliscloud:** 0 filas sin llave de dispositivo.
- **Meteo:** 6.410 filas, 10 sitios, 2025-01-01 al 2026-10-03. HSF NULL en 3 fechas para los 10 sitios:
  2026-10-02 y 2026-10-03 (rezago normal) y **2026-09-07** (hueco en la fuente, no se llenó).

## Paso 2 — PR mensual con la meteo nueva

PR mes = kWh del mes / (kWp DC × HSF real del mes), solo días con energía y HSF. La energía empieza el
2026-03-01 (la meteo de 2025 no tiene generación con qué cruzarse).

| Planta | Mar | Abr | May | Jun | Jul | Ago | Sep |
|---|---|---|---|---|---|---|---|
| PROALSA | 78,7 % | 73,9 % | 57,5 % | 73,1 % | 72,5 % | 70,2 % | 72,7 % |
| REFINERÍA | — | 60,3 % (4 d) | 78,8 % | **105,2 %** | 93,8 % | **101,2 %** | 91,1 % |
| PERFECTOR | 68,0 % | 61,8 % | 51,3 % | 71,6 % | 58,6 % | 60,9 % | 54,2 % |
| EDIF ADMIN | 66,4 % | 62,9 % | 51,5 % | 73,1 % | 69,8 % | 67,2 % | 46,5 % |
| JABÓN | 79,8 % | 79,4 % | 61,7 % | 70,7 % | 72,2 % | 69,2 % | 62,9 % |
| HARINAS | 58,9 % | 60,5 % | 44,7 % | 45,4 % | 44,2 % | 48,7 % | **34,3 %** |
| DETERGENTE | — | — | — | 51,8 % (15 d) | 47,1 % | 53,9 % | 56,2 % |
| MARGARINA | — | — | — | — | — | — | 47,5 % (9 d) |
| SOLIS | — | — | — | — | 27,2 % (11 d) | 72,9 % | 77,5 % |

Lectura:
- **REFINERÍA** pasa del 100 % en junio y agosto y tiene 20, 14 y 18 días > 100 % en jun/jul/ago: no es un día
  raro, es la capacidad (187,5 kWp) que se queda corta. Por decisión del 2026-10-05 la capacidad no se cambia.
- **HARINAS** queda bajo todo el período (44-60 %) y cae a 34 % en septiembre; también tiene 187,5 kWp.
- **Mayo** baja en todas las plantas a la vez (51-62 %): es un patrón general, no de una planta.
- **SOLIS julio** (27 %) son los primeros 11 días de datos (desde el 21/07); no es representativo.
- PROALSA, SOLIS, JABÓN y EDIF ADMIN tienen algunos días sueltos > 100 %, pero el mes queda en 63-80 %.

## Paso 3 — `Account` en Huawei

Migraciones 256 (columna en `[int]`/`dw` de estaciones, equipos y hecho; relleno de las 657 filas ya cargadas)
y 257 (los 6 merge la copian). Probadas en dev y aplicadas en producción. Sin commit.

## Siguiente (en espera de decisión del usuario)

Incorporar San Alejo al reporte (nombre, plantel, capacidad, plan, migración de vistas), pedir su histórico
desde el 18/08 al proceso externo, y los pendientes ya conocidos (JABÓN, JABON-2, tareas programadas, alerta de
frescura).
