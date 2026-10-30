# Build production only; tests, calibration, debug files and keys are not published.
$ErrorActionPreference = 'Stop'
$Sdk = Join-Path $env:RUNNER_TOOL_CACHE 'garmin-sdk-9.2.0'
$keyPath = Join-Path $env:RUNNER_TEMP 'driftguard-signing.der'
$profileZip = Join-Path $env:RUNNER_TEMP 'edge1050-profile.zip'
try {
    foreach ($name in @('GARMIN_SIGNING_KEY_BASE64','GARMIN_EDGE1050_PROFILE_1','GARMIN_EDGE1050_PROFILE_2')) {
        if (![Environment]::GetEnvironmentVariable($name)) { throw "Missing release secret: $name" }
    }
    if (!(Test-Path (Join-Path $Sdk 'bin/monkeybrains.jar'))) {
        $archive = Join-Path $env:RUNNER_TEMP 'garmin-sdk.zip'
        Invoke-WebRequest 'https://developer.garmin.com/downloads/connect-iq/sdks/connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2.zip' -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $Sdk -Force
    }
    [IO.File]::WriteAllBytes($keyPath,[Convert]::FromBase64String($env:GARMIN_SIGNING_KEY_BASE64))
    $profile = $env:GARMIN_EDGE1050_PROFILE_1 + $env:GARMIN_EDGE1050_PROFILE_2
    [IO.File]::WriteAllBytes($profileZip,[Convert]::FromBase64String($profile))
    Expand-Archive -LiteralPath $profileZip -DestinationPath (Join-Path $env:APPDATA 'Garmin/ConnectIQ') -Force
    & "$PSScriptRoot/build.ps1" -Sdk $Sdk -Key $keyPath
    if ($LASTEXITCODE -ne 0) { throw 'Production compiler failed' }
    $binary = Join-Path $PSScriptRoot 'bin/DriftGuard.prg'
    if (!(Test-Path $binary) -or (Get-Item $binary).Length -eq 0) { throw 'Release binary is absent' }
    $hash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'bin/SHA256SUMS.txt'),"$hash  DriftGuard.prg`n",[Text.UTF8Encoding]::new($false))
} finally {
    foreach ($file in @($keyPath,$profileZip)) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    }
}
