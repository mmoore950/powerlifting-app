# Native validation gate

Status: first Apple CI passed on 2026-10-07 at revision ee7f22a: unsigned app build, 42 macOS core tests, 42 simulator core tests and 6 app-host tests, zero failures. See docs/status.md for run/toolchain/runtime evidence. The interactive/device checks below remain pending; Node fixture enumeration is not this gate.

Record Mac/Xcode/Swift/XcodeGen versions, Simulator/iPhone model and OS, exact commands, results and screenshots.

## Bounded simulator UI smoke and screenshots

The manual workflow now includes PowerliftingAppUITests: one smoke method launches the app, visits Plates, Training, Attempts, Competition and Bar path, checks reachable tabs/navigation plus disconnected-data/local-import controls, and attaches five named screenshots with keepAlways lifetime. Training/Attempts are two tabs within one feature group. No private media, live API, fake lifters or tracking paths are supplied. CI uses a fresh hosted simulator; this test expects no previously configured endpoint or imported video.

After successful scheme tests, `bash tools/ci/native-validation.sh screenshots` exports all attachments from test.xcresult using xcresulttool and requires at least five PNG files. Review the attachment manifest/names and images under artifacts/native-ci/screenshots; a file count is not visual approval. Existing result bundles are retained on test failure; the export step is skipped then. The manual trigger, 10-minute test-step limit, 30-minute job limit and three-day artifact retention remain. Run 37723566137 at revision 2611743 actually passed the UI test and exported the exact five named screenshots. Copies/manifest are preserved under artifacts/native-ci-runs/37723566137/screenshots; observed visual anomalies and remaining gates are recorded in docs/status.md.

Review all five screenshots for clipping, unreadable text, navigation visibility and honest disconnected/no-video states. This single default portrait smoke pass has no pixel baselines and does not exercise data browsing, video import/analysis, accessibility settings or device lifecycle. Successful tab navigation does not satisfy the acceptance checks below.

## Build and numerical execution

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

Native service recovery: run OPLRecoveryTests and OPLPageStoreTests, then exercise live 409 expiration, 503 busy, 504 timeout, offline fallback and repository/foreground changes on Simulator. Verify automatic first-page restart happens at most once per logical query budget; old cursor/rows are discarded, metadata adoption does not cause another transaction, and explicit Try again works. See native-service-recovery.md.

The data and video gates in `research-gates.md` are independent. Passing plate UI checks does not validate daily ingestion or automatic bar identification.

## Product accessibility source follow-up

The bounded view source pass is documented in `accessibility-source-pass.md`. Purpose/unit/set labels, explicit error cues and Developer settings separation have not been exercised with VoiceOver, Dynamic Type or rendered UI. Include reverse-stepper adjustment actions, text-field value announcements, noninteractive per-side grouping, long names/filters, missing/failed result rows and no-connection/developer-disclosure/retry paths in the first device/Simulator pass. These source changes are not accessibility acceptance.
