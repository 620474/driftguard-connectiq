param(
    [string]$Java = 'java',
    [string]$Sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg" -Raw).Trim(),
    [string]$Key = "$PSScriptRoot\developer_key.der",
    [switch]$Test,
    [switch]$Calibration
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (!(Test-Path -LiteralPath $Key)) {
        throw "Signing key missing: $Key. See README.md for local key creation."
    }
    New-Item -ItemType Directory -Force bin | Out-Null
    $jungle = if ($Calibration) { 'calibration.jungle' } else { 'monkey.jungle' }
    $output = if ($Test) { 'bin/DriftGuard-tests.prg' } else { 'bin/DriftGuard.prg' }
    if ($Calibration) { $output = if ($Test) { 'bin/DriftGuard-calibration-tests.prg' } else { 'bin/DriftGuard-calibration.prg' } }
    $compilerArgs = @('-Dfile.encoding=UTF-8', '-jar', "$Sdk\bin\monkeybrains.jar",
        '-f', $jungle, '-d', 'edge1050', '-o', $output, '-y', $Key, '-w', '-l', '3')
    if ($Test) { $compilerArgs += '-t' }
    & $Java @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "Garmin build failed ($LASTEXITCODE)." }
} finally {
    Pop-Location
}
