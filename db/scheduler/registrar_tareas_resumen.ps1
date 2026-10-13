<#
.SYNOPSIS
  Registra en el Programador de tareas de Windows el resumen diario por correo de todas las corridas del ETL.

.DESCRIPTION
  Crea una tarea:
    JaremarDW-Resumen  corre db\reporte_diario.py a la hora de -Hora (default 08:30): un correo con las
                       corridas de las ultimas 24 h por dominio (estado, filas extraidas, cambios en gold),
                       los errores del periodo, los dominios sin corridas y las alertas vigentes.

  Las 08:30 quedan despues de las corridas completas de la madrugada (ventas 02:00, compras 06:00,
  envios 07:00) y de las primeras del dia; la de SanAlejo (08:00) entra si ya termino. Los errores se
  siguen avisando al momento por el monitor de cada corrida.

  Requisitos en el equipo: Python 3 con pyodbc, ODBC Driver for SQL Server, acceso de red a la base,
  el repo y el archivo .env.prod con ALERT_*. No lleva rutas ni usuarios fijos.

.PARAMETER RutaRepo     Carpeta del repo (default: dos niveles arriba de este script).
.PARAMETER Python       Ejecutable de Python (default: el primero que resuelva 'python' en el PATH).
.PARAMETER EnvFile      Archivo .env, relativo al repo o absoluto (default .env.prod).
.PARAMETER Hora         Hora del resumen, formato HH:mm.
.PARAMETER Usuario      Cuenta con la que corre la tarea aunque no haya sesion iniciada (junto a -Credencial).
.PARAMETER Credencial   Contrasena de -Usuario (SecureString). Sin -Usuario, la tarea corre solo con la sesion abierta.
.PARAMETER Deshabilitada  Crea la tarea deshabilitada (para probarla con Start-ScheduledTask).
.PARAMETER Desinstalar  Elimina la tarea y sale.

.EXAMPLE
  .\registrar_tareas_resumen.ps1 -WhatIf
.EXAMPLE
  .\registrar_tareas_resumen.ps1 -Usuario "DOMINIO\svc_etl" -Credencial (Read-Host -AsSecureString)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RutaRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Python = '',
    [string]$EnvFile = '.env.prod',
    [string]$Hora = '08:30',
    [string]$Usuario = '',
    [securestring]$Credencial = $null,
    [switch]$Deshabilitada,
    [switch]$Desinstalar
)

$ErrorActionPreference = 'Stop'
$Nombre = 'JaremarDW-Resumen'

if ($Desinstalar) {
    if (Get-ScheduledTask -TaskName $Nombre -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($Nombre, 'Eliminar tarea')) {
            Unregister-ScheduledTask -TaskName $Nombre -Confirm:$false
            Write-Host "Eliminada: $Nombre"
        }
    } else {
        Write-Host "No existe: $Nombre"
    }
    return
}

if (-not $Python) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "No se encontro 'python' en el PATH; indica -Python con la ruta completa." }
    $Python = $cmd.Source
}
if (-not (Test-Path $Python)) { throw "No existe el ejecutable de Python: $Python" }

$script = Join-Path $RutaRepo 'db\reporte_diario.py'
if (-not (Test-Path $script)) { throw "No existe: $script" }

$envRuta = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $RutaRepo $EnvFile }
if (-not (Test-Path $envRuta)) { Write-Warning "No existe el archivo de entorno: $envRuta (la tarea fallara hasta que se cree)." }

$tmp = [datetime]::MinValue
if (-not [datetime]::TryParseExact($Hora, 'HH:mm', $null, 'None', [ref]$tmp)) { throw "Hora invalida '$Hora' (usa HH:mm)." }

$accion = New-ScheduledTaskAction -Execute $Python -Argument "`"$script`" --env-file `"$envRuta`"" -WorkingDirectory $RutaRepo
$disparador = New-ScheduledTaskTrigger -Daily -At $Hora
$config = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
if ($Deshabilitada) { $config.Enabled = $false }

if ($PSCmdlet.ShouldProcess($Nombre, "Registrar tarea (diaria $Hora)")) {
    $params = @{ TaskName = $Nombre; Action = $accion; Trigger = $disparador; Settings = $config; Force = $true
                 Description = 'JaremarDW: resumen diario por correo de todas las corridas del ETL (db\reporte_diario.py).' }
    if ($Usuario) {
        if (-not $Credencial) { throw '-Usuario requiere -Credencial.' }
        $plano = [System.Net.NetworkCredential]::new('', $Credencial).Password
        Register-ScheduledTask @params -User $Usuario -Password $plano -RunLevel Limited | Out-Null
    } else {
        Register-ScheduledTask @params | Out-Null
    }
    Write-Host "Registrada: $Nombre  [diaria $Hora]$(if ($Deshabilitada) { '  (deshabilitada)' })"
}

Write-Host "`nPython : $Python`nRepo   : $RutaRepo`nEntorno: $envRuta"
Write-Host "Probar : Start-ScheduledTask -TaskName $Nombre (envia el correo)"
