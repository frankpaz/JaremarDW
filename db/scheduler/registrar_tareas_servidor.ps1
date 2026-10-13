<#
.SYNOPSIS
  Registra en el servidor las tareas de JaremarDW de uno o varios dominios, con una sola cuenta y
  revisando antes lo que hizo fallar los primeros registros.

.DESCRIPTION
  Antes de registrar verifica:
    - PowerShell como administrador (registrar con otra cuenta lo requiere).
    - Python instalado para todos (no en C:\Users ni el alias de WindowsApps).
    - pyodbc visible para cualquier cuenta (python -s: sin el site-packages del usuario).
    - Drivers ODBC de SQL Server (JAREMAR_ODBC_DRIVER) y, si hay dominios AS400, de IBM i (AS400_DRIVER).
    - El archivo .env y la contrasena de la cuenta (contra el dominio, si se puede).
  Luego da a la cuenta permiso de modificacion en el repo y de lectura en el .env (con -RunLevel Limited
  no le sirve ser administradora), y llama a registrar_tareas_<dominio>.ps1 de cada dominio SIEMPRE con
  -Usuario/-Credencial: las tareas corren sin sesion abierta y sin ventana (LogonType Password).
  Al final lista las tareas con su cuenta y tipo de inicio.

  Los horarios son los defaults de cada registrar_tareas_<dominio>.ps1 (ver db/scheduler/README.md).
  Volver a correrlo reemplaza las tareas (sirve tambien tras cambiar la contrasena de la cuenta).

.PARAMETER Dominios  Separados por coma: solar, ventas, guias, compras, manifiestos, envios, bascula, sanalejo, dimensiones, resumen (correo diario) o todos.
.PARAMETER Usuario   Cuenta con la que corren las tareas (ej. DOMINIO\cuenta).
.PARAMETER Credencial  Contrasena de -Usuario; si no se indica, se pide.
.PARAMETER RutaRepo  Carpeta del repo (default: dos niveles arriba de este script).
.PARAMETER Python    Ejecutable de Python (default: el primero que resuelva 'python' en el PATH).
.PARAMETER EnvFile   Archivo .env, relativo al repo o absoluto (default .env.prod).
.PARAMETER Desinstalar  Elimina las tareas de los dominios indicados y sale.

.EXAMPLE
  .\db\scheduler\registrar_tareas_servidor.ps1 -Dominios ventas -Usuario "JAREMAR\operador1" -WhatIf
.EXAMPLE
  .\db\scheduler\registrar_tareas_servidor.ps1 -Dominios ventas,guias -Usuario "JAREMAR\operador1"
.EXAMPLE
  .\db\scheduler\registrar_tareas_servidor.ps1 -Dominios todos -Usuario "JAREMAR\operador1"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('solar', 'ventas', 'guias', 'compras', 'manifiestos', 'envios', 'bascula', 'sanalejo', 'dimensiones', 'resumen', 'todos')]
    [string[]]$Dominios,
    [string]$Usuario = '',
    [securestring]$Credencial = $null,
    [string]$RutaRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Python = '',
    [string]$EnvFile = '.env.prod',
    [switch]$Desinstalar
)

$ErrorActionPreference = 'Stop'
$Orden = @('solar', 'ventas', 'guias', 'compras', 'manifiestos', 'envios', 'bascula', 'sanalejo', 'dimensiones', 'resumen')
if ($Dominios -contains 'todos') { $Dominios = $Orden }
$Dominios = @($Orden | Where-Object { $Dominios -contains $_ })
$soloPrueba = [bool]$WhatIfPreference

$errores = New-Object System.Collections.Generic.List[string]
function Ok([string]$m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Falla([string]$m) { $errores.Add($m); Write-Host "  FALLA $m" -ForegroundColor Red }

if ($Desinstalar) {
    foreach ($d in $Dominios) { & (Join-Path $PSScriptRoot "registrar_tareas_$d.ps1") -Desinstalar -WhatIf:$soloPrueba }
    return
}
if (-not $Usuario) { throw 'Indica -Usuario (ej. "JAREMAR\operador1"): sin cuenta las tareas solo corren con sesion abierta y muestran ventana.' }

Write-Host "`n== Verificaciones ==" -ForegroundColor Cyan

# Administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Ok 'PowerShell como administrador' }
elseif ($soloPrueba) { Write-Warning 'PowerShell sin elevar: en la corrida real abrela como administrador.' }
else { Falla 'PowerShell sin elevar: abrela con "Ejecutar como administrador".' }

# Python para todos
if (-not $Python) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $Python = $cmd.Source }
}
if (-not $Python -or -not (Test-Path $Python)) { Falla "No se encontro Python ('$Python'); indica -Python con la ruta completa." }
elseif ($Python -like '*\WindowsApps\*') { Falla "Python es el alias de Microsoft Store ($Python): desactivalo o indica -Python." }
elseif ($Python -like "$env:SystemDrive\Users\*") { Falla "Python esta instalado solo para un usuario ($Python): instalalo para todos." }
else { Ok "Python: $Python" }

# .env
$envRuta = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $RutaRepo $EnvFile }
$envVars = @{}
if (Test-Path $envRuta) {
    Get-Content $envRuta | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { $envVars[$Matches[1]] = $Matches[2].Trim('"', "'") }
    }
    Ok "Entorno: $envRuta"
} else { Falla "No existe el archivo de entorno: $envRuta" }

# pyodbc y drivers, tal como los veria otra cuenta (-s: sin el site-packages del usuario)
if ($errores.Count -eq 0) {
    # Windows PowerShell trata el stderr de un ejecutable como error si ErrorActionPreference = Stop.
    $ErrorActionPreference = 'Continue'
    $salida = @(& $Python -s -c "import pyodbc; print(pyodbc.__file__); print('|'.join(pyodbc.drivers()))" 2>$null)
    $rc = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($rc -ne 0 -or $salida.Count -lt 2) {
        Falla "pyodbc no esta instalado para todos. En PowerShell de administrador: & `"$Python`" -s -m pip install pyodbc"
    } else {
        $rutaPyodbc, $drivers = @($salida)[0], (@($salida)[1] -split '\|')
        if ($rutaPyodbc -like "$env:SystemDrive\Users\*") { Falla "pyodbc esta en un perfil de usuario ($rutaPyodbc): reinstalalo con -s como administrador." }
        else { Ok "pyodbc: $rutaPyodbc" }

        $necesarios = @(@{ Var = 'JAREMAR_ODBC_DRIVER'; Para = 'SQL Server' })
        if ($Dominios | Where-Object { $_ -notin 'solar', 'resumen' }) { $necesarios += @{ Var = 'AS400_DRIVER'; Para = 'AS400' } }
        foreach ($n in $necesarios) {
            $drv = $envVars[$n.Var]
            if (-not $drv) { Falla "$($n.Var) no esta en $envRuta." }
            elseif ($drivers -contains $drv) { Ok "Driver $($n.Para): $drv" }
            else { Falla "Driver $($n.Para) '$drv' ($($n.Var)) no esta instalado. Instalados: $($drivers -join ', ')" }
        }
        if ($necesarios.Count -gt 1) {
            foreach ($v in 'AS400_HOST', 'AS400_USER', 'AS400_PASSWORD') { if (-not $envVars[$v]) { Falla "$v no esta en $envRuta." } }
        }
    }
}

# Cuenta y contrasena
$cuentaSid = $null
try { $cuentaSid = (New-Object Security.Principal.NTAccount($Usuario)).Translate([Security.Principal.SecurityIdentifier]).Value; Ok "Cuenta: $Usuario ($cuentaSid)" }
catch { Falla "La cuenta '$Usuario' no existe o no se pudo resolver." }

if ($errores.Count -gt 0) {
    Write-Host "`nNo se registro nada: corrige lo marcado como FALLA y vuelve a correrlo." -ForegroundColor Red
    exit 1
}

if (-not $soloPrueba) {
    if (-not $Credencial) { $Credencial = Read-Host -AsSecureString "Contrasena de $Usuario" }
    $partes = $Usuario -split '\\', 2
    if ($partes.Count -eq 2 -and $partes[0] -ne $env:COMPUTERNAME -and $partes[0] -ne '.') {
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $partes[0])
            $plano = [System.Net.NetworkCredential]::new('', $Credencial).Password
            if (-not $ctx.ValidateCredentials($partes[1], $plano)) { throw 'Contrasena incorrecta.' }
            Ok 'Contrasena validada contra el dominio'
        } catch {
            if ($_.Exception.Message -eq 'Contrasena incorrecta.') { Write-Host "  FALLA Contrasena incorrecta para $Usuario. No se registro nada." -ForegroundColor Red; exit 1 }
            Write-Warning "No se pudo validar la contrasena contra el dominio ($($_.Exception.Message)); si es incorrecta, fallara el registro."
        }
    }

    Write-Host "`n== Permisos de $Usuario ==" -ForegroundColor Cyan
    & icacls $RutaRepo /grant "*$($cuentaSid):(OI)(CI)M" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls fallo sobre $RutaRepo" }
    & icacls $envRuta /grant "*$($cuentaSid):R" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls fallo sobre $envRuta" }
    Ok "Modificacion en $RutaRepo, lectura en $envRuta"
} else {
    Write-Host "`n(-WhatIf: no se pide contrasena ni se cambian permisos)" -ForegroundColor Yellow
}

Write-Host "`n== Registro ==" -ForegroundColor Cyan
foreach ($d in $Dominios) {
    Write-Host "-- $d" -ForegroundColor Cyan
    $p = @{ RutaRepo = $RutaRepo; Python = $Python; EnvFile = $envRuta; Usuario = $Usuario; WhatIf = $soloPrueba }
    if (-not $soloPrueba) { $p.Credencial = $Credencial }
    & (Join-Path $PSScriptRoot "registrar_tareas_$d.ps1") @p
}

if (-not $soloPrueba) {
    Write-Host "`n== Tareas JaremarDW en este equipo ==" -ForegroundColor Cyan
    $tareas = Get-ScheduledTask -TaskName 'JaremarDW-*' -ErrorAction SilentlyContinue
    $tareas | Select-Object TaskName, @{n = 'Usuario'; e = { $_.Principal.UserId } }, @{n = 'Inicio'; e = { $_.Principal.LogonType } }, State |
        Format-Table -AutoSize | Out-Host
    $interactivas = @($tareas | Where-Object { $_.Principal.LogonType -ne 'Password' })
    if ($interactivas) {
        Write-Warning "Tareas que muestran ventana y solo corren con sesion abierta: $($interactivas.TaskName -join ', '). Registra su dominio con este script."
    }
    Write-Host "Probar: Start-ScheduledTask -TaskName <tarea> ; luego Get-ScheduledTask JaremarDW-* | Get-ScheduledTaskInfo"
}
