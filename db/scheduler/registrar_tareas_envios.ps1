<#
.SYNOPSIS
  Registra en el Programador de tareas de Windows la ejecucion desatendida de envios.

.DESCRIPTION
  Crea dos tareas:
    JaremarDW-Envios            corre db\scheduler\run_envios.py (dimVehiculo + hecho de envios + monitor) a
                                las horas de -Horas (default 07:00 y 15:00).
    JaremarDW-Envios-Vigilante  corre db\monitor_etl.py acotado a envios y dimVehiculo a las horas de
                                -HorasVigilante (default 09:00 y 17:00), para avisar si una corrida no se hizo,
                                fallo o se colgo (alerta SIN_EXITO a -HorasSinExitoVigilante, default 6 h).

  No hay tarea de reconciliacion: el extract de envios ya es FULL (ver run_envios.py).

  Los horarios van despues de los de ventas (05:00), guias (05:30), compras (06:00) y manifiestos (06:30)
  para no cargar el AS400 con varias corridas a la vez.

  El umbral del vigilante se mide desde el INICIO del ultimo exito de cada proceso. Con los defaults, lo
  normal a la hora del vigilante es <= 2 h, y si falta una corrida pasa a 10-18 h. Si cambias -Horas,
  ajusta -HorasVigilante y el umbral.

  Requisitos en el equipo: Python 3 con pyodbc, ODBC Driver for SQL Server, acceso de red a la base y al
  AS400, el repo clonado y el archivo .env.prod (credenciales + ALERT_*). No lleva rutas ni usuarios fijos.

.PARAMETER RutaRepo         Carpeta del repo (default: dos niveles arriba de este script).
.PARAMETER Python           Ejecutable de Python (default: el primero que resuelva 'python' en el PATH).
.PARAMETER EnvFile          Archivo .env, relativo al repo o absoluto (default .env.prod).
.PARAMETER Horas            Horas de la corrida diaria, formato HH:mm.
.PARAMETER HorasVigilante   Horas del vigilante, formato HH:mm.
.PARAMETER HorasSinExitoVigilante  Horas sin exito a partir de las cuales el vigilante alerta.
.PARAMETER Usuario          Cuenta con la que corren las tareas aunque no haya sesion iniciada (junto a -Credencial).
.PARAMETER Credencial       Contrasena de -Usuario (SecureString). Sin -Usuario, las tareas corren solo con la sesion abierta.
.PARAMETER Deshabilitada    Crea las tareas deshabilitadas (para probarlas con Start-ScheduledTask).
.PARAMETER Desinstalar      Elimina las dos tareas y sale.

.EXAMPLE
  .\registrar_tareas_envios.ps1 -WhatIf
.EXAMPLE
  .\registrar_tareas_envios.ps1 -Usuario "DOMINIO\svc_etl" -Credencial (Read-Host -AsSecureString)
.EXAMPLE
  .\registrar_tareas_envios.ps1 -Desinstalar
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RutaRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Python = '',
    [string]$EnvFile = '.env.prod',
    [string[]]$Horas = @('07:00', '15:00'),
    [string[]]$HorasVigilante = @('09:00', '17:00'),
    [int]$HorasSinExitoVigilante = 6,
    [string]$Usuario = '',
    [securestring]$Credencial = $null,
    [switch]$Deshabilitada,
    [switch]$Desinstalar
)

$ErrorActionPreference = 'Stop'
$NombreDiaria = 'JaremarDW-Envios'
$NombreVigilante = 'JaremarDW-Envios-Vigilante'
$Prefijos = 'Envios Vehiculo'

if ($Desinstalar) {
    foreach ($n in $NombreDiaria, $NombreVigilante) {
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

$scriptRun = Join-Path $RutaRepo 'db\scheduler\run_envios.py'
$scriptMon = Join-Path $RutaRepo 'db\monitor_etl.py'
foreach ($f in $scriptRun, $scriptMon) { if (-not (Test-Path $f)) { throw "No existe: $f" } }

$envRuta = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $RutaRepo $EnvFile }
if (-not (Test-Path $envRuta)) { Write-Warning "No existe el archivo de entorno: $envRuta (las tareas fallaran hasta que se cree)." }

function Leer-Hora([string]$h) {
    $tmp = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($h, 'HH:mm', $null, 'None', [ref]$tmp)) { throw "Hora invalida '$h' (usa HH:mm)." }
    return $tmp.TimeOfDay
}
foreach ($h in $Horas + $HorasVigilante) { Leer-Hora $h | Out-Null }

$dispDiaria = @($Horas | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })
$dispVigilante = @($HorasVigilante | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })

$argDiaria = "`"$scriptRun`" --env-file `"$envRuta`""
$argVigilante = "`"$scriptMon`" --env-file `"$envRuta`" --procesos $Prefijos --horas-sin-exito $HorasSinExitoVigilante --sin-repetir-horas 12"

function Nueva-Tarea([string]$nombre, [string]$argumentos, $disparadores, [string]$detalle, [int]$limiteMin, [string]$descripcion) {
    $accion = New-ScheduledTaskAction -Execute $Python -Argument $argumentos -WorkingDirectory $RutaRepo
    $config = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $limiteMin) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    if ($Deshabilitada) { $config.Enabled = $false }

    if ($PSCmdlet.ShouldProcess($nombre, "Registrar tarea ($detalle)")) {
        $params = @{ TaskName = $nombre; Action = $accion; Trigger = $disparadores; Settings = $config; Description = $descripcion; Force = $true }
        if ($Usuario) {
            if (-not $Credencial) { throw '-Usuario requiere -Credencial.' }
            $plano = [System.Net.NetworkCredential]::new('', $Credencial).Password
            Register-ScheduledTask @params -User $Usuario -Password $plano -RunLevel Limited | Out-Null
        } else {
            Register-ScheduledTask @params | Out-Null
        }
        Write-Host "Registrada: $nombre  [$detalle]$(if ($Deshabilitada) { '  (deshabilitada)' })"
    }
}

# Limite de 2 h: coincide con el vencimiento del bloqueo logs\run_envios.lock.
Nueva-Tarea $NombreDiaria $argDiaria $dispDiaria ($Horas -join ', ') 120 `
    'JaremarDW: dimVehiculo + envios (extract FULL) y monitor (db\scheduler\run_envios.py).'
Nueva-Tarea $NombreVigilante $argVigilante $dispVigilante ($HorasVigilante -join ', ') 15 `
    "JaremarDW: vigilante de envios; avisa si no hay corridas exitosas en $HorasSinExitoVigilante h."

Write-Host "`nPython : $Python`nRepo   : $RutaRepo`nEntorno: $envRuta"
Write-Host "Probar : Start-ScheduledTask -TaskName $NombreDiaria ; luego revisar $RutaRepo\logs"
