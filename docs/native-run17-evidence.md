# Run 17 retained native evidence

October 8, 2026, 06:58 ET. Reviewed revision
`47b406b8300e33cb33533fc8c4e176d91c610076`,
[run 37764499138](https://github.com/mmoore950/powerlifting-app/actions/runs/37764499138),
job113268703648: completed **failure**. The later two-window source is absent
from this revision; this run required62 iOS methods.

## Actual outcomes

- Eleven POSIX supervisor methods passed in10.919s, including persistent/final
  diagnostic-write failure regressions;24 orchestration methods passed10.364s.
- macOS core42passed/1 opt-in HTTP skipped in1.545s; independent actual
  Swift-to-Node HTTP method passed in1.131s. These are separate inventories.
- Prepare created/validated owned fresh UI device
  `5BF998D6-1F0E-4F2A-BE29-E3B0479899B5`; selected preexisting destination
  `841E0288-2704-4A18-A304-BF477CA384A8` remained the compile/non-UI destination.
- Build phase0 in376.179s/shared440s: compile72.272s; fresh boot5.403s;
  bootstatus242.637s; matching available Booted inventory31.589s. Every command
  receipt finished with direct wait/group absence/cleanup verified. This proves
  this execution succeeded, not a general startup-contention cause or cure.
- UI phase0 in380.280s: exactly the existing one smoke method passed. Its five
  screenshot exports were not executed because the later phase failed.
- Non-UI phase124: shared remaining178.434s, child limit158.434s; actual
  supervised elapsed162.339s.42 iOS LiftingCore methods passed. No app-host
  method start/pass appears in its retained log. Full62 inventory was not
  accepted; no new portable-export/capture/device accuracy acceptance follows.
- Non-UI log reports CoreSimulator405 “Invalid device state” during
  `installApplication:withOptions:error:` and Mach-308 server died at10:54:05UTC,
  near timeout termination, then BUILD INTERRUPTED. The receipt establishes
  timeout; these adjacent messages do not establish OS root cause or whether
  the install failure preceded or resulted from termination. No compiler error
  or failed app assertion is identified.
- Unit supervisor sent TERM, direct child returned-15; direct wait/group absence/
  cleanup true. One transient EPERM zero-signal probe was retained, then group
  absence verified. Outer observation did not time out and verified the receipt.
- Owned UI simulator cleanup succeeded: bounded list-before/shutdown/delete/
  list-after commands all0, `ownedDeviceAbsent:true`, `verified-absent`.
  Ownership excludes preexisting devices and escaped OS services.
- Both attachment exports skipped. There is no successful generated unit
  manifest and no actual native reconstruction/wrapper transport evidence.

## Retained diagnostics

Downloaded artifact11543589949, `native-diagnostics-37764499138-1`:
198365 ZIP bytes, SHA-256
`279e400bc2a2e66756ce9e7b85c19e8ada8b273855d852e2858a83b7b076b63d`.
Actual byte count/digest matched GitHub metadata.229 entries safely extracted
under ignored `artifacts/native-ci-runs/37764499138/diagnostics` with traversal,
symlink,4MiB per-file and32MiB total bounds; uncompressed1783166bytes.
Remote expiry October11 approximately06:54ET; local bytes retained.

Actual final overwritten periodic evidence:

| Receipt | State | Progress sequence | Elapsed seconds | Outcome |
| --- | --- | ---: | ---: | --- |
|build-compile.process.json|finished|17|72.272|child0, cleanup verified|
|test-ui.process.json|finished|77|380.280|child0, cleanup verified|
|test-unit.process.json|finished|24|162.339|timeout124, child-15, cleanup verified|
|test-unit.outer.json|finished|25|163.116|receipt verified, no outer timeout|

Resources in these receipts are supervisor/observer **self** CPU/RSS, not app,
command tree or simulator-service resources. Periodic sequences show updates
occurred; only the final overwritten receipt is retained, not a full history.

Full result artifact11544173684 uploaded successfully, metadata1640031bytes,
SHA-256`8f08e3ff3a605515ac0a2d0394c0627a2645cef0165cf3b6140a74d561503042`.
It has not been downloaded as part of this bounded diagnosis. Raw xcresult
records cannot substitute for the required successful attachment export.

## Next decision and timing

Process is finished; failure diagnosis above is complete. The shared test budget
left only158s for the unit child after UI used380s. A future orchestration change
needs leader review using these observations; no blind retry or limit expansion
is authorized. Build8/test10/job30 minute limits remain unchanged. No reliable
native completion ETA exists before that reviewed decision/dispatch; re-estimate
after its scope and actual run start. Private-browser, provider/device, real
accuracy and release readiness remain separate gates.
