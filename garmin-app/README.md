# DriftGuard — Milestone 2

Edge 1050 Connect IQ Data Field based on the installed Garmin SDK templates.
Displays current power, HR, instantaneous power / HR, and a local quality-aware
aerobic-decoupling result. No settings UI, stored ride history, permissions, or
network access.

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

See Layouts below for the field sizes. Use the simulator's Simulation menu
to supply activity/FIT data and check changing readings and sensor dropout.

## Data policy and verification

`compute(Activity.Info)` reads currentPower, currentHeartRate, timerTime and
timerState on every sample. Missing/negative power displays `--`; zero power is
displayed. Missing/zero/negative HR displays `--` and disables the ratio. Missing readings immediately replace
previous text. The ratio uses floating-point division and two decimal places.
Garmin documents both inputs as nullable integers:
[Activity.Info](https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html),
[DataField.compute](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html).

2026-09-24: Edge 1050 simulator tests passed (11 passed, 0 failed, 0 errors).
The runner returns exit code 1 despite its passing summary; rely on the summary.
Test functions are excluded from normal builds.

The simulator loaded Edge 1050 (6.0.0). Automated visual inspection was blocked
by Windows capture error `SetIsBorderRequired: 0x80004002` and unavailable input
geometry. Live activity playback and layout appearance still need manual review.
Physical-device checks remain for sensor-disconnection timing (the app can clear
only values Garmin reports as missing), activity lifecycle, and readability.

## Aerobic decoupling

`DriftEngine` owns the Milestone 2 calculation; `DriftGuardView` only passes it
activity data and renders its state. The default warm-up is 15 minutes and can
be changed only in code by passing milliseconds to `new DriftEngine(warmupMs)`.
There is deliberately no settings UI yet.

Warm-up is measured in timer time, so pauses do not count. Samples with a stopped
timer are ignored. While the timer runs, a sample is valid when power and HR are
positive; missing readings and coasting (zero power) are invalid. Speed is not
used. A period is 30 minutes of valid samples split into two 15-minute halves.
Each half's efficiency is average power divided by average HR, and drift is the
percentage decrease from the first half to the second.

A period is rejected (`NOT STEADY`) when more than 20% of its samples are invalid
or when the coefficient of variation of its 30-second power averages exceeds 15%;
collection then starts over. The first accepted period is the ride's result and
stays on screen until the activity is saved or discarded (`onTimerReset`).

## Layouts

- Full page (height ≥ 500 px): AEROBIC DRIFT label, large drift value with a
  colored STABLE / WATCH / HIGH DRIFT pill (or state and progress bar before a
  result), Pw:HR trend chart, and power / heart-rate zone gauges.

Power is a 3-second average (1 s power is too jumpy for zones); a dropout clears
it and restarts the average. The Pw:HR number is the last full minute, because
instantaneous power / HR is noise (HR lags power by tens of seconds).

Zone gauges use the rider's own zones from the Garmin user profile
(`UserProfile.getHeartRateZones2` / `getPowerZones` for cycling, API 5.2.2+, with
`getHeartRateZones` and FTP-based Coggan zones as fallbacks). This needs the
`UserProfile` permission. Every zone gets the same width; the current zone is
drawn thicker with a marker at the value. Without valid zones the gauge shows
NO ZONES. Zones reload on `onTimerReset`.

The trend chart plots Pw:HR per minute of running timer for the last 60 minutes
(`EfficiencyHistory`, a fixed 60-point ring buffer). A minute with under 30 s of
valid data is a gap. Once a result exists, a dashed line marks the first-half
baseline and the line takes the STABLE / WATCH / HIGH DRIFT color. The vertical
scale spans at least 0.2 so minute-to-minute noise does not look like drift.
- Medium field (150–499 px): drift value or progress, one power / HR / Pw:HR line.
- Small field (< 150 px): value or progress minutes and a colored state word.

Colors follow the field background (light or dark).
