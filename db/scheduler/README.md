# Programar Ejecucion (db/scheduler)

Aqui viven **todos los procesos pensados para correr desatendidos** (orquestadores y scripts de registro de tareas). Los scripts de carga de cada tabla siguen en `db/etl/<Tabla>/`; esta carpeta solo los orquesta.

| Archivo | Que hace |
|---|---|
| `run_solar.py` | Orquestador del dominio Solar: silver + gold de 15 tablas (30 pasos, ~1 min) y, al final, el monitor de alertas acotado a Solar. |
| `registrar_tareas_solar.ps1` | Registra en el Programador de tareas de Windows la corrida principal y el vigilante. |
| `run_dimensiones.py` | Orquestador de las dimensiones AS400: extract + silver + gold de 16 dimensiones (50 pasos, ~5 min), geografia al final del grupo `pais`, y el monitor acotado a esos procesos. Mismos codigos de salida que `run_solar.py`; bloqueo `logs/run_dimensiones.lock`, log `logs/run_dimensiones_AAAAMMDD_HHMMSS.log`. **Aun no esta programado.** Al crear una dimension nueva, agregarla a `GRUPOS` y su proceso a `PREFIJOS_MONITOR`. |
| `run_ventas.py` | Orquestador de ventas: `dimEmpresas` + `dimProducto` (para que gold resuelva las llaves) y luego el hecho de ventas (extract encabezados -> extract lineas -> silver -> gold), y el monitor acotado a `Ventas Empresas EmpresaMoneda Producto` (`--horas-sin-exito 26`). Si una dimension falla, ventas corre igual; dentro de ventas se detiene al primer error. `--reconciliar` extrae todo el historico (limite 3600 s por paso; 1800 s en la diaria). Bloqueo `logs/run_ventas.lock` (compartido por la diaria y la reconciliacion), log `logs/run_ventas_AAAAMMDD_HHMMSS.log`. Los pasos salen de `db/etl/run_fact.py` y de `run_dimensiones.py`. |
| `registrar_tareas_ventas.ps1` | Registra `JaremarDW-Ventas` (diaria), `JaremarDW-Ventas-Reconciliar` (semanal) y `JaremarDW-Ventas-Vigilante`. Mismas opciones que el de Solar, mas `-DiaReconciliar`, `-HoraReconciliar`, `-HorasVigilante` y `-HorasSinExitoVigilante`. |
| `run_guias.py` | Orquestador de guias de remision: `dimEmpresas`, `dimCliente`, `dimProducto`, `dimVehiculo` y `dimMotivoTraslado`, luego `factGuiasRemision` (extract -> silver -> gold, ventana de 30 dias por fecha de registro) y el monitor acotado a `GuiasRemision Empresas EmpresaMoneda Cliente Producto Vehiculo MotivoTraslado`. `--reconciliar` re-extrae todo desde 2025. Mismo comportamiento, limites y codigos que `run_ventas.py`; bloqueo `logs/run_guias.lock`, log `logs/run_guias_AAAAMMDD_HHMMSS.log`. |
| `registrar_tareas_guias.ps1` | Registra `JaremarDW-Guias`, `JaremarDW-Guias-Reconciliar` y `JaremarDW-Guias-Vigilante`, con las mismas opciones que el de ventas y horarios 30 min despues. |
| `run_compras.py` | Orquestador de compras: `dimEmpresas` + `dimProveedor` (las llaves que resuelve el gold), luego el hecho de compras (extract encabezados -> extract lineas -> silver -> gold) y el monitor acotado a `Compras Empresas EmpresaMoneda Proveedor`. Mismo comportamiento, limites y codigos que `run_ventas.py`; bloqueo `logs/run_compras.lock`, log `logs/run_compras_AAAAMMDD_HHMMSS.log`. |
| `registrar_tareas_compras.ps1` | Registra `JaremarDW-Compras`, `JaremarDW-Compras-Reconciliar` y `JaremarDW-Compras-Vigilante`, con las mismas opciones que el de ventas. |
| `run_pedidos.py` | Orquestador de pedidos de venta: `dimEmpresas`, `dimCliente`, `dimProducto` y `dimRuta`, luego `factPedidos` (extract -> silver -> gold, ventana de 30 dias por fecha de la orden) y el monitor acotado a `Pedidos Empresas EmpresaMoneda Cliente Producto Ruta`. `--reconciliar` re-extrae todo desde 2026. Bloqueo `logs/run_pedidos.lock`, log `logs/run_pedidos_AAAAMMDD_HHMMSS.log`. |
| `registrar_tareas_pedidos.ps1` | Registra `JaremarDW-Pedidos`, `JaremarDW-Pedidos-Reconciliar` y `JaremarDW-Pedidos-Vigilante`, con las mismas opciones que el de ventas. |
| `hecho_programado.py` | Logica comun de `run_ventas.py`, `run_guias.py`, `run_compras.py` y `run_pedidos.py` (dimensiones -> hecho -> monitor, bloqueo, log). Para programar otro hecho AS400, crear un `run_<hecho>.py` con su configuracion (flujo de `run_fact.py`, grupos de `run_dimensiones.py`, prefijos del monitor, limites). |

El monitor (`db/monitor_etl.py`) es de uso general y se queda en `db/`.

## Que se programa

| Tarea | Horario (hora local, UTC-6 sin horario de verano) | Comando |
|---|---|---|
| Corrida principal | 10:30, 17:30, 20:30 | `python db/scheduler/run_solar.py --env-file .env.prod` |
| Vigilante | 12:00, 22:00 | `python db/monitor_etl.py --env-file .env.prod --procesos Sma Huawei Soliscloud Growatt Meteo DeviceCapacity GhiPlan GsaMonthly --horas-sin-exito 16 --sin-repetir-horas 12` |
| Ventas diaria | 05:00 (excepto domingo) y 13:00 | `python db/scheduler/run_ventas.py --env-file .env.prod` |
| Ventas reconciliacion | domingo 02:00 | `python db/scheduler/run_ventas.py --env-file .env.prod --reconciliar` |
| Ventas vigilante | 07:00, 15:00 | `python db/monitor_etl.py --env-file .env.prod --procesos Ventas Empresas EmpresaMoneda Producto --horas-sin-exito 6 --sin-repetir-horas 12` |
| Guias diaria | 05:30 (excepto domingo) y 13:30 | `python db/scheduler/run_guias.py --env-file .env.prod` |
| Guias reconciliacion | domingo 03:00 | `python db/scheduler/run_guias.py --env-file .env.prod --reconciliar` |
| Guias vigilante | 07:30, 15:30 | `python db/monitor_etl.py --env-file .env.prod --procesos GuiasRemision Empresas EmpresaMoneda Cliente Producto Vehiculo MotivoTraslado --horas-sin-exito 6 --sin-repetir-horas 12` |
| Compras diaria | 06:00 (excepto domingo) y 14:00 | `python db/scheduler/run_compras.py --env-file .env.prod` |
| Compras reconciliacion | domingo 04:00 | `python db/scheduler/run_compras.py --env-file .env.prod --reconciliar` |
| Compras vigilante | 08:00, 16:00 | `python db/monitor_etl.py --env-file .env.prod --procesos Compras Empresas EmpresaMoneda Proveedor --horas-sin-exito 6 --sin-repetir-horas 12` |
| Pedidos diaria | 06:30 (excepto domingo) y 14:30 | `python db/scheduler/run_pedidos.py --env-file .env.prod` |
| Pedidos reconciliacion | domingo 05:00 | `python db/scheduler/run_pedidos.py --env-file .env.prod --reconciliar` |
| Pedidos vigilante | 08:30, 16:30 | `python db/monitor_etl.py --env-file .env.prod --procesos Pedidos Empresas EmpresaMoneda Cliente Producto Ruta --horas-sin-exito 6 --sin-repetir-horas 12` |

Ventas se registra aparte con `.\db\scheduler\registrar_tareas_ventas.ps1` (acepta `-WhatIf`, `-Usuario/-Credencial`, `-Deshabilitada`, `-Desinstalar`, `-Horas`, `-DiaReconciliar`, `-HoraReconciliar`, `-HorasVigilante`, `-HorasSinExitoVigilante`). El dia de la reconciliacion se omiten las horas diarias que caen en las 6 h siguientes a ella. La diaria y la reconciliacion tienen limite de 2 h, igual que el vencimiento del bloqueo.

El vigilante corre 2 h despues de cada corrida diaria. `SIN_EXITO` se mide desde el **inicio** del ultimo exito: lo normal a esa hora es <= 2 h (<= 5 h el domingo, por la reconciliacion de las 02:00), y si una corrida no se hizo, fallo o quedo bloqueada, pasa a 10-18 h; por eso el umbral es 6 h. **Si se cambian las horas de ventas, revisar las del vigilante y el umbral.** El monitor que corre al final de cada corrida usa 26 h.

Guias se registra con `.\db\scheduler\registrar_tareas_guias.ps1`, con las mismas opciones y la misma logica de vigilante; sus horarios van 30 min despues de los de ventas para no cargar el AS400 con las dos corridas a la vez. Compras (`.\db\scheduler\registrar_tareas_compras.ps1`) va 30 min despues de guias y pedidos (`.\db\scheduler\registrar_tareas_pedidos.ps1`) 30 min despues de compras, con la misma logica.

Las horas de Solar caen 30-60 min despues de cada lote que deposita el proceso externo (SMA/Soliscloud 02/13/20 UTC, Huawei 13 UTC, meteo 11 UTC). **Si el servidor no esta en UTC-6, ajustar las horas.**

Codigos de salida de `run_solar.py`: `0` ok, `1` un paso fallo, `2` ya habia otra corrida (bloqueo `logs/run_solar.lock`, vence a las 2 h), `3` pasos ok pero el monitor hallo alertas criticas. Log por corrida: `logs/run_solar_AAAAMMDD_HHMMSS.log` (30 dias).

## Requisitos del equipo

- Python 3 con `pyodbc`; ODBC Driver 17 (o superior) para SQL Server.
- Acceso de red a `172.20.6.6\FINANZAS,58092`.
- Repo clonado y `.env.prod` en la raiz con las credenciales `JAREMAR_*` y las variables `ALERT_SMTP_HOST/PORT/USER/PASSWORD/TLS`, `ALERT_EMAIL_FROM`, `ALERT_EMAIL_TO`. **No versionar `.env.prod`.**
- Probar antes de programar:
  ```
  python db/monitor_etl.py --env-file .env.prod --probar-notificacion
  python db/scheduler/run_solar.py --env-file .env.prod --dry-run
  python db/scheduler/run_solar.py --env-file .env.prod
  ```

## Opcion A: Programador de tareas de Windows (recomendada)

Es la que esta implementada y probada. Desde PowerShell **como administrador**, en la raiz del repo:

```powershell
# Ver que haria, sin registrar nada
.\db\scheduler\registrar_tareas_solar.ps1 -WhatIf

# Registrar (corre solo con la sesion abierta)
.\db\scheduler\registrar_tareas_solar.ps1

# Registrar para que corra sin sesion iniciada, con una cuenta de servicio
.\db\scheduler\registrar_tareas_solar.ps1 -Usuario "DOMINIO\svc_etl" -Credencial (Read-Host -AsSecureString)

# Otras opciones: -RutaRepo, -Python, -EnvFile (default .env.prod), -Horas '10:30','17:30','20:30', -Deshabilitada
```

Crea `JaremarDW-Solar` y `JaremarDW-Solar-Vigilante` con: inicia si se perdio la hora (`StartWhenAvailable`), no permite instancias simultaneas, limite de 1 h (15 min el vigilante) y directorio de trabajo en el repo.

La cuenta necesita: lectura del repo y de `.env.prod`, escritura en `logs/`, y el derecho "Iniciar sesion como trabajo por lotes" (Directiva de seguridad local > Asignacion de derechos de usuario).

Verificar y probar:

```powershell
Get-ScheduledTask JaremarDW-Solar* | Get-ScheduledTaskInfo      # LastTaskResult = 0 es correcto
Start-ScheduledTask -TaskName JaremarDW-Solar                   # disparo manual
Get-ChildItem logs\run_solar_*.log | Sort LastWriteTime | Select -Last 1
```

Quitar: `.\db\scheduler\registrar_tareas_solar.ps1 -Desinstalar`

Configuracion manual (sin el script), en `taskschd.msc` > Crear tarea:
1. **General:** nombre `JaremarDW-Solar`; "Ejecutar tanto si el usuario inicio sesion como si no"; sin privilegios elevados.
2. **Desencadenadores:** 3 diarios (10:30, 17:30, 20:30).
3. **Acciones:** Programa `C:\...\python.exe`; Argumentos `"C:\...\JaremarDW\db\scheduler\run_solar.py" --env-file "C:\...\JaremarDW\.env.prod"`; Iniciar en `C:\...\JaremarDW`.
4. **Configuracion:** "Ejecutar lo antes posible si se omitio una ejecucion"; "No iniciar una nueva instancia" si ya se ejecuta; detener tras 1 hora.
5. Repetir para el vigilante con `db\monitor_etl.py` y los argumentos de la tabla de arriba.

## Opcion B: SQL Server Agent

El orquestador es Python, asi que el Agent solo lo **invoca** con un paso de tipo sistema operativo; el Agent debe correr en un equipo que tenga Python y el repo (normalmente el mismo servidor SQL o uno junto a el).

**Restriccion actual:** el usuario ETL (`svc_etl_jaremar_write_prod`) no es sysadmin ni ve `msdb`; **un DBA debe crear los jobs**. Ademas la cuenta de servicio del Agent (o un proxy) debe poder leer el repo y `.env.prod` y escribir en `logs/`.

1. Crear una credencial y un **proxy** del Agent para "Sistema operativo (CmdExec)" con la cuenta de Windows que tiene acceso al repo (o usar la cuenta de servicio del Agent).
2. Crear el job `JaremarDW-Solar` (SSMS > SQL Server Agent > Jobs > New Job):
   - **Steps:** un paso, tipo `Operating system (CmdExec)`, ejecutar como el proxy, comando (ajustar rutas):
     ```
     "C:\Python313\python.exe" "D:\JaremarDW\db\scheduler\run_solar.py" --env-file "D:\JaremarDW\.env.prod"
     ```
     Si el paso falla con el codigo de salida `1`/`2`/`3`, el Agent lo marca como error (cualquier codigo distinto de 0). Para reintentar un fallo transitorio: reintentos = 1, intervalo = 5 min.
   - **Schedules:** diario a las 10:30, 17:30 y 20:30 (tres schedules, porque los horarios no son equidistantes).
   - **Notifications:** operador con correo al fallar (requiere Database Mail configurado). Es un aviso adicional al correo del propio monitor.
3. Crear el job `JaremarDW-Solar-Vigilante` con un paso CmdExec:
   ```
   "C:\Python313\python.exe" "D:\JaremarDW\db\monitor_etl.py" --env-file "D:\JaremarDW\.env.prod" --procesos Sma Huawei Soliscloud Growatt Meteo DeviceCapacity GhiPlan GsaMonthly --horas-sin-exito 16 --sin-repetir-horas 12
   ```
   y schedules diarios a las 12:00 y 22:00.
4. Probar: clic derecho en el job > "Start Job at Step..." y revisar el historial y `logs/`.

Si el Agent corre en Linux (SQL Server en Linux) el paso seria de tipo `Operating system` con `python3` y rutas Linux; el `.ps1` no aplica.

Sin Python en el servidor no hay equivalente 100 % T-SQL: los scripts `load_silver_*` / `load_gold_*` solo abren la corrida en el framework `dbo` y llaman a los SPs `[int].usp_Merge*` y `dw.usp_Merge*`, pero esa orquestacion (registro de corridas, watermark) esta escrita en Python; portarla a T-SQL seria un trabajo aparte.

## Reglas para agregar nuevos procesos programados

- Crear el orquestador en esta carpeta (`run_<dominio>.py`), con los mismos codigos de salida, bloqueo y log, y su script de registro (`registrar_tareas_<dominio>.ps1`).
- Documentarlo en este README y en la seccion "Programacion" de `CLAUDE.md`.
- Los grupos deben ser independientes; dentro de un grupo, respetar dependencias (dimension -> hecho) y detenerse al primer error.

## Limites conocidos

- Si el servidor esta apagado, ni la corrida ni el vigilante avisan (viven en el mismo equipo). Mitigacion opcional: correr el monitor desde otro equipo.
- La alerta `SIN_EXITO` mide corridas propias, no la frescura de `stg`; si el proceso externo deja de depositar datos, no se detecta.
- Solar no cubre los flujos AS400 ni las cargas manuales (`dimPlanGeneracion`, geografia). De los hechos AS400 estan programados ventas, guias de remision, compras y pedidos (envios aun no).
