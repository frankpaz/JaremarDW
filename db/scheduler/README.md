# Programar Ejecucion (db/scheduler)

Aqui viven **todos los procesos pensados para correr desatendidos** (orquestadores y scripts de registro de tareas). Los scripts de carga de cada tabla siguen en `db/etl/<Tabla>/`; esta carpeta solo los orquesta.

| Archivo | Que hace |
|---|---|
| `run_solar.py` | Orquestador del dominio Solar: silver + gold de 15 tablas (30 pasos, ~1 min) y, al final, el monitor de alertas acotado a Solar. |
| `registrar_tareas_solar.ps1` | Registra en el Programador de tareas de Windows la corrida principal y el vigilante. |
| `run_dimensiones.py` | Orquestador de las dimensiones AS400: extract + silver + gold de 15 dimensiones (47 pasos, ~3 min), geografia al final del grupo `pais`, y el monitor acotado a esos procesos. Mismos codigos de salida que `run_solar.py`; bloqueo `logs/run_dimensiones.lock`, log `logs/run_dimensiones_AAAAMMDD_HHMMSS.log`. **Aun no esta programado.** Al crear una dimension nueva, agregarla a `GRUPOS` y su proceso a `PREFIJOS_MONITOR`. |

El monitor (`db/monitor_etl.py`) es de uso general y se queda en `db/`.

## Que se programa

| Tarea | Horario (hora local, UTC-6 sin horario de verano) | Comando |
|---|---|---|
| Corrida principal | 10:30, 17:30, 20:30 | `python db/scheduler/run_solar.py --env-file .env.prod` |
| Vigilante | 12:00, 22:00 | `python db/monitor_etl.py --env-file .env.prod --procesos Sma Huawei Soliscloud Growatt Meteo DeviceCapacity GhiPlan GsaMonthly --horas-sin-exito 16 --sin-repetir-horas 12` |

Las horas caen 30-60 min despues de cada lote que deposita el proceso externo (SMA/Soliscloud 02/13/20 UTC, Huawei 13 UTC, meteo 11 UTC). **Si el servidor no esta en UTC-6, ajustar las horas.**

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
- No cubre los flujos AS400 ni las cargas manuales (`dimPlanGeneracion`, geografia).
