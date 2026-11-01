# Release CI: actual simulator tests

The Windows hosted runner supports the Garmin simulator. The compiler-only
profile used previously is insufficient: it lacks simulator resources and fonts.
Removing the test call in 5b49693 hid the failure. Provisioning the complete
Edge 1050 device directory and its WW fonts lets the production suite execute
on the same hosted runner; Linux/Xvfb or an interactive runner is unnecessary.

## Required gates

Release runs the Python suite, then `ci-release.ps1` installs SDK 9.2.0 and the
private simulator runtime. `test.ps1` compiles and executes **both** production
and calibration suites before the signed production build and semantic-release.
Missing credentials/runtime, bad checksums, missing WW fonts, compiler failures,
empty output, timeouts, FAILED reports and missing positive PASSED summaries
block publication. MonkeyDoDeux's process status is not a reliable replacement
for its test protocol: even a completed passing suite can produce a nonzero
status with SDK 9.2.0.

Each simulator attempt is bounded to 90 seconds in release CI; only a timeout
gets one retry. A real test failure is never retried. The runner terminates its
own simulator/test processes and retains test and simulator stdout/stderr logs
as a seven-day Actions artifact. Only `.log` files are uploaded: no device bits,
fonts, signing keys or test binaries. Only main can publish a release; a manual
workflow dispatch on a feature branch validates the same gates without publishing.

## Private simulator provisioning

The job uses the `garmin-simulator-ww` GitHub Environment. It has no deployment
approval requirement. Environment secrets avoid the combined size limit on
repository/organization secrets. The original production signing key and minimal
compiler secrets remain repository secrets.

The runtime ZIP contains the unmodified SDK Manager-installed
`Devices/edge1050/` directory and these installed `Fonts/` files:

- `DejaVuSans_Cd_SemiBold_WGL4.ttf`
- `Garmin_Roboto_Bold.ttf`
- `Roboto-Medium.ttf`

This validates the WW/English profile used by the app and tests. Other simulator
font sets are not claimed as covered. No Garmin login credentials are required
by the workflow. Device resources/fonts are never committed, cached publicly,
or attached to releases.

For rotation, create a ZIP with paths relative to the Garmin ConnectIQ data
directory. Base64-encode the complete ZIP and split the string into consecutive
32,000-character chunks. Store them as environment secrets
`GARMIN_SIMULATOR_01` through `GARMIN_SIMULATOR_40` (the current bundle uses 40).
The workflow explicitly maps these secrets; extend that mapping if the bundle
grows. The installer accepts up to 48 chunks and refuses missing ones.
Store `GARMIN_SIMULATOR_MANIFEST` as JSON:

```json
{"chunks":40,"sha256":"<SHA-256 of ZIP bytes>","device":"edge1050","font_set":"ww"}
```

Upload through GitHub's environment-secret API with its public-key encryption
or a trusted secret-management client. Do not print values or pass them as shell
arguments. After rotation, manually dispatch Release on a feature branch and
verify both positive test summaries before promoting it to main.

## Verified execution

[Hosted run 41339749884](https://github.com/620474/driftguard-connectiq/actions/runs/41339749884)
on 2026-11-01 passed 110 Python tests, 54 production Monkey C tests and 57
calibration tests, then built the signed production PRG. Both simulator suites
passed on their first attempt. Publishing was deliberately skipped on the test
branch. Physical-device behavior is a separate validation.
