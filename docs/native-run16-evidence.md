# Run 16 failure evidence

October 8, 2026. Run37759725854/job113252936665, exact revision
`f000132924697e56085aeec1803b50d1fbf6a2f0`. Final job conclusion failure;
both diagnostic uploads completed. No rerun is authorized by this record.

## Actual results

- Nine POSIX supervisor methods passed in7.047s; nineteen orchestration methods
  passed in1.641s on the macOS runner. Ordinary macOS core42passed/1explicit
  HTTP-fixture skip in1.689s; separate actual HTTP1passed in3.606s with completion
  marker. These do not establish an iOS app build.
- Prepare created and validated fresh simulator
  `E0240737-238A-4160-AA4E-270D0EF2280F`, requested boot and retained
  bootVerifiedfalse. Original build destination remained
  `841E0288-2704-4A18-A304-BF477CA384A8`.
- Build phase started05:57:12ET; compile launch was logged05:57:17ET;
  exit125 logged06:05:12ET. `build-phases.json` gives shared440s,
  child349.957229357s, future reserve70s and actual aggregate451.11313238s.
  Outer observer nominal child timeout+17s expired, but supervisor receipt still
  had state running/elapsed0.386s, supervisorPID5767 and childPID/PGID5772.
  No completed direct-child wait/group-absence receipt exists. Owned-child cleanup
  is unknown. The separate child session is outside the killed wrapper group.
- Entire retained compile log has no compiler-error diagnostic. It ends during
  LiftingCore Swift compilation with **BUILD INTERRUPTED**. This establishes
  interruption/outer observation failure, not a Swift source error or its cause.
  The scheduling/blocking reason for elapsed time exceeding the nominal observer
  deadline is unknown; no periodic operation/resource receipts were collected.
- Readiness commands were never launched. All62 required iOS tests and both UI
  and generated-unit attachment exports were skipped. No actual generated-native
  reconstruction or strict wrapper evaluation can proceed from this run.
- Cleanup's initial `simctl list --json` soft20s timed out. Its supervisor finished
  in20.191s, TERM child-15/direct wait completed/group absent/command cleanuptrue,
  exit124. One EPERM probe was handled conservatively. Simulator cleanupfalse:
  shutdown/delete/final absence checks were not launched, so owned simulator
  absence remains unknown. Runner post-job orphan cleanup is not proof of those
  specific ownership/absence gates.

## Retained artifacts

Diagnostics11541739537 was actually downloaded:110101bytes, ZIP SHA256
`8fb002dd51ba102ec986aa871700440ffc57d25ebd47563e70ac98e819c123e8`.
178 bounded top-level regular entries were inspected/extracted under ignored
`artifacts/native-ci-runs/37759725854/diagnostics`. Each entry<=4MiB and total
<=32MiB. Diagnostic retention expires October11 approximately06:06:40ET;
the local copy is retained. Full artifact11542078388 is listed110101bytes with
SHA256 `6ac79facf67868a9250feef228431681b6d38deae9f8ad376af18ee26b0e8f45`;
it was not separately downloaded. Final job logs were retrieved and inspected.

## Reviewed next source experiment

Leader accepted this bounded diagnosis and approved periodic fixed-size atomic
supervisor/outer receipts: operation, monotonic elapsed/deadline, child poll and
cheap in-process resource observations; no diagnostic subprocess polling loops.
Prepare will create/validate only, then build compiles before requesting fresh
boot, bootstatus and exact matching Booted inventory under the same440s budget.
This removes simultaneous fresh startup as an explicitly unproven contention
experiment. No time expansion, retries, global kills/reset or weaker readiness
gate. Source instrumentation does not establish the host stall's root cause.

Source estimate20–35minutes after the cumulative partition handoff, no hard
delivery deadline. Existing prepare2/build8/test10/job30-minute workflow limits
remain. Native result/readiness has no reliable estimate until review and an
authorized run produce new evidence. Real reference clips remain zero and
accuracy unmeasured.
