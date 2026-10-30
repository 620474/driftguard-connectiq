param([string]$Command='run',[switch]$Offline,[switch]$Suite,[string]$ImportDir,[int]$Months=6)
$ErrorActionPreference='Stop'
if ($Command -eq 'auth') {
    $secretDirectory=Join-Path $PSScriptRoot '.data'
    New-Item -ItemType Directory -Force $secretDirectory | Out-Null
    $key=Read-Host 'Garmin Personal API key (hidden input)' -AsSecureString
    $key | Export-Clixml -LiteralPath (Join-Path $secretDirectory 'garmin-key.xml')
    Write-Host 'Saved with Windows DPAPI for this Windows user. Run lab.ps1 run -Suite'
    exit 0
}
$python=Join-Path $PSScriptRoot '.venv/Scripts/python.exe'
if (!(Test-Path -LiteralPath $python)) {
    & python -c "import sys; assert sys.version_info >= (3,12), 'Python 3.12+ required'"
    if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.12+ (64 bit)' }
    & python -m venv (Join-Path $PSScriptRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
    & $python -m pip install -e $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw 'dependency installation failed' }
}
if ($Command -eq 'research') {
    foreach ($scriptName in @('research.py','device_alignment.py','render_research.py')) {
        & $python (Join-Path $PSScriptRoot $scriptName)
        if ($LASTEXITCODE -ne 0) { throw "Research step failed: $scriptName" }
    }
    exit 0
}
$argsList=@('-m','driftlab.cli',$Command,'--months', [string]$Months)
if ($Offline) { $argsList+='--offline' }
if ($Suite) { $argsList+='--suite' }
if ($ImportDir) { $argsList+=@('--import-dir',$ImportDir) }
& $python @argsList
if ($LASTEXITCODE -ne 0) { throw "Lab exited with code $LASTEXITCODE" }
