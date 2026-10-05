# Pendientes del dominio Solar — 2026-10-05 08:40

Cifras consultadas en producción (`172.20.6.6\FINANZAS`, base JAREMAR) justo después de la corrida manual
`run_solar.py --env-file .env.prod` de las 08:35 (30/30 pasos OK, monitor sin alertas).

## Lo que sí está al día

- **Las capas cuadran:** `stg` = `[int]` = `dw` en conteo de filas en las 15 tablas solares. Ninguna corrida terminó
  en error desde el 2026-09-23 y no hay filas rechazadas ni borradas lógicamente.
- **Llaves de dispositivo:** 0 filas sin `SmaDeviceKey` / `HuaweiDeviceKey` / `SoliscloudDeviceKey`.
- **Datos de hoy (2026-10-05)** y 31/31 días completos en los últimos 30 para: Huawei (3 equipos), Soliscloud (2),
  Growatt (6), SMA PROALSA (6), REFINERÍA (3), PERFECTOR (5), HARINAS (3) y OLEPSA 1 - MARGARINA (4).
- **Referencia:** `dimPlanGeneracion` cubre 2026-01-01 a 2026-12-31, 39 inversores y 1 versión vigente;
  `dimGhiPlanDaily` (3.285 filas) y `dimGsaMonthlyReference` (108) sin cambios.

## Pendientes

### Datos que faltan (revisar en el origen / con quien opera las plantas)

1. **JABÓN (SMA, planta 4551207) sin datos desde el 2026-10-03 19:45.** Los 6 inversores (JABON-1, 3, 4, 5, 6, 7)
   no tienen nada del 04/10 ni del 05/10, aunque las demás plantas SMA sí traen datos de hoy. Como `stg` tampoco
   los tiene, el problema está antes del warehouse: la planta, el portal SMA o el proceso externo. También les
   falta el 14/09.
2. **JABON-2 (`SN 3006256658`, equipo 4551218) sin datos desde el 2026-08-11 12:15.** El plan sí le asigna
   producción (267,37 kWh/día), así que el cumplimiento de JABÓN se ve más bajo de lo real. Hay que confirmar si
   el inversor está apagado, se retiró o se reemplazó.
3. **`factSmaPowerPlanta` nunca ha recibido datos** (0 filas en `stg`, `[int]` y `dw`; watermark en 1900-01-01).
   En cambio, `test.factSmaPowerPlanta_TEST` tiene 273 filas (5 equipos, 2026-08-01 a 2026-08-20). Hay que
   confirmar con el proceso externo si va a escribir en `stg` o si esa tabla se deja de usar.
4. **Meteo llega hasta el 2026-10-02** en los 9 sitios, con 3 días de rezago y los datos traídos hoy a las 11:00
   UTC. Puede ser el rezago normal de la fuente; falta confirmarlo para no confundirlo con un atraso.

### Catálogos desactualizados

5. **Planta SMA vieja `PI1-MARGARINA` (7178282):** sus 5 equipos nunca tuvieron datos. Sus series se repiten en
   OLEPSA 1 - MARGARINA (3012032495, 3012032498) y en HARINAS (3009155068, 3012032494). Parece una planta
   reemplazada en el portal SMA que sigue vigente en `dimSmaDevices`/`dimSmaPlants`. Hay que decidir si se ignora
   o si se pide quitarla en el origen.
6. **`dimDeviceCapacity` no refleja MARGARINA:** tiene 5 marcadores (`MARG-01..05`, `IsPlaceholder = 1`, sin llave
   de cruce), pero SMA tiene 4 inversores reales con datos desde el 2026-09-22. EDIF ADMIN (Huawei) también está
   con marcadores sin llave. Solo 16 de los 39 inversores tienen capacidad.
7. **Plan en 0** para EDIF ADMIN (3 inversores) y SOLIS (2), conocido y así está en el Excel. EDIF ADMIN se dejó así
   por decisión del usuario; SOLIS sigue sin plan.

### Operación

8. **No hay ejecución programada:** no hay tareas `JaremarDW-*` registradas en esta PC y las corridas de Solar han
   sido manuales (23, 24, 25, 26 y 28/09; 01 y 05/10). No hubo ninguna el 27, 29 y 30/09 ni del 02 al 04/10, así
   que el warehouse se atrasa cada vez que no se corre a mano. Falta registrar `registrar_tareas_solar.ps1`
   (`JaremarDW-Solar` 10:30/17:30/20:30 + vigilante 12:00/22:00) en el servidor, junto con las demás tareas
   pendientes.
9. **Correo de alertas:** las variables `ALERT_SMTP_*` / `ALERT_EMAIL_*` ya están en `.env.prod`. Al montarlo en el
   servidor hay que validarlas con `monitor_etl.py --probar-notificacion`.
10. **Limitación del monitor:** `SIN_EXITO` mide corridas propias, no la frescura de los datos. Por eso la corrida de
    hoy salió "sin alertas" aunque JABÓN lleva 2 días sin datos y JABON-2 casi 2 meses. Hace falta una alerta de
    frescura por dispositivo (último `Time` por equipo contra un umbral) para enterarse a tiempo.
