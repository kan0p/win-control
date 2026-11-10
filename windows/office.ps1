# office.ps1 - instala o ajusta Microsoft 365 con la Office Deployment Tool oficial
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
#   -Apps: apps de Office a dejar instaladas, separadas por espacio (Word Excel PowerPoint ...)
#   -Producto: O365BusinessRetail (Microsoft 365 Apps para empresas) u O365ProPlusRetail (E3/E5/A3/A5)
#   -Marca: archivo donde se escribe el resultado ("ok" o "error: ...") al terminar
#   -Elevar: pide permisos de administrador (desde una sesión normal; en la instalación ya los tiene)
param(
    [string]$Apps = 'Word Excel PowerPoint',
    [string]$Producto = 'O365BusinessRetail',
    [string]$Marca = '',
    [switch]$Elevar
)

$ErrorActionPreference = 'Stop'
$todas = 'Word', 'Excel', 'PowerPoint', 'Outlook', 'OneNote', 'Access', 'Publisher',
         'Teams', 'Lync', 'Groove', 'OneDrive', 'Bing'
$incluir = $Apps -split '\s+' | Where-Object { $_ }
$carpeta = 'C:\OfficeInstall'

function Marcar([string]$t) {
    if ($Marca) { Set-Content -LiteralPath $Marca -Encoding UTF8 -Value $t }
}

try {
    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    $excluir = ($todas | Where-Object { $incluir -notcontains $_ } |
                ForEach-Object { "      <ExcludeApp ID=`"$_`" />" }) -join "`r`n"
    $xml = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="$Producto">
      <Language ID="MatchOS" Fallback="es-es" />
$excluir
    </Product>
  </Add>
  <Updates Enabled="TRUE" Channel="Current" />
  <RemoveMSI />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
    Set-Content -LiteralPath "$carpeta\office.xml" -Encoding UTF8 -Value $xml
    $setup = "$carpeta\setup.exe"
    if (-not (Test-Path $setup)) {
        & curl.exe -L --fail --retry 3 -o $setup 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
        if ($LASTEXITCODE -ne 0) { throw 'no se pudo descargar la Office Deployment Tool' }
    }
    $argumentos = @{ FilePath = $setup; ArgumentList = '/configure office.xml'
                     WorkingDirectory = $carpeta; Wait = $true; PassThru = $true }
    if ($Elevar) { $argumentos.Verb = 'RunAs' }
    $p = Start-Process @argumentos
    if ($p.ExitCode -ne 0) { throw "la instalación de Office terminó con el código $($p.ExitCode)" }
    Marcar 'ok'
} catch {
    Marcar ('error: ' + $_)
    exit 1
}
