# Next bounded task: hosted native validation preparation

Human confirmed no Mac is available. Use a hosted macOS/Xcode runner rather than waiting for personally owned hardware. [Official GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) lists macOS runner labels including `macos-15` / `macos-15-intel`; private jobs consume account allowance and can incur charges. Account/repository access and billing allowance are unverified. No remote, workflow run, public repository or billing action has been created.

Recommended next dispatch, Sol Medium, estimated 25–40 minutes for a **local configuration checkpoint**, no hard delivery deadline:

1. Prepare a manually dispatched `workflow_dispatch` workflow (no push/scheduled trigger), pinned supported macOS image and verified action SHAs, read-only repository permission, one job/concurrency limit, **30-minute hard job timeout**.
2. Capture runner, Xcode, Swift and XcodeGen versions; install/verify XcodeGen ≥2.46.0 as a development tool. Resolve the app manifest/local Swift package.
3. Run actual core XCTest via `swift test`, generate project, discover an available iOS 17+ iPhone Simulator UUID, unsigned simulator build/test with `CODE_SIGNING_ALLOWED=NO`.
4. Save console logs and `.xcresult` bundles even on failure; use bounded artifact retention. Include exact commands/versions in summary and avoid packaging public dataset ZIP/SQLite/video artifacts.
5. Validate YAML/commands locally as far as possible, then present that concrete configuration and the actual repository/allowance prerequisite before asking for any access/approval. Do not make the project public to obtain free runners or trigger billing by assumption.

Actual build completion/readiness cannot be estimated reliably before runner access and first execution. The 30-minute job timeout is a proposed bound, not expected successful duration. First real diagnostics determine repair work. Simulator compilation/testing does not prove iPhone video accuracy, real-device memory/thermal behavior, signing or TestFlight readiness. Continue independent data work while this access gate is unresolved.

## Prepared configuration — October 7, 1:07 PM ET

Local `.github/workflows/native-validation.yml` is now reviewable. It has only `workflow_dispatch`, repository contents read permission, credential persistence disabled, one macos-15-intel job, a repository-wide concurrency group, and a 30-minute job timeout. OS label is fixed; GitHub updates its image/Xcode contents, so this is not an immutable runner image. Setup logs record actual Xcode/Swift/SDK/OS versions.

Action pins verified against upstream tags with `git ls-remote`:

- checkout v4.3.1: `34e114876b0b11c390a56381ad16ebd13914f8d5`.
- upload-artifact v4.6.2: `ea165f8d65b6e75b540449e92b4886f43607fa02`.
- XcodeGen 2.46.0 release ZIP: SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`. Verified using GitHub release API digest and an actual downloaded local ZIP. Runner downloads that same version, checks the digest before executing and logs its version. Development tool only; not bundled in the app.

`tools/ci/native-validation.sh` runs macOS `swift test`, XcodeGen generation, actual available iPhone/iOS17+ simulator selection, unsigned simulator build and scheme test. `select-simulator.py` rejects unavailable devices/runtimes and picks a deterministic candidate from simctl JSON, preserving the selected UUID/version. No hardcoded simulator name or assumed runtime installation. Lack of a candidate fails explicitly.

Logs, selected simulator JSON, phase exit codes and build/test xcresult bundles are uploaded with three-day retention on ordinary success/failure. Only `artifacts/native-ci/` is selected; no dataset ZIP/SQLite/private video paths. Upload is best effort: hard job timeout/cancellation/runner failure can prevent cleanup steps, and failed builds may not produce a result bundle. Download Actions' console logs in those cases. An explicit failure is not a passed gate.

ACTUAL Windows checks: actionlint 1.7.12 passes workflow syntax/expressions (shellcheck/pyflakes disabled because unavailable); Git Bash `bash -n` passes shell syntax; Python synthetic simulator selection excludes iPad, iOS16, unavailable runtime/device and errors with no candidate; ZIP checksum/archive layout verified; `git diff --check` passes. No XcodeGen generation, Swift tests or Apple build was executed here. The generated package-test scheme syntax was checked against XcodeGen 2.46.0 ProjectSpec; runtime behavior remains a first-run gate.

## Account and repository prerequisites / exact next execution

1. Leader reviews these local files. There is no remote and no committed history yet. Select a human-authorized GitHub repository/destination and visibility; keep datasets, videos and ignored artifacts out of the source commit. Do not make it public to obtain runners by default.
2. Confirm write access to save source/workflow on that repository's default branch, Actions enabled, workflow/action policies permitting the two pinned official actions, permission to dispatch, macos-15-intel availability, and sufficient approved Actions minutes/artifact allowance. Do not assume billing allowance or add a payment method. A normal GitHub account/repository is sufficient for unsigned simulator work; no Apple signing secrets are required.
3. After authorization/access are established, commit/push the reviewed source and workflow. In GitHub Actions choose **Native validation (manual)** → **Run workflow** and the reviewed branch. With authenticated GitHub CLI the equivalent is `gh workflow run native-validation.yml --repo OWNER/REPOSITORY --ref REVIEWED_BRANCH` (replace both explicit placeholders). Workflow file must be present on the default branch for manual dispatch availability. Do not execute that command before authorization.
4. Inspect all three gates separately: macOS core tests, unsigned iOS build, iOS scheme tests. Download the diagnostic artifact/console logs. Record actual versions, run URL, gate status and first failing diagnostics. Fix source errors locally and rerun only the necessary gate; bounded job duration does not guarantee passing.

Configuration completed earlier than the original 25–40 minute estimate. The next native result has no reliable ETA until repository access/allowance and dispatch are available; runner queue and actual toolchain compatibility are unknown. A new estimate can be made at first run/diagnostics. Continue the preauthorized native data source integration while that gate is pending.
