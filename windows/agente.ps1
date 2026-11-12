# agente de win-control: abre y cierra apps dentro de la sesion RemoteApp y la cierra
# (logoff) cuando ya no queda ninguna, porque Windows 11 24H2 no restaura RemoteApp al reconectar.
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
# -Escritorio: corre dentro del escritorio completo de `win presentar` (lo arranca el acceso
# directo de Inicio); ahí solo abre apps: no cierra la sesión al quedar sin apps.
param([Parameter(Mandatory = $true)][string]$Dir, [switch]$Escritorio)

$ErrorActionPreference = 'SilentlyContinue'
$cola = Join-Path $Dir 'cola'
$estado = Join-Path $Dir 'abiertas.txt'
$nombres = @{}                 # proceso -> nombre visible
$inicio = Get-Date
$vacioDesde = $null
$cortadoDesde = $null
$GRACIA_INICIO = 25            # s: Office tarda en arrancar la primera vez
$GRACIA_VACIO = 6              # s sin apps antes de cerrar la sesion
$GRACIA_CORTE = 5              # s desconectado antes de cerrar la sesion
$registro = Join-Path $Dir 'agente.log'

# registro local en Windows: nunca se traba aunque la unidad compartida (\\tsclient) quede ocupada
$localDir = Join-Path $env:LOCALAPPDATA 'win-control'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$localLog = Join-Path $localDir 'agente.log'
$ultimoPaso = Join-Path $localDir 'ultimo-paso.txt'

function Log([string]$t) {
    $linea = '{0:HH:mm:ss} {1}' -f (Get-Date), $t
    Add-Content -LiteralPath $localLog -Encoding UTF8 -Value $linea
    Add-Content -LiteralPath $registro -Encoding UTF8 -Value $linea
}

# el ultimo paso se sobrescribe en cada etapa: si el agente se cuelga, dice donde quedo
function Paso([string]$t) {
    [IO.File]::WriteAllText($ultimoPaso, ('{0:HH:mm:ss.fff} {1}' -f (Get-Date), $t))
}

function Atender {
    Get-ChildItem -LiteralPath $cola -Filter '*.pedido' | Sort-Object Name | ForEach-Object {
        $l = @(Get-Content -LiteralPath $_.FullName -Encoding UTF8)
        Remove-Item -LiteralPath $_.FullName -Force
        switch ($l[0]) {
            'abrir' {
                $exe = $l[1]
                $proc = [IO.Path]::GetFileNameWithoutExtension($exe)
                $script:nombres[$proc] = $l[2]
                Log "abrir $proc"
                Paso "Start-Process $proc"
                if ($l.Count -gt 3 -and $l[3]) {
                    Start-Process -FilePath $exe -ArgumentList ('"{0}"' -f $l[3])
                } else {
                    Start-Process -FilePath $exe
                }
            }
            'cerrar' { Log "cerrar $($l[1])"; Get-Process -Name $l[1] | ForEach-Object { [void]$_.CloseMainWindow() } }
            'maximizar' {
                Log "maximizar $($l[1])"
                Get-Process -Name $l[1] | Where-Object { $_.MainWindowHandle -ne 0 } |
                    ForEach-Object { [void][WinControl.Ventana]::ShowWindowAsync($_.MainWindowHandle, 3) }
            }
            'forzar' { Log "forzar $($l[1])"; Stop-Process -Name $l[1] -Force }
            'salir' { Salir }
        }
    }
}

function Vivos { @($script:nombres.Keys | Where-Object { Get-Process -Name $_ }) }

function Salir {
    # las apps que sigan abiertas se terminan antes: si alguna queda, Windows deja el logoff a
    # medias esperándola y la siguiente conexión se engancha en esa sesión
    foreach ($p in @($script:nombres.Keys)) { Stop-Process -Name $p -Force }
    if ($script:nombres.Count -gt 0) { Start-Sleep -Seconds 1 }
    Log 'logoff'
    # marca de hora para que win espere a que termine el logoff antes de volver a conectar
    Set-Content -LiteralPath (Join-Path $Dir 'fin.txt') -Value (Get-Date -Format o)
    Remove-Item -LiteralPath $estado -Force
    logoff
    exit
}

New-Item -ItemType Directory -Path $cola -Force | Out-Null

# host.lan (Samba del contenedor, tu carpeta personal) como intranet local: sin esto Windows lo trata
# como internet, Office abre los archivos en Vista protegida y bloquea las macros
$zona = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\host.lan'
New-Item -Path $zona -Force | Out-Null
Set-ItemProperty -Path $zona -Name 'file' -Value 1 -Type DWord
Set-ItemProperty -Path $zona -Name '*' -Value 1 -Type DWord
if (Test-Path -LiteralPath $ultimoPaso) {
    $previo = @('ultimo paso: ' + (Get-Content -LiteralPath $ultimoPaso -Raw))
    $previo += @(Get-Content -LiteralPath $localLog -Tail 15)
    Set-Content -LiteralPath (Join-Path $Dir 'agente-anterior.txt') -Encoding UTF8 -Value $previo
}
if ((Test-Path $localLog) -and (Get-Item $localLog).Length -gt 1MB) { Remove-Item $localLog }

# acceso directo en Inicio para el escritorio de `win presentar`: el Explorador lo ejecuta al
# iniciar un escritorio completo (las sesiones RemoteApp no lo ejecutan). Solo encuentra el
# agente si la sesión trae la unidad \\tsclient\win; si no, se rinde al minuto.
if (-not $Escritorio) {
    $acceso = Join-Path ([Environment]::GetFolderPath('Startup')) 'win-control escritorio.lnk'
    $orden = "for(`$i=0; `$i -lt 60; `$i++){ if(Test-Path '\\tsclient\win\agente.ps1'){ & '\\tsclient\win\agente.ps1' -Dir '\\tsclient\win' -Escritorio; break }; Start-Sleep 1 }"
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($acceso)
    $lnk.TargetPath = Join-Path $env:WINDIR 'System32\conhost.exe'
    $lnk.Arguments = "--headless powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$orden`""
    $lnk.WindowStyle = 7
    $lnk.Save()
}
Add-Type -Name Ventana -Namespace WinControl -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);'
Log $(if ($Escritorio) { 'inicio (escritorio)' } else { 'inicio' })
$vuelta = 0

while ($true) {
    $vuelta++
    if ($vuelta % 500 -eq 1) { Log "vuelta $vuelta" }
    try {
    Paso 'leer cola'
    Atender
    Paso 'listar procesos'
    $vivos = Vivos
    Paso 'escribir abiertas.txt'
    # apps abiertas ("PROCESO|nombre") y títulos de sus ventanas ("v|título"), para saber cuándo aparecen
    $lineas = @($vivos | ForEach-Object { '{0}|{1}' -f $_, $nombres[$_] })
    if ($vivos.Count -gt 0) {
        $lineas += @(Get-Process -Name $vivos | Where-Object { $_.MainWindowTitle } |
                     ForEach-Object { 'v|' + $_.MainWindowTitle })
    }
    Set-Content -LiteralPath $estado -Encoding UTF8 -Value $lineas
    $ahora = Get-Date

    if ($vivos.Count -gt 0) { $vacioDesde = $null } elseif (-not $vacioDesde) { $vacioDesde = $ahora }
    Paso 'consultar sesion (qwinsta)'
    $sesion = (qwinsta | Select-String '^>') -join ''
    Paso 'esperar'
    if ($sesion -match 'Desc|Disc') {
        if (-not $cortadoDesde) { $cortadoDesde = $ahora }
    } else {
        $cortadoDesde = $null
    }

    # en el escritorio la sesión la cierra el usuario: el agente solo atiende pedidos
    if ($Escritorio) { Start-Sleep -Milliseconds 700; continue }
    if ($cortadoDesde -and ($ahora - $cortadoDesde).TotalSeconds -ge $GRACIA_CORTE) { Salir }
    if ($vacioDesde -and ($ahora - $vacioDesde).TotalSeconds -ge $GRACIA_VACIO -and
        ($ahora - $inicio).TotalSeconds -ge $GRACIA_INICIO) {
        Atender
        if ((Vivos).Count -eq 0) { Salir }
        $vacioDesde = $null
    }
    } catch { Log ('error: ' + $_) }
    Start-Sleep -Milliseconds 700
}
