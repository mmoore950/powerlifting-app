# First Apple run: diagnostic handoff

## Current checkpoint — October 8, 2026

The first-run prerequisites below were resolved through the authorized private `mmoore950/powerlifting-app` repository and hosted macOS validation. Latest run [37726403071](https://github.com/mmoore950/powerlifting-app/actions/runs/37726403071), revision `58f3d63`, passed unsigned simulator build, 42 macOS core tests and 53 simulator methods (42 core, 10 app-host, 1 UI), including all four synthetic media lifecycle checks. Five named screenshot files were exported; previous default-screen visual review was accepted separately. Evidence and limits are in `status.md` and `native-validation.md`.

Zero observed real-lift evaluation clips, no production scheduler/reachable approved HTTPS service, and no real-device/signing/release evidence remain current limitations. The native/service HTTP boundary test source and CI phase are prepared in `native-http-boundary-scope.md`; their Swift execution is pending. Readiness timing remains blocked on these prerequisites and scope decisions. Latest native job took about 10m50, test phase 7m20, with hard test 10 minutes/job 30 minutes; these process bounds do not estimate research readiness.

## Historical first-run handoff — superseded where noted above

The remainder preserves the October 7, 2026, 4:05 PM ET pre-run handoff and its source inventory/prerequisite reasoning. Its zero-native, no-remote/approval and unrun-test statements describe that earlier checkpoint, not current status. At that time this pack consolidated source and evidence without executing native features; Windows had no Swift/Xcode and hosted macOS was the prepared route.

## Prerequisites and ownership

| Prerequisite | Current evidence | Required next decision / owner |
|---|---|---|
| Repository destination and permission | No remote/commits. Leader found account mmoore950 and no matching repository; proposed private powerlifting-app destination remains unanswered | Human approves exact destination/visibility/source upload; leader verifies write/Actions/dispatch access before creation or push |
| Free runner/artifact allowance | Account authentication does not establish allowance; connector has no billing/allowance evidence | Human/account owner confirms approved allowance; leader verifies runner/action policy. Do not infer free minutes or enable billing |
| Apple runner | Manual workflow prepared for macos-15-intel, actual versions logged | After approvals, leader dispatches reviewed revision; runner queue and compatibility unknown |
| Reachable competition API | Genuine local Node/SQLite service works; loopback cannot serve an iPhone directly | Human/leader selects approved HTTPS hosting or development connection, resource/cost/access policy. Worker then implements target-specific deployment; no URL guessed |
| Continuing source checks | Due-aware wrapper/retry/state/logs and finite demos exist; no permanent scheduler | Approved host/scheduler installation plus observed real upstream recurring check/publication/retry. Leader owns operational acceptance |
| Representative video references | Deliberately empty manifest, schema/scorer/encoder source prepared | Human/leader supplies authorized local representative clips/permissions/manual references/splits and real device access. Worker measures existing baseline, then proposes detector changes from failures |
| iPhone validation/signing | No device/compiler/signing evidence | Actual Simulator diagnostics first; later human-owned device/signing/TestFlight prerequisites. No credential action assumed |

Current stored data source date is October3; successful check October7 at12:49:39PM ET, next due6:49:39PM ET. That is a stored eligibility time, **not an automatic run**. No new source check/import is scheduled by this pack. Upstream export time remains uncertain.

## Static native inventory

Counted source, not test discovery or execution: **17 App Swift files +10 core files;42 package XCTest methods across9files,6 app-host methods across2files**.

| Package test source | Methods |
|---|---:|
| PlateLoaderTests | 5 |
| PreferencesTests | 3 |
| TrainingTests | 4 |
| OPLRepositoryTests | 7 |
| OPLRecoveryTests | 6 |
| BarCandidateTrackerTests | 7 |
| VideoSampleClockTests | 2 |
| VideoTraceTests | 4 |
| VideoPredictionExportTests | 4 |
| **Package total** | **42** |
| OPLPageStoreTests (app) | 4 |
| BarPredictionExporterTests (app) | 2 |
| **App total** | **6** |

Package declares Swift tools5.9/iOS17/macOS13. App manifest declares Swift5language/iOS17, XcodeGen≥2.46.0, local LiftingCore and an app-host test target. First generation must verify scheme actually resolves package+app targets and discovery includes expected source methods; current count does not prove that.

## Exact first-run sequence

Existing `.github/workflows/native-validation.yml`: manual dispatch only, contents read, one concurrent macos-15-intel job,30-minute job timeout; checkout/upload actions pinned. Only `artifacts/native-ci/` diagnostics uploaded with3-day retention. Do not upload `artifacts/` wholesale, local media/manifests, SQLite/ZIP, node_modules, credentials or runtime state. Review source selection before the authorized commit; AGENTS/product/coordination/research instructions belong with the source.

After explicit repository/write/runner allowance approvals and reviewed source saved to its default branch:

```sh
# Placeholder command; NOT executed or authorized by this document.
gh workflow run native-validation.yml --repo OWNER/REPOSITORY --ref REVIEWED_BRANCH
```

GitHub UI equivalent: Native validation (manual) → Run workflow → reviewed branch. Do not substitute an unrelated repository, publish the project, create billing or execute CI merely because this command is written down.

| Phase | Exact prepared invocation | Evidence / boundary |
|---|---|---|
| Toolchain | `bash tools/ci/native-validation.sh setup` | OS/CPU/Xcode/Swift/SDK/Python logs; XcodeGen2.46.0 archive SHA verification.5-minute step |
| Core | `bash tools/ci/native-validation.sh core` | `swift test --package-path Packages/LiftingCore`; expected42methods, all currently unrun.8-minute step |
| Generate/select | `bash tools/ci/native-validation.sh prepare` | XcodeGen/project-list/simctlJSON; available iPhone withiOS17+ UUID selected.2-minute step |
| Build | `bash tools/ci/native-validation.sh build` | Uses selected SIMULATOR_ID, unsigned `CODE_SIGNING_ALLOWED=NO`, single destination/parallel testing off.8-minute step |
| Simulator tests | `bash tools/ci/native-validation.sh test` | Same selected destination; scheme expects core+app-host methods, actual discovery required.10-minute step |
| Summary | `bash tools/ci/native-validation.sh summary` | Completed phase exit codes, actual revision, limits; upload logs/result bundles best effort |

Step ceilings do not sum to allowed elapsed time; whole job30minutes can terminate before all phases. Queue/startup are outside an expected-success estimate. Hard timeout/cancellation/runner failure can prevent cleanup/artifact upload, so retain Actions console logs; absence of an xcresult is not success. The generated project, Swift compilation/API/isolation, XCTest discovery and Simulator execution are all new gates.

Direct Mac commands and simulator selection are also in README/hosted-native-build-plan.md; the human has no Mac, so they are not a current execution alternative. No Apple account/signing secrets are needed for unsigned Simulator validation.

## Product-brief coverage and remaining work

| Required feature | Implemented source | Actual executed evidence | Remaining implementation / validation |
|---|---|---|---|
| Forward load, independentlb/kg inventory/display, bar/two collars/finite pairs/nearest alternatives | Weight/PlateLoading/LoadingModel/PlateLoadingView/EquipmentView | Independent Node specification fixtures ran previously; source reviewed | Swift numerical/persistence tests; native input/unit/nearest/display correctness and accessibility. No known new algorithm requirement selected |
| Reverse load with both units and per-side diagrams | Shared loading source and reverse steppers | Same independent fixture evidence; source arithmetic reviewed | Actual native adjustment/finite limits/unit persistence/diagram announcements |
| Epley/Brzycki completed-set estimate and valid ranges | Training core/TrainingView | Independent Windows training specification check previously passed | Native formula/invalid-input XCTest and UI behavior; no medical/programming claim |
| Editable practical warm-ups and loading diagrams | WarmupPlanner/PlanRunner/TrainingView | Specification evidence and4 Training XCTest source methods (unrun) | Native planning/cancellation/prefs/editing/rounding and unavailable targets |
| Backward attempts, editable ranges/goal/legal increments | AttemptPlanner/AttemptsView | Specification evidence; native test source unrun | Simulator/domain tests plus meet-specific human rule verification; legal exceptions intentionally not modeled |
| Native lifter search/profile meet history and filtered best performances | OPL repository/cache/model/views plus full DataService | Genuine4,043,255-row import, real local search/history/ranking pages;16 Node service/retention/query/proposal tests pass (~5.84s) | Reachable approvedHTTPS deployment; all native client/cache/screens tests and life cycle. Results remain dated best performances, not ratified records |
| Mandatory ongoing additions/corrections/removals, atomic versions/cache transitions | Full replacement ingestion, due/retry wrapper, pointer/version leases, retention, recovery | Synthetic add/correct/remove/failure/idempotency and finite recurring mechanics; actual manual90.55s revalidation, due skips | Actual permanent scheduled upstream checks/monitoring/deployment. Native cache/version expiry+busy/offline transitions unrun; no freshness guarantee yet |
| Offline/stale/source/check/device-save meaning | Versioned bounded disk cache, separate metadata/page states, settings/retry views | Local API date/version race regressions pass; native source reviewed | Native persistence/purge/offline/current-version/generation and truthful UI execution |
| Local video import/rep trim/playback/bar path overlay | VideoImportStore/VideoModel/VideoAnalysisView/VideoTrace | Node evaluation integrity/synthetic contract tooling only; no decoded native video | AVFoundation/file/Photos/player geometry/cancel/storage/device execution; overlay synchronization/orientation/VFR measurements |
| Automatic near-side hub identification and explicit manual fallback/loss/reacquisition | Original experimentalContourFrame/BarCandidateTracker/BarAnalysisService and manualVision | Seven synthetic tooling tests pass (~0.17s); tracker/clock/trace native tests allunrun | Representative real held-out near-side references/false-selection/occlusion/camera tests; device latency/RSS/thermal. Actual decoder failure evidence may require substantive detector revisions; no accuracy passed |
| Local evaluation/provenance/no private uploads | Manifest/prediction schemas, exactPTS scorer/hash guards and developer encoder source | Formal/semantic/hash/scoring/Windows-junction tests; empty run0observed/0bytes/gatefalse | Actual native encoder/hash/PTS fixture output and approved real media; scoring is supporting tooling, not semantic accuracy acceptance |
| Accessibility/error paths/privacy/release | Purpose/unit/set/error labels, Developer diagnostics separation; managed local copies/backup exclusion | Source/whitespace inspection only | VoiceOver, DynamicType/rendered contrast, privacy/storage/cancel, realiPhone/signing/TestFlight. No release artifacts |

Earlier import measurement118.13seconds/1,343,746,048SQLitebytes/337,502,208peakRSS is localhost diagnostic. Ranking first-page7.06seconds and later narrow~1second are confounded by cache/order; original serving query remains selected. No production throughput/capacity claim. All genuine read artifacts were preserved; this pack imports/profiles/prunes nothing.

## First diagnostics to return

Return runURL/reviewed Git revision, actualXcode/Swift/XcodeGen/OS/SDK, selectedSimulator/runtime, completed phase/exit codes, discovered/executed native test totals and first failure log/context. Return separate macOS core, iOS build, iOS tests statuses; do not collapse successful source/YAML checks into native success. Worker fixes concrete diagnostics locally before another authorized necessary run. Preserve logs privately and redact secrets/private media metadata before external sharing.

After compilation, use native-validation/accessibility-source-pass/native-service-recovery/native-prediction-export checklists. A Simulator build does not validate real iPhone Vision accuracy, memory/thermal, signing or AppStore readiness.

## Next substantive decision

No additional unblocked required implementation was identified by this consolidation beyond the already implemented source checkpoints. The concrete next work is actual Apple diagnostic repair, approved reachable deployment/scheduler, and measurements on authorized clips. Each needs an external prerequisite/target; another generic polish/test-repeat loop would not close those gates. Leader should obtain those decisions and dispatch the matching bounded implementation/measurement. Do not select a more complex detector/index or install/publish anything without that evidence/authorization.

Next native-result ETA is blocked on repository permission, runner allowance and dispatch; re-estimate once the job is queued/started or first diagnostics arrive. Jobhard30minutes limits a run, not research or release readiness. Automatic accuracy ETA is blocked on clips/native/device execution; re-estimate after the first reviewed baseline measurements. This document completed independently of those unresolved gates.
