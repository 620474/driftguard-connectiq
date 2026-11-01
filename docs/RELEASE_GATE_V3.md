Current hosted release gate and provisioning: [RELEASE_CI.md](RELEASE_CI.md).
Both simulator suites were executed successfully in hosted run 41339749884.
Historical implementation notes follow.

# Release gate, HRR boundary and experimental CV — v3

Follow-up to ceeabae8a903e4db571d85a2901a823f4eb3a24d, authorized by owner.
No push or release. Historical v2 results remain in RELIABILITY_V2_RU.md.

## Release gate

Python unittest discovery runs for PRs and main. The release workflow independently
runs the same Python gate before accessing release credentials. After SDK/profile
installation, ci-release.ps1 calls test.ps1 before building/publishing production.
test.ps1 compiles and runs both production and calibration suites, requiring a
complete PASSED summary with nonzero pass count, zero failures and zero errors.
An empty log, crash, compilation failure or timeout blocks publication. Simulator
exit code alone is insufficient for this SDK. Logs are retained under bin/tests.
Garmin tests require the provisioned device profile and signing key; PR Python
checks do not use secrets. A hosted GitHub run is still required to confirm that
its desktop/simulator environment supports the same gate; it fails closed if not.

Local command: ./garmin-app/test.ps1 -Sdk <sdk-dir> -Key <der-file> -Java <java.exe>
The script starts a hidden simulator and bounds each runner to 300 seconds.

## Exact 60-second boundary

If a genuine explicit segment boundary arrives with recovery at sample 59,
retain a bounded copy for the next compute. That copy receives exactly one sample
and publishes the previous parent's result. The new segment starts immediately;
no sample is invented, repeated, or moved between interval segments. If compute
arrives first, its completed HRR is published before the callback starts recovery
for the next segment. Invalid sensors/power or pause can still invalidate recovery.
Earlier boundaries cancel the unfinished recovery as before. Activity reset or
workout restart clears the pending copy. This is event-order determinism for the
same input samples; real device callback timing remains a hardware check.

## Production FIT schema 3

HRR now has an independent held parent channel, dg_hrr_parent (ID19, uint16), replacing the old dg_rep_evt byte.
Changes to dg_rep_id describe effort completions; completion N+1 no longer clears HRR
for N. HRR values and dg_rep_recovery_w refer to dg_hrr_parent, not dg_rep_id.
The decoder attaches that channel after collecting starts, including sparse FIT
records where the two become visible together. Unknown parents are reported.
Schemas 1/2 retain their old event semantics in the decoder.

To retain the budget, dg_rep_end_s (ID30) becomes uint16, capped at 65534;
quality bit 8 now means duration OR end-clock clipping. It counts observed running
callbacks since reset, not device timer time if the field loaded late.
Production uses 31 B RECORD / 23 B SESSION, calibration 32 / 24.
Calibration algorithm version=3, config CRC32=1914809483; schema/config changes
must be checked before comparing files. No original FIT has been rewritten.

## CV experiment

The 30% intra-minute CV gate is OFF by default in both builds and the Python
oracle. Monkey C experiments explicitly set engine.experimentalCV=true;
Python experiments use Config(power_cv=.30). This is a lab/developer opt-in,
not a public on-device setting. There is no physiological validation of 30%.
Standard calibration uses CV off; a custom experimental build must use a distinct
version/config identity before exporting calibration data. Resume recovery and
sensor-range checks remain enabled.

123-FIT offline replay with default CV off: 2029 steady minutes; final VALID
RIDE=6 and LAST60=1, versus 0/0 in v2 and 8/5 at original main. AUTO remains
1547 completed candidates, including 42 sustained and 10 partial. These counts
are not accuracy measurements; recorded values of old apps remain separate.

Tests cover callback-before-compute and compute-before-callback, parent attachment
when HRR appears alongside the next rep, the default CV bypass and explicit strict
CV rejection. Physical Edge and a new physical FIT round trip remain outstanding.

## Verification

Local SDK 9.3.0 test.ps1 gate: production 54/54 and calibration 57/57 PASS.
Python 92/92 PASS; both ordinary builds compile at type-check level 3.
Normal-app diagnostic wrapper confirms FIT runtime, reset and effort/HRR writes
remain enabled. Production RECORD uses 16 fields / 31 bytes. An earlier candidate
with 17 RECORD fields crashed the native simulator before test output; the field
allocation regression now enforces this tested count in addition to byte budgets.
This observation is not a claim of a universal hardware field-count limit.
The [Garmin API budget](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html)
specifies 32 bytes per message for Data Fields.
Hosted Actions and physical Edge validation remain outstanding.
