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
$sim = Start-Process -FilePath (Join-Path $Sdk 'bin/simulator.exe') -WorkingDirectory (Join-Path $Sdk 'bin') -WindowStyle Hidden -PassThru
try {

    # The UI thread is ready before the simulator command socket is listening.
    Start-Sleep -Seconds 3
    foreach ($variant in @('production','calibration')) {
        $jungle = if ($variant -eq 'production') {'monkey.jungle'} else {'calibration.jungle'}
        $binary = Join-Path $Output "$variant.prg"
        & $Java '-Dfile.encoding=UTF-8' -jar $jar -f (Join-Path $PSScriptRoot $jungle) -d edge1050 -o $binary -y $Key -w -l 3 -t
        if ($LASTEXITCODE -ne 0) { throw "$variant test compilation failed" }
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
        if (!$process.WaitForExit($TimeoutSeconds*1000)) {
            $process.Kill($true)
            throw "$variant simulator timed out; release blocked"
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $Output "$variant.log"),$log)
        Write-Output $log
        # MonkeyDoDeux exit codes vary by SDK; require a complete positive summary.
        if ($log -notmatch 'PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)' -or $log -match 'FAILED \(') {
            throw "$variant tests did not pass; release blocked"
        }
    }
} finally {
    if (!$sim.HasExited) { Stop-Process -Id $sim.Id -ErrorAction SilentlyContinue }
}
