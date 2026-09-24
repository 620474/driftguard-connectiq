# DriftGuard — Milestone 1

Edge 1050 Connect IQ Data Field based on the installed Garmin SDK templates.
Displays current power, HR, and instantaneous power / HR. No aerobic decoupling,
settings, stored history, permissions, or network access.

## Windows build

Requires Garmin SDK Manager's selected SDK, the Edge 1050 profile, and Java.
Verified with SDK 9.2.0 and JetBrains Java 25. Use PowerShell 7 in this directory.
Create a local signing key once (ignored by Git):

```powershell
if (!(Test-Path developer_key.der)) {
    $rsa = [System.Security.Cryptography.RSA]::Create(4096)
    [System.IO.File]::WriteAllBytes("$PWD/developer_key.der", $rsa.ExportPkcs8PrivateKey())
    $rsa.Dispose()
}
./build.ps1
```

If Java is not on PATH, pass its installed executable:

```powershell
./build.ps1 -Java 'C:\Program Files\JetBrains\WebStorm 2026.2.3\jbr\bin\java.exe'
./build.ps1 -Java 'C:\Program Files\JetBrains\WebStorm 2026.2.3\jbr\bin\java.exe' -Test
```

The compiler uses `-f monkey.jungle -d edge1050 -o bin/DriftGuard.prg
-y developer_key.der -w -l 3`. `-Test` adds `-t` and writes
`bin/DriftGuard-tests.prg`. SDK initialization needs write access to its directory.
Keep the signing key private; keys and build outputs are excluded from Git.

## Simulator

Open the selected SDK's `bin/simulator.exe`, then run the following with Java
on PATH (or replace `java` with an explicit executable):

```powershell
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg" -Raw).Trim()
java -classpath "$sdk\bin\monkeybrains.jar" com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f bin/DriftGuard.prg -d edge1050 -s "$sdk\bin\shell.exe"
# After building with -Test:
java -classpath "$sdk\bin\monkeybrains.jar" com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f bin/DriftGuard-tests.prg -d edge1050 -s "$sdk\bin\shell.exe" -t
```

This is the entry point used by Garmin's `monkeydo.bat`. A normal run remains
attached until the field exits. Reload the normal PRG after running tests.

Use a full-size field for the stacked DRIFTGUARD / POWER / HR / PW:HR layout.
Shorter fields use three compact rows. Use the simulator's Simulation menu
to supply activity/FIT data and check changing readings and sensor dropout.

## Data policy and verification

`compute(Activity.Info)` reads currentPower and currentHeartRate on every sample.
Missing/negative power displays `--`; zero power is valid. Missing/zero/negative
HR displays `--` and disables the ratio. Missing readings immediately replace
previous text. The ratio uses floating-point division and two decimal places.
Garmin documents both inputs as nullable integers:
[Activity.Info](https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html),
[DataField.compute](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html).

2026-09-24: Edge 1050 simulator tests passed (2 passed, 0 failed, 0 errors),
using actual Activity.Info objects: 247 W / 151 bpm = 1.64, zero power, zero HR,
missing sensors after valid data, and negative readings. The runner returned
exit code 1 despite its passing summary; retain the summary when diagnosing it.
Test functions are excluded from normal builds.

The simulator loaded Edge 1050 (6.0.0). Automated visual inspection was blocked
by Windows capture error `SetIsBorderRequired: 0x80004002` and unavailable input
geometry. Live activity playback and layout appearance still need manual review.
Physical-device checks remain for sensor-disconnection timing (the app can clear
only values Garmin reports as missing), activity lifecycle, and readability.
