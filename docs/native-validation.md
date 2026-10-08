# Native validation gate

Status: first Apple CI passed on 2026-10-07 at revision ee7f22a: unsigned app build, 42 macOS core tests, 42 simulator core tests and 6 app-host tests, zero failures. See docs/status.md for run/toolchain/runtime evidence. The interactive/device checks below remain pending; Node fixture enumeration is not this gate.

Record Mac/Xcode/Swift/XcodeGen versions, Simulator/iPhone model and OS, exact commands, results and screenshots.

## Bounded simulator UI smoke and screenshots

The manual workflow now includes PowerliftingAppUITests: one smoke method launches the app, visits Plates, Training, Attempts, Competition and Bar path, checks reachable tabs/navigation plus disconnected-data/local-import controls, and attaches five named screenshots with keepAlways lifetime. Training/Attempts are two tabs within one feature group. No private media, live API, fake lifters or tracking paths are supplied. CI uses a fresh hosted simulator; this test expects no previously configured endpoint or imported video.

After successful aggregate tests, `bash tools/ci/native-validation.sh screenshots`
exports BOTH results: `test-ui.xcresult` to `screenshots/ui` for the exact five-name
UI checker, and `test-unit.xcresult` to `screenshots/unit` for its generated native
capture manifest and bounded extraction recipe. No manifest merging or image
substitution. Both raw result bundles survive test failure; export remains skipped
then. Apple run15 reached preparation and failed cold-boot readiness; its split
app build/tests/exports were skipped. Older run37723566137 at2611743
actually passed/exported its five UI images from a single result; that historical
evidence does not validate the new split route. Test10/job30 and retention3days remain.

Review all five screenshots for clipping, unreadable text, navigation visibility and honest disconnected/no-video states. This single default portrait smoke pass has no pixel baselines and does not exercise data browsing, video import/analysis, accessibility settings or device lifecycle. Successful tab navigation does not satisfy the acceptance checks below.

## Build and numerical execution

The build phase uses `build-for-testing` on the selected existing simulator. The
new test orchestrator runs UI first on one owned fresh simulator, then all non-UI
scheme targets on the original destination, using `test-without-building` and the
same scheme/derived data. The full scheme and both export gates remain. This follows [Apple's xcodebuild
documentation](https://developer.apple.com/library/archive/technotes/tn2339/_index.html).
The unchanged outer limits are build 8 minutes, test 10 minutes and job 30 minutes.

`tools/ci/supervise-process.py` launches xcodebuild without a shell in a new POSIX
session/process group. Build shares440s across compilation and mandatory UI
readiness; the split test phase shares560s and gives
each invocation its remaining budget minus cleanup reserve. The outer8/10min
limits retain margin for receipt writing and bounded observation. Timeout
or SIGINT/SIGTERM signals only that owned group, allows 5 seconds of grace, then
uses KILL if necessary, observes the group for up to 5 seconds and waits for the
direct child for up to 5 seconds. Remaining owned descendants are also cleaned
after a normal child exit. Escaped sessions and simulator OS services are outside
this boundary; no process-name matching or global kill is used. Group existence
can include unreaped zombies, so incomplete cleanup fails conservatively with125.
Timeout is124, cancellation is128+signal and ordinary child failures are retained.
An EPERM result from the zero-signal group probe is recorded as present/uncertain
and observed under the existing deadline; it never proves absence. Persistent
uncertainty, an actual signal permission error, or a different probe error cannot
pass cleanup. The direct-child wait runs in finally even if group cleanup raises.
Apple's [killpg documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/killpg.2.html)
distinguishes EPERM from ESRCH. The runner's transient EPERM kernel cause is unknown.

Top-level `build-compile.process.json`, `ui-build-bootstatus.process.json`,
`ui-build-ready.process.json`, `test-ui.process.json` and `test-unit.process.json`
receipts preserve the command,
PID/group, reason, signals, child exit and observed cleanup outcome in the plain
diagnostic artifact. A hard external kill can leave a `running` receipt; that is
not completed phase evidence. These deadlines do not guarantee OS scheduling or
termination of an uninterruptible process. No retry or timeout expansion was added.
The existing setup phase runs nine focused synthetic supervisor methods, including
POSIX TERM/KILL, SIGINT/SIGTERM cancellation, child/grandchild cleanup and unrelated
process preservation and descendants remaining after a normal parent exit.
Windows runs only four direct-child checks and skips the five POSIX methods.
Source/local success is separate from macOS/Xcode execution.
Supervisor test receipts/stdout/stderr are retained as unique top-level diagnostic
files, with separate SIGTERM/SIGINT suffixes. Error receipts include the actual
exception traceback and operation; a failed cleanup assertion does not erase them.

`native-test-phases.py` owns ONE monotonic560s budget across both invocations,
including cleanup reservations. Each child gets remaining time minus20s (15s
existing supervisor cleanup plus observation margin). Cancellation is forwarded to
the current supervisor/group; exhausted/failed/cancelled phases cannot launch the
second command. `test-phases.json` records the aggregate and partial/unrun phases.
An outer observation failure stops only the owned supervisor wrapper and reports
unverified child cleanup, never successful cleanup of escaped sessions/services.

The current named XCTest source inventory is42core+19app-host+1UI=62 iOS methods;
the HTTP test is entirely macOS-only, so iOS has no expected HTTP skip. Its separate
actual HTTP gate and macOS opt-in skip remain. `check-test-inventory.py` requires
the split passing IDs to match current iOS sources exactly once, with no omitted,
extra, failed or skipped methods. Unsupported conditional/generated source forms
require review rather than a frozen count. This log gate is not a Swift parser.

`owned_ui_simulator.py` records preexisting IDs, run/attempt/name/runtime/device
type and validates the returned new UUID against fresh inventory before boot.
Creation/boot request shares90s including bounded command cleanup within prepare2min;
it records `bootRequested:true`, `bootVerified:false`. Installed
simctl help/commands/logs are retained. The always cleanup step has100s internal
budget within its2min step. It validates record/run/current device identity,
refuses malformed/empty/preexisting IDs, shuts down/deletes only its owned UUID
and requires observed absence. Cancellation, missing identity or failed commands
keep cleanup false. Job30 can interrupt cleanup; runner teardown remains external.
`native-build-phase.py` first compiles on the existing destination while the fresh
UI simulator boots independently. It then requires successful bootstatus and a
fresh matching available Booted inventory entry before marking ready. ONE440s
deadline covers all three commands: compilation retains70s for following work and
cleanup, bootstatus retains30s for final inventory/cleanup, and each command also
reserves20s for its supervisor cleanup/observer. Compile failure, cancellation or
budget exhaustion leaves explicit unrun readiness in `build-phases.json` and
prevents the test phase. No separate boot440s allowance or retry. Simulator OS
startup services are outside the owned command group.

Nineteen orchestration tests include shared budget/cancellation/failure,
inventory omission/duplicate/skip guards, injected simulator identities and a real
POSIX signal-propagation method. The original14 all passed on macOS in run15;
the five added build-budget/readiness methods are source-only until a reviewed run.
Windows18pass/1POSIXskip is not new simctl/macOS proof.
Top-level test receipts/logs are retained before temporary fixture cleanup.

1. Run `swift test --package-path Packages/LiftingCore`: fixture cases and 120 deterministic small-inventory comparisons against exhaustive full count-vector enumeration, plus invalid inputs/decoding/selection/cap cases.
2. Generate the project, compile the app, run its scheme tests, including PowerliftingAppTests and the package tests. Resolve warnings that expose isolation, resources, test-host or package/scheme problems. New application test sources have not been generated/compiled/run in Windows.
3. Run the UI on Simulator and a real iPhone before calling this feature validated.

## Plate screen acceptance

- 45 lb bar, no collars, two 45 lb plates per side: 225 lb. Reverse and forward agree.
- 20 kg bar, 25+20+10+5 kg per side: 140 kg; 2.5 kg collars each: 145 kg.
- Switch display lb → kg → lb repeatedly: exact target, selected physical total and equipment do not change. Save unchanged converted equipment fields and repeat.
- Enter a kg target with lb inventory; enter an lb target with kg inventory. The selected load reflects actual plate mass and clearly shows both units.
- Set target below the bar, above inventory, between reachable totals, and exactly halfway. Verify no false exact label; inspect lower/upper and difference.
- Custom plates 4 kg ×1 pair and 3 kg ×2 pairs with zero bar, target 12 kg: two 3 kg per side. Verify limited and zero availability.
- Reverse count never exceeds availability; reducing inventory clamps previous counts; swapping inventory systems preserves each system's selection.
- Negative, blank, letters, too many decimals, oversized values and duplicate plates produce understandable errors. Decimal comma locale works with the device keyboard.
- Type quickly/change inventory during a calculation: no old result overwrites a new target and no UI freeze. Exercise complexity cap with unusual fractional sizes.
- VoiceOver reads controls and per-side plate labels; large Dynamic Type, narrow iPhone screens, keyboard dismissal and horizontal diagram scrolling remain usable.
- Milestone 2: configure each inventory separately, bar/collars, display/plate units and target; relaunch. Verify exact canonical mass and both inventories survive. Invalid target text must not overwrite the last valid saved target. Reverse counts/training plans remain session-only.

## Training and attempt acceptance — Milestone 2

- Run the added TrainingTests and PreferencesTests, not just independent Node specifications. Formula reference values: 100 kg ×5 gives Epley 116.666… kg and Brzycki 112.5 kg; 100 kg ×10 gives 133.333… kg for both. One rep preserves performed mass. Zero/negative/unsupported reps and input errors must fail visibly.
- Change display units with performed/top/goal/increment/manual weights entered: physical values and existing valid results remain unchanged; switching plate inventory/equipment clears stale plans. Change inputs rapidly during planning to check cancellation and old-result rejection.
- With 20 kg bar and stock kg inventory, requested top 140.1 kg resolves to 140 kg; default warm-ups are 56, 77, 98, 119 kg. With top 25 kg, omit duplicate bar rows and return 20, 21 kg. No zero, nonascending or above-top rows. Below-bar/no-warm-up/invalid progression states are explicit.
- Edit reps/percentages, add/delete sets, restore progression, and inspect per-set percentage target versus actual load/plate diagram. Invalid ordering is an error; it is not silently rearranged.
- With 20 kg bar/no collars, stock kg inventory, desired third 201 kg and 2.5 kg increment: 170/187.5/200 kg. All totals and diagrams agree. Verify three distinct loads, selected increment, unavailable third adjustment and empty-range failure.
- Generate suggestions, enable manual opener/second, edit seeded weights, and check valid overrides outside presets versus invalid unavailable/off-increment/nonascending inputs. Verify competition preset changes shared equipment explicitly and retains both saved inventories.
- Pound bars/inventory with kg meet increments may have no exact compatible totals. Show an error and let the user select actual meet equipment; never pretend rounded conversion meets an exact increment.
- On Simulator, seed corrupted bytes, wrong storage type, unknown schema, mismatched inventory unit, oversized and schema-0 fixtures. Verify recovery notice/defaults, backup preservation and next-save behavior. App UI/storage integration remains untested on Windows, even though codec XCTest source exists.
- Verify the notices resource is bundled and opens from native Training/Attempts controls. All plate weights/units remain readable with color vision differences, VoiceOver and larger text; kg 25/20/15 map to red/blue/yellow. Smaller/custom/pound colors are schematic choices.

## Later gates

### Actual service HTTP contract (macOS gate passed)

The manual workflow adds `http-setup` and `http-contract` macOS phases (three-minute limits each). Setup verifies pinned Node 24.19.0/pnpm 11.25.0 archives and installs locked production service dependencies with frozen-lockfile/ignore-scripts. Contract launches the existing Node server/importer on an ephemeral loopback port using 54 labeled synthetic rows, then runs only OPLHTTPContractTests/testActualNodeHTTPContract through `swift test`. A test-only exact-origin adapter preserves repository URL construction and calls the real URLSession transport; production HTTPS/ATS settings remain intact.

The runner requires successful XCTest exit AND a one-time completion proof from the method; a skipped or missing method cannot pass this phase. Run 37728528425 at 105815f actually passed the selected method in 1.174 seconds, verified the execution proof and completed controlled cleanup before phase exit 0. Ordinary package invocation had 42 passes/one opt-in skip/zero failures; that skip is not an extra pass. All 53 simulator methods passed separately. Pinned dependency setup took about 23 seconds, contract about five seconds; limits unchanged. Logs/artifact proof/timing in docs/status.md. See native-http-boundary-scope.md for coverage/cleanup/tool pins. This does not validate public TLS, iOS networking, rendered browsing or production recurring freshness.

VideoMediaLifecycleTests adds four app-host integration methods using tiny runtime-generated synthetic MOVs in owned temporary roots. After the bounded encoder ownership/diagnostics repair, run 37726403071 at 58f3d63 passed all four methods: imported metadata/decoded upright geometry, invalid-media cleanup, managed/source ownership, and model failed/successful replacement/removal with explicit player detach. All 53 simulator methods and 42 macOS core tests passed; test phase approximately 7 minutes 20 seconds below its unchanged ten-minute limit. Prior run 37724841204 failed two methods during fixture encoding before application assertions; the new run supersedes that incomplete evidence. See docs/status.md for logs/artifact/timing. Store/model defaults preserve production storage/security-scoped access; await returned import tasks without sleeps. These tests do not measure bar detection, observer count/deinit timing, large/private video or device performance.

Native service recovery: run OPLRecoveryTests and OPLPageStoreTests, then exercise live 409 expiration, 503 busy, 504 timeout, offline fallback and repository/foreground changes on Simulator. Verify automatic first-page restart happens at most once per logical query budget; old cursor/rows are discarded, metadata adoption does not cause another transaction, and explicit Try again works. See native-service-recovery.md.

The data and video gates in `research-gates.md` are independent. Passing plate UI checks does not validate daily ingestion or automatic bar identification.

## Product accessibility source follow-up

The bounded view source pass is documented in `accessibility-source-pass.md`. Purpose/unit/set labels, explicit error cues and Developer settings separation have not been exercised with VoiceOver, Dynamic Type or rendered UI. Include reverse-stepper adjustment actions, text-field value announcements, noninteractive per-side grouping, long names/filters, missing/failed result rows and no-connection/developer-disclosure/retry paths in the first device/Simulator pass. These source changes are not accessibility acceptance.
