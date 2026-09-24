<#
.SYNOPSIS
  Registra en el Programador de tareas de Windows la ejecucion desatendida del dominio Solar.

.DESCRIPTION
  Crea dos tareas:
    JaremarDW-Solar            corre db\scheduler\run_solar.py (silver+gold de las 15 tablas solares + monitor)
                               a las horas de -Horas (default 10:30, 17:30, 20:30 hora local del equipo).
    JaremarDW-Solar-Vigilante  corre db\monitor_etl.py acotado a Solar a las 12:00 y 22:00, para avisar
                               si el orquestador no corrio o se colgo (alerta SIN_EXITO a 16 h).

  Las horas asumen un equipo en UTC-6 sin horario de verano: cada corrida queda 30-60 min despues de un
  lote del proceso externo (SMA/Soliscloud 02/13/20 UTC, Huawei 13 UTC, meteo 11 UTC). Si el servidor
  tiene otra zona horaria, ajusta -Horas.

  Requisitos en el equipo: Python 3 con pyodbc, ODBC Driver for SQL Server, acceso de red a la base,
  el repo clonado y el archivo .env.prod (credenciales + ALERT_*). No lleva rutas ni usuarios fijos.

.PARAMETER RutaRepo    Carpeta del repo (default: dos niveles arriba de este script).
.PARAMETER Python      Ejecutable de Python (default: el primero que resuelva 'python' en el PATH).
.PARAMETER EnvFile     Archivo .env, relativo al repo o absoluto (default .env.prod).
.PARAMETER Horas       Horas de la corrida principal, formato HH:mm.
.PARAMETER Usuario     Cuenta con la que corren las tareas aunque no haya sesion iniciada (junto a -Credencial).
.PARAMETER Credencial  Contrasena de -Usuario (SecureString). Sin -Usuario, las tareas corren solo con la sesion abierta.
.PARAMETER Deshabilitada  Crea las tareas deshabilitadas (para probarlas con Start-ScheduledTask).
.PARAMETER Desinstalar Elimina ambas tareas y sale.

.EXAMPLE
  .\registrar_tareas_solar.ps1 -WhatIf
.EXAMPLE
  .\registrar_tareas_solar.ps1 -Usuario "DOMINIO\svc_etl" -Credencial (Read-Host -AsSecureString)
.EXAMPLE
  .\registrar_tareas_solar.ps1 -Desinstalar
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RutaRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Python = '',
    [string]$EnvFile = '.env.prod',
    [string[]]$Horas = @('10:30', '17:30', '20:30'),
    [string]$Usuario = '',
    [securestring]$Credencial = $null,
    [switch]$Deshabilitada,
    [switch]$Desinstalar
)

$ErrorActionPreference = 'Stop'
$NombrePrincipal = 'JaremarDW-Solar'
$NombreVigilante = 'JaremarDW-Solar-Vigilante'
$HorasVigilante = @('12:00', '22:00')
$Prefijos = 'Sma Huawei Soliscloud Growatt Meteo DeviceCapacity GhiPlan GsaMonthly'

if ($Desinstalar) {
    foreach ($n in $NombrePrincipal, $NombreVigilante) {
        if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($n, 'Eliminar tarea')) {
                Unregister-ScheduledTask -TaskName $n -Confirm:$false
                Write-Host "Eliminada: $n"
            }
        } else {
            Write-Host "No existe: $n"
        }
    }
    return
}

if (-not $Python) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "No se encontro 'python' en el PATH; indica -Python con la ruta completa." }
    $Python = $cmd.Source
}
if (-not (Test-Path $Python)) { throw "No existe el ejecutable de Python: $Python" }

$scriptRun = Join-Path $RutaRepo 'db\scheduler\run_solar.py'
$scriptMon = Join-Path $RutaRepo 'db\monitor_etl.py'
foreach ($f in $scriptRun, $scriptMon) { if (-not (Test-Path $f)) { throw "No existe: $f" } }

$envRuta = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $RutaRepo $EnvFile }
if (-not (Test-Path $envRuta)) { Write-Warning "No existe el archivo de entorno: $envRuta (las tareas fallaran hasta que se cree)." }

foreach ($h in $Horas + $HorasVigilante) {
    $tmp = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($h, 'HH:mm', $null, 'None', [ref]$tmp)) { throw "Hora invalida '$h' (usa HH:mm)." }
}

$argPrincipal = "`"$scriptRun`" --env-file `"$envRuta`""
$argVigilante = "`"$scriptMon`" --env-file `"$envRuta`" --procesos $Prefijos --horas-sin-exito 16 --sin-repetir-horas 12"

function Nueva-Tarea([string]$nombre, [string]$argumentos, [string[]]$horas, [int]$limiteMin, [string]$descripcion) {
    $accion = New-ScheduledTaskAction -Execute $Python -Argument $argumentos -WorkingDirectory $RutaRepo
    $disparadores = @($horas | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })
    $config = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $limiteMin) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    if ($Deshabilitada) { $config.Enabled = $false }

    if ($PSCmdlet.ShouldProcess($nombre, "Registrar tarea ($($horas -join ', '))")) {
        $params = @{ TaskName = $nombre; Action = $accion; Trigger = $disparadores; Settings = $config; Description = $descripcion; Force = $true }
        if ($Usuario) {
            if (-not $Credencial) { throw '-Usuario requiere -Credencial.' }
            $plano = [System.Net.NetworkCredential]::new('', $Credencial).Password
            Register-ScheduledTask @params -User $Usuario -Password $plano -RunLevel Limited | Out-Null
        } else {
            Register-ScheduledTask @params | Out-Null
        }
        Write-Host "Registrada: $nombre  [$($horas -join ', ')]$(if ($Deshabilitada) { '  (deshabilitada)' })"
    }
}

Nueva-Tarea $NombrePrincipal $argPrincipal $Horas 60 'JaremarDW: silver+gold del dominio Solar y monitor de alertas (db\scheduler\run_solar.py).'
Nueva-Tarea $NombreVigilante $argVigilante $HorasVigilante 15 'JaremarDW: vigilante del dominio Solar; avisa si no hay corridas exitosas en 16 h.'

Write-Host "`nPython : $Python`nRepo   : $RutaRepo`nEntorno: $envRuta"
Write-Host "Probar : Start-ScheduledTask -TaskName $NombrePrincipal ; luego revisar $RutaRepo\logs"
