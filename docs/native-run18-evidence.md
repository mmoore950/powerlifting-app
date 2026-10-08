# Run18 retained evidence

October 8, 2026, 07:26 ET. Run
[37768042551](https://github.com/mmoore950/powerlifting-app/actions/runs/37768042551),
job113280411298, exact revision `348d37e02e0424ae6682464ea563ef599e34ba17`.
Build-phase and simulator cleanup steps failed; iOS tests and exports skipped.
Final job upload/post-checkout steps succeeded; final job completion was still
being reported when these receipts were read. No repeated dispatch occurred.

## Actual evidence

- Eleven POSIX supervisor tests passed in 9.436s and 29 orchestration tests in
  11.382s. These include injected ownership/readiness cases, not successful live
  execution of the warm UI-to-unit experiment.
- macOS core: 42 passes, one opt-in HTTP skip, 1.895s test duration. Separate
  actual Swift-to-Node HTTP: one pass, 2.507s.
- Fresh owned simulator `E501CA5D-B246-4B74-BA76-C54B4956C23A`, iPhone16,
  iOS26.2 runtime, validated against the preexisting inventory. Original selected
  destination `841E0288-2704-4A18-A304-BF477CA384A8` remains distinct.
- `build-for-testing` succeeded: exit0, 137.632s supervisor elapsed, direct wait,
  owned process-group absence and command cleanup verified. This compilation
  includes the two-window test source but establishes no test execution.
- Boot request succeeded in 8.733s. Bootstatus child budget was 242.780s from the
  shared 440s build-phase budget. Last log still reports nonterminal data
  migration through LaunchServicesMigrator and KeychainMigrator. This identifies
  the observed wait; it does not prove the host/OS cause or a remedy.
- Bootstatus outer observation expired: phase125,
  `supervisor-cleanup-unverified`. Last periodic supervisor receipt remained
  `running`, sequence44, operation `wait-direct-child`, elapsed272.079s, reason
  timeout, SIGTERM sent, childReturnCode-15. It has no final direct-wait/group-
  absence/cleanup proof. The outer receipt reports sequence47,
  `receipt-unverified`, elapsed282.005s, `outerObservationTimedOut:true`.
  These are overwritten final retained observations, not a complete time series.
- Shared build phase finished125 at435.625s; final ready-inventory command was
  not launched. Owned device record retains bootVerifiedfalse. UI, non-UI,
  generated attachments and both exports did not run. The same warm-device
  experiment and all63 iOS method acceptance remain unmeasured.
- Owned simulator cleanup could not establish a fresh inventory: `simctl list
  --json` child timeout20s, phase124. That command itself was reaped and its
  owned process group verified absent (22.182s supervisor, 31.094s outer);
  simulator cleanup record is `cleanupComplete:false`. Shutdown/delete and
  device absence were not verified. Command cleanup is not simulator cleanup.
- Resource observations cover each supervisor itself, not simulator services,
  descendant resource totals or the host. No global service reset or ownership
  claim is made.

## Retained archive

Artifact11545724465, `native-diagnostics-37768042551-1`, downloaded and verified:
165535 ZIP bytes; SHA256
`07f287dad6ca3c221d526ac3180dbed0aabebe371b58cafdf45b9c25aa159f14`;
243 entries, 997111 uncompressed bytes. Extracted to ignored
`artifacts/native-ci-runs/37768042551/diagnostics` after refusing traversal,
absolute/colon/backslash paths and symlinks and checking limits of1000 entries,
4MiB per file and32MiB total. Metadata confirms exact run SHA. Remote expiry is
October11 at07:22:59 ET; the verified local copy is retained. Full result-bundle
archive was uploaded but is not needed to establish this bounded failure.

## Decision and time

Diagnosis complete; leader review determines any further native experiment.
No native retry or infrastructure correction is proposed automatically. No
reliable native-readiness ETA exists from this run; simulator readiness and
unverified cleanup block one. Re-estimate after a reviewed experiment and actual
runner evidence. Existing build8/test10/job30 limits remain, while observed
supervision overhead demonstrates that individual child budgets are not hard
whole-process completion guarantees. Profile source implementation proceeds
independently; production freshness, real-video accuracy and release remain
separate gates.
