# Powerlifting App

Native SwiftUI iPhone source, minimum iOS 17. Working display name: Lift Toolkit.

## Current source slice

Forward/reverse loading, finite lb/kg inventories, configurable bar/collars, independent display/plate units and per-side diagrams. Training/Attempts add named rep-max estimates, loadable warm-ups and backward planning with persisted equipment. Competition source adds a configurable data client, saved offline pages, search/history and filtered best performances; see `docs/native-data-integration.md`. Bar path source adds local import/playback, experimental automatic candidates and separately labeled manual Vision tracking; see `docs/automatic-bar-experiment.md`. Native execution, reachable service, continuing freshness and real video accuracy remain gates.

**No Swift compiler or Xcode is available in the current Windows workspace. The app has not been compiled or run.** The checks below distinguish specification evidence from actual native execution.

## Structure

- `App/`: SwiftUI views and screen state.
- `Packages/LiftingCore/`: Foundation-only domain library, XCTest source, shared numerical fixtures.
- `project.yml`: XcodeGen project and scheme specification; generated Xcode files are ignored.
- `tools/`: Windows-compatible fixture and public-source inspection tools.
- `DataService/`: runnable local streaming ingestion, immutable SQLite snapshots and JSON read API.
- `docs/`: product, coordination, architecture, research gates and validation checklist.

## macOS build gate

The user has no Mac. Hosted validation preparation is documented in `docs/hosted-native-build-plan.md`; no Apple build has run yet.

Use a Mac with Xcode 16 or newer, its command-line tools, and an iOS 17+ Simulator runtime. The bundle identifier is a development placeholder. Personal device installation requires configuring your Apple signing team in Xcode; no credentials are stored here.

```sh
cd /path/to/powerlifting-app
xcodebuild -version
swift --version
brew install xcodegen
xcodegen --version
# Manifest requires XcodeGen 2.46.0 or newer.
swift test --package-path Packages/LiftingCore
xcodegen generate --spec project.yml
xcodebuild -list -project PowerliftingApp.xcodeproj
xcrun simctl list devices available
```

Choose an available simulator UUID from the last command, then:

```sh
xcodebuild -project PowerliftingApp.xcodeproj -scheme PowerliftingApp \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PowerliftingApp.xcodeproj -scheme PowerliftingApp \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
open PowerliftingApp.xcodeproj
```

The package's `swift test` is the direct core-test gate; the generated scheme also names its package test target. These instructions and scheme have not been executed here. Resolve any Apple-toolchain diagnostics and record exact Xcode/Swift/XcodeGen versions before declaring native validation. Follow `docs/native-validation.md` on Simulator and an iPhone.

XcodeGen is a development tool, not an app runtime dependency. See its [usage documentation](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/Usage.md).

## Available Windows evidence

From `C:\codex\powerlifting-app` in PowerShell:

```powershell
node tools/check-fixtures.mjs
node tools/check-training-spec.mjs
.\tools\inspect-opl.ps1
# Optional bounded archive inspection (up to 200 MiB, 60-second download timeout):
.\tools\inspect-opl.ps1 -Download
```

The Node checks independently enumerate combinations and verify specification arithmetic/ordering. They do **not** execute the Swift implementation, persistence codec, XCTest, or iOS UI. The source inspection downloads public upstream data into ignored `artifacts/`, reads its header without extracting the full CSV, and records metadata. It is research tooling, not the recurring production ingestion service.

See `docs/calculator-decisions.md` for formula conventions, preset assumptions, rounding and persistence. FineGym's MIT notice is preserved in `THIRD_PARTY_NOTICES.md` and bundled into the app's native notices screen.

## Local OpenPowerlifting service

See `docs/data-service-runbook.md` for locked dependency installation, import/refresh/query commands, measured full-dataset evidence and limits. Run `node --test DataService/test/service.test.mjs` for executable data integration checks. The service has imported a genuine full snapshot; continuing scheduled freshness and native browsing remain acceptance gates.

## Local video evaluation tooling

See `docs/video-scoring.md` for formal reference/prediction schema validation, bounded local media hashes and exact presentation-timestamp scoring. Run `node --test tools/video-manifest.test.mjs tools/video-scoring.test.mjs` after installing pinned DataService development dependencies. The empty corpus reports accuracy unmeasured; synthetic tests do not validate native tracking. Generated native capture executed on Apple CI, including all four capture methods and stronger attachment/raster assertions at exact `cd3a34c`; that run failed during UI startup and skipped attachment export. Actual native-to-wrapper output, private-use acceptance and a product export control remain pending. See `docs/status.md`, `docs/local-annotation-guide.md` and the proposal in `docs/portable-native-capture-scope.md`.
