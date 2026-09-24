# DriftGuard — Milestone 4

Edge 1050 Connect IQ Data Field: live aerobic decoupling (Pw:HR drift) for the
whole ride and the last hour, a per-minute Pw:HR chart, and power / HR zone
gauges. Fully local: no settings UI, no network. Uses the `UserProfile`
permission to read the rider's zones and `FitContributor` to record its values.

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
The test runner returns exit code 1 despite a passing summary; rely on the
summary. Clicking the simulated screen delivers `onTap`.

## Sideloading

Connect the Edge by USB, copy `bin/DriftGuard.prg` to `Garmin\Apps` on the
device, disconnect, then add the Connect IQ field to a data screen.

## Readings

`compute(Activity.Info)` reads currentPower, currentHeartRate and timerState
every second. Missing readings immediately replace previous text with `--`.

- Power is a 3-second average (1 s power is too jumpy for zones); a dropout
  clears it and restarts the average. Zero power is a real reading.
- HR of zero or less is treated as missing.
- The Pw:HR number is the last full minute, because instantaneous power / HR is
  noise (HR lags power by tens of seconds).

## Aerobic decoupling

The calculation contract is in `docs/CURRENT_TASK.md`. In short:

- `DriftEngine` collects one-minute records of running timer (pauses are
  skipped) and decides for each post-warm-up minute whether it is **steady**:
  ≥ 48 valid seconds, power within ±20% of the ride's median minute, and not in
  the 3-minute HR recovery after a non-steady minute.
- **RIDE** drift uses every steady minute of the ride (`RideBuckets`, 240
  buckets merged pairwise when full, so memory is constant for any duration).
- **LAST 60** uses the steady minutes of the last hour (`EfficiencyHistory`,
  a 60-minute ring that also feeds the chart).
- Both split their steady time into halves and compare average power / average
  HR (`DriftMath.halves`), the same definition Intervals.icu uses.
- If the halves differ by more than 5% in average power, the metric shows
  POWER CHANGED instead of a percentage: a change of effort alone moves Pw:HR.
- Labels use 0.5 percentage points of hysteresis; drift below -3% is labelled
  NEGATIVE in a neutral color.
- Everything is recomputed once per minute; the per-second work is a few adds.

The warm-up (default 15 minutes) can be changed only in code:
`new DriftEngine(warmupMinutes)`. All thresholds are heuristics to be
calibrated on real ride files.

## Layouts

Tap anywhere on the field to switch the main metric between RIDE and LAST 60.
The choice is kept in `Application.Storage`. Nothing depends on the tap: the
other metric is always shown too. If the selected metric has given up on the
ride (POWER CHANGED, NOT STEADY) while the other has a value, the other is shown
large instead and the selected tab gets an orange outline.

- Full page (height ≥ 500 px): RIDE / LAST 60 tabs; large drift with a
  STABLE / WATCH / HIGH DRIFT pill (or state, progress bar and what is missing);
  the other metric and STEADY TIME; the Pw:HR chart; power and HR zone gauges.
- Medium field (150–499 px): selected metric, then the other metric and steady time.
- Small field (< 150 px): value or progress and the metric with its state.

The chart plots Pw:HR per minute for the last 60 minutes. Steady minutes are
drawn in the metric's color, other minutes muted, and minutes with under 30 s
of valid data are gaps. The dashed line is the selected metric's first-half
baseline. The vertical scale follows the steady minutes and spans at least 0.2,
so warm-up, climbs and minute-to-minute noise do not dominate it.

Zone gauges use the rider's own zones from the Garmin user profile
(`UserProfile.getHeartRateZones2` / `getPowerZones` for cycling, API 5.2.2+, with
`getHeartRateZones` and FTP-based Coggan zones as fallbacks). Every zone gets the
same width; the current zone is drawn thicker with a marker at the value.
Without valid zones the gauge shows NO ZONES. Zones reload on `onTimerReset`.

Colors follow the field background (light or dark).

## FIT recording

`DriftRecorder` writes developer fields once per minute (contract in
`docs/CURRENT_TASK.md`): minute EF, steady flag, RIDE drift and state, pedalling
cadence, and session values including `dg_compat_drift`, an Intervals.icu-style
decoupling of the whole activity for checking the arithmetic. Garmin Connect
graphs developer fields only for Store apps; a sideloaded build still writes them
to the FIT file. The unit tests construct the view with `recordFit = false`
because FIT fields can only be created by a field running in an activity.

## Verification

2026-09-25: 21 Edge 1050 simulator tests pass. The POWER CHANGED fallback, both metrics and
the tap toggle were checked by screenshot with a synthetic ride; the field ran in
the simulator with FIT recording enabled. Still to verify on a physical Edge:
sensor-dropout timing, auto-pause, onTap, readability, the FIT fields in
Intervals.icu, and the thresholds on real ride files.