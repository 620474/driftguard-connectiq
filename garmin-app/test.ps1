param(
    [Parameter(Mandatory=$true)][string]$Sdk,
    [Parameter(Mandatory=$true)][string]$Key,
    [string]$Java = 'java',
    [string]$Output = (Join-Path $PSScriptRoot 'bin/tests'),
    [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Output | Out-Null
$Output = (Resolve-Path -LiteralPath $Output).Path
$jar = Join-Path $Sdk 'bin/monkeybrains.jar'

foreach ($variant in @('production', 'calibration')) {
    $jungle = if ($variant -eq 'production') { 'monkey.jungle' } else { 'calibration.jungle' }
    $binary = Join-Path $Output "$variant.prg"
    & $Java '-Dfile.encoding=UTF-8' -jar $jar -f (Join-Path $PSScriptRoot $jungle) -d edge1050 -o $binary -y $Key -w -l 3 -t
    if ($LASTEXITCODE -ne 0) { throw "$variant test compilation failed" }

    $passed = $false
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $sim = $null
        $process = $null
        $stdout = $null
        $stderr = $null
        $timedOut = $false
        $logFile = Join-Path $Output "$variant.attempt-$attempt.log"
        $log = ''
        try {
            Write-Host "Starting $variant simulator attempt $attempt/2 (timeout $TimeoutSeconds seconds)"
            $sim = Start-Process -FilePath (Join-Path $Sdk 'bin/simulator.exe') -WorkingDirectory (Join-Path $Sdk 'bin') -WindowStyle Hidden -PassThru
            Start-Sleep -Seconds 6
            if ($sim.HasExited) { throw "$variant simulator exited before test launch" }
            $info = [Diagnostics.ProcessStartInfo]::new()
            $info.FileName = $Java
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            foreach ($argument in @('-classpath',$jar,'com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux',
                    '-f',$binary,'-d','edge1050','-s',(Join-Path $Sdk 'bin/shell.exe'),'-t')) {
                $info.ArgumentList.Add($argument)
            }
            $process = [Diagnostics.Process]::Start($info)
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
            if ($timedOut) {
                Write-Warning "$variant attempt $attempt timed out; terminating test runner"
                $process.Kill($true)
                $process.WaitForExit(10000) | Out-Null
            }
            $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
            [IO.File]::WriteAllText($logFile, $log)
            if ($log.Length -gt 0) {
                Write-Host "===== $variant attempt $attempt log (last 120 lines) ====="
                $lines = $log -split "\r?\n"
                $lines | Select-Object -Last 120 | ForEach-Object { Write-Host $_ }
            } else {
                Write-Warning "$variant attempt $attempt emitted no test output"
            }
            if ($timedOut) {
                if ($attempt -eq 2) { throw "$variant simulator timed out twice; release blocked (see $logFile)" }
                continue
            }
            # Never retry or ignore a real test failure.
            if ($log -notmatch 'PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)' -or $log -match 'FAILED \(') {
                throw "$variant tests did not pass; release blocked (see $logFile)"
            }
            [IO.File]::WriteAllText((Join-Path $Output "$variant.log"), $log)
            $passed = $true
            break
        } finally {
            if ($null -ne $process -and -not $process.HasExited) {
                $process.Kill($true)
            }
            if ($null -ne $sim -and -not $sim.HasExited) {
                Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    if (-not $passed) { throw "$variant tests did not complete; release blocked" }
}
