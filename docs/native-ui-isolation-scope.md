# Native UI startup comparison and isolation proposal

October 8, 2026. Source/evidence review only; no workflow change or CI dispatch.
Portable export source is46a50ef+a13135d, outside the observed runs below.

## Actual comparison

Logs retained locally from hash-verified artifacts:
`artifacts/native-ci-runs/37738044082/test.log` and
`artifacts/native-ci-runs/37747857345/diagnostics/test.log`.

| Observation | Ninth successful run | Fourteenth timeout |
| --- | --- | --- |
| Exact revision |4a700f5017712c4fb62992d685eed219ed38fb03|c6eb206eb8db7c6c0cdc1b5e2dc8d4ad168393e7|
| Toolchain |macOS15.7.9/x86_64, Xcode16.4/Swift6.1.2, SDK18.5|Same recorded versions|
| Selected device |iPhone16,841E0288-2704-4A18-A304-BF477CA384A8|Same recorded name/UDID|
| Available runtime |iOS26.2,23C54|Same recorded runtime/build|
| Test phase start (ET) |02:34:10|04:12:14|
| Core suite wall |6.748s,42passes|6.448s,42passes|
| App-host suite wall |59.831s,14passes|58.959s,14passes|
| Core end → app-host start |225.492s|232.082s|
| UI suite start (ET) |02:41:32.538|04:19:11.101|
| Automation setup |t3.14s|t17.97s|
| Enter idle wait |t11.07s|t78.00s|
| Foreground wait |t17.63s|t139.05s after event-loop/animation notification warnings|
| First Plates existence/snapshot |t18.65s, proceeds|t140.09s, accessibility snapshot pending|
| UI verdict |Pass58.001s; five screenshot activities|No completed UI verdict before interruption|
| Overall |57simulatorpasses/test success|42core+14app-hostpass; test timeout124|

Run14 internal560s receipt elapsed563.839s: TERM, child-15, direct wait completed,
owned group absent/cleanup true before upload. One zero-signal EPERM probe was
recorded and conservatively handled. This validates supervisor behavior for that
run; simulator services remain outside its process group.

The long core-to-app transition exists in both runs; suite-method totals alone
cannot size a test phase. The same UDID on two hosted jobs does not prove the same
physical runner or persistent device state. No CPU/main-thread stack or native
provider diagnostics establish a specific root cause. The UI warning is not proof
of a permanent app animation. The selected newer runtime/older SDK combination
is recorded rather than inferred; the ninth run succeeded with that combination.

## Startup source review

`git diff 4a700f5 c6eb206 -- App Tests/UI` is empty. The initial screen, model and
smoke test have no app-source change between success and timeout.

- `PowerliftingApp` creates `ToolkitView`; the initial Plates screen constructs a
  LoadingModel and performs a preferences decode on the main actor.
- `PlateLoadingView.task` requests calculation. LoadingModel waits150ms, then runs
  PlateLoader in Task.detached; token/cancellation guards end loading on result.
  Its ProgressView is conditional. No repeatForever/Timer or unconditional polling
  was found in this startup path. This inspection does not measure main-thread time
  or prove the detached calculation finished during run14.
- Training/Attempts appearance initializes display inputs. Competition startup
  returns immediately for an empty endpoint; page state refuses fetch without a
  client/version/query. The smoke expects the disconnected screen. No video is
  imported in the UI test.
- New portable-source `recoverAnnotationExport` adds an actor call on Bar path
  appearance. It is not in run14 and cannot explain that timeout; future empty-root
  recovery and picker behavior still need native validation.

## Recommended bounded implementation for review

Create ONE owned UI simulator using the selected installed runtime and actual
selected deviceTypeIdentifier, with a run-specific name and recorded returned UUID.
Keep the existing selected simulator for non-UI tests. Do not erase/delete existing
devices, kill global services or choose an unobserved hard-coded device/runtime.
Capture inventory, state, exact creation/boot commands and times. Actual `xcrun
simctl help` on the Apple host establishes installed command syntax; Windows does
not validate it. Create/boot request under the existing prepare2min limit; setup/build/job
limits remain5/8/30min. An overrun fails with diagnostics, without retry/extension.

Build all targets once using the existing build-for-testing destination/derived
data. Following actual run15 cold-boot timeout, approved repair shares ONE440s
deadline across build-for-testing first, required UI bootstatus second, and fresh
matching Booted inventory proof third. Compilation overlaps natural simulator
startup; future work/cleanup reservations and failure/unrun receipts retain the
existing build8min limit. No ready flag from boot request alone, no retry/extension.
In the single existing10min test step, run two sequential
test-without-building invocations with the same built scheme/derived data:

1. UI first, on the owned freshly booted simulator, selecting the complete
   `PowerliftingAppUITests` target. Produce `test-ui.xcresult` and its own process
   receipt/log/exit code. Keep normal XCTest idle/accessibility/screenshot checks.
2. Non-UI on the original selected simulator, with only the UI target excluded.
   Produce `test-unit.xcresult` and separate receipt/log/exit code. All core and
   app-host methods, including future additions, remain selected by the scheme.

One monotonic560s absolute phase deadline covers BOTH invocations, startup and
cleanup. Each child gets only remaining time minus the existing bounded cleanup
margin; never560s independently per child. Do not start another child when no
budget remains. Record unstarted phases as unrun/failure, not passes. Any child
failure makes the aggregate test phase fail; no blind second attempt. No absolute
OS termination guarantee is implied. A small orchestration helper needs meaningful
injected-clock tests for the shared deadline, no second launch after timeout,
failure propagation and all selection/result paths; existing nine POSIX tests stay.

This changes both UI destination and order. A pass would show that the reviewed
arrangement completed on that host; it would not isolate which change mattered or
establish an app defect's cause. If separate setup overhead exhausts560s, report
actual timings and return for a budget decision; do not expand the test10/job30.

## Results and attachment gates

Preserve both result bundles and raw logs in the existing full artifact; plain
diagnostics include both receipts and selected/owned simulator records. Update the
summary to show each phase and aggregate status. Do not report the full scheme
passed unless their union contains all expected tests without unexpected skips,
duplicates or failures: current source42 ordinary core+19app-host+1UI. The HTTP
method is macOS-only/absent on iOS (no expected iOS skip); macOS opt-in skip and
independent actual HTTP contract gate remain separate and retained.

After successful aggregate tests, export attachments from BOTH bundles into
separate directories:

- `screenshots/ui`: export `test-ui.xcresult`, run the unchanged five-name
  `check-ui-attachments.py` against its own manifest. Require exactly the UI smoke
  group and five non-failure screenshots as today.
- `screenshots/unit`: export `test-unit.xcresult`, retain its original manifest and
  generated attachments. Point the approved generated extraction recipe to THIS
  manifest; select the exact rotated-native capture test group. Retain current
  bounds/type/name/byte/hash/range/synthetic checks. Do not merge manifests, rename
  generated attachments into UI evidence, omit the unit export or reconstruct from
  arbitrary raw xcresult paths.

Actual exported generated-group shape is still unobserved. Inspect it before
reconstruction; unexpected metadata returns for review. The generated fixture's
strict-wrapper run stays a separate actual-evidence gate. Failed runs keep both
available raw result bundles; successful screenshot export is not manufactured
from partial evidence. Update all `test.xcresult`/single-manifest assumptions in
the shell, summary, native validation and generated extraction documentation.

Cleanup targets ONLY the created UI UUID recorded by this run. Bounded shutdown,
deletion and subsequent absence check run in an always path before artifact upload;
record failures and partial cleanup honestly. Existing/shared devices and processes
are untouched. The job30 limit can interrupt cleanup; a saved command/receipt is
not evidence of completed simulator shutdown. Runner teardown remains external.

## Size and decision

Proposal comparison checkpoint is source only. Recommended Medium for bounded
implementation after leader review; estimate20–35min, no hard source deadline,
with shared-deadline and two-bundle export correctness uncertainty. First reviewed
native result remains15–22min after runner start provisionally, queue excluded,
prepare2/build8/test10/job30 bounds. Added cold startup may make that estimate wrong;
actual phase receipts would support the next sizing decision. Native/provider,
actual generated-wrapper, device and representative accuracy gates remain open.

Apple documents scheme/target selection and build-for-testing/test-without-building
in [TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html).
This supports the split execution route; it does not prove the installed simctl
syntax, this runtime's startup performance or successful attachment exports.
