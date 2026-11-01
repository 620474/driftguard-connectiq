Current algorithm version: 2. In addition to the historical algorithm below,
steady requires within-minute positive-power CV <=30%, valid sensor ranges,
and rejection of the first resumed minute plus three recovery minutes.
See [v2 contract](../docs/RELIABILITY_V2_RU.md) for exact FIT and timer semantics.

# Source audit / algorithm contract

Source revision: 7d6b5c1123e208ef64e4911a662392cfdf0a9810. Read AGENTS.md, CLAUDE.md, all docs/*.md and requested source/test files. User explicitly authorizes separate lab beyond older CURRENT_TASK scope; production remains untouched.

1. View passes instantaneous currentPower, positive HR, timer ON. Display 3-second power average does not feed the engine. Paused seconds are ignored, including minute phase.
2. Engine consumes 60 running calls per committed minute. Incomplete trailing minute is not committed. Positive power AND HR define valid second. Warmup first 15 completed minutes, transition to COLLECTING exactly at 15.
3. Eligible post-warmup minute has >=48 valid seconds. Integer average power is added to global histogram BEFORE classification, even when out of band or in recovery. Histogram 150 bins, 10 W each, clipped at 149. Lower median rank (count+1)//2, bin centre i*10+5.
4. Integer mean within inclusive +/-20% of reference is in band. Insufficient data or out-of-band resets recovery to 3. In-band minute with recovery>0 decrements it and is rejected. Otherwise accepted. Three consecutive in-band minutes are excluded after an unstable minute.
5. Steady minutes retain sum power, sum HR, valid seconds. EF = sum power/sum HR. RIDE includes post-warmup zero-second records for rejected minutes to preserve bucket timing. LAST60 history includes all minutes but zero steady-seconds for rejected/warmup.
6. Halves split by valid steady seconds. A crossing record is apportioned proportionally, assuming constant composition within record. Drift = (EF1-EF2)/EF1*100. Return [drift,EF1,(P2/P1-1)*100]. Null if first power or either HR sum <=0.
7. RIDE NOT_STEADY takes precedence after >=40 post-warmup minutes if accepted minute fraction <70%. Otherwise COLLECTING until 40 accepted minutes (not 2400 seconds). LAST60 COLLECTING until 60 post-warmup minutes; then NOT_STEADY if fewer than 48 accepted in latest 60. A result exceeding +/-5% power change becomes POWER_CHANGED; otherwise VALID. Invalid states hide drift and clear label.
8. Labels: negative below -3, stable below 5, watch below 10, high >=10. Hysteresis +/-0.5 percentage point follows source ordering and strict/inclusive comparisons.
9. Buckets capacity 240 even records. At full buffer pairwise merge, double width, open a new bucket. Sums preserved; half split resolution worsens. Compaction can change the drift, despite some optimistic older acceptance text. Python reproduces this approximation rather than replacing it with exact minute history.
10. Compatibility begins at activity start, includes every running second with positive HR; absent/nonpositive power contributes zero, NOT a missing second. Complete minutes only. Split by HR-present seconds through compressed buckets, not true elapsed-time halves when HR is missing. Thus actual implementation differs from its short 'halves by time' comment.
11. Recorder stores last completed minute EF only if >=30 valid seconds; steady flag; ride state codes 0..4. Drift fields are only updated while valid: stale recorded numbers require matching VALID state. Session coverage integer percentage. Cadence average uses positive pedalling seconds, clips at 255. Developer fields retain their raw FIT semantics and are exported, not treated as independent ground truth.

Oracle uses Python float64; Monkey C Float is float32. Integer division is reproduced for positive sums/median. Bit-for-bit Float and 32-bit accumulator overflow are not emulated. Relevant existing Monkey C test vectors are ported, not executed through the SDK here. Production simulator build needs SDK and signing key; no build/simulator claim is made by this lab.
