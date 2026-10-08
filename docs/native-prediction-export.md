# Native prediction encoder source checkpoint

October 7, 2026. Added a developer-local encoder hook, not a new product export screen. **Source only: no Swift compilation, XCTest, native hashing or media decoding ran.** The shared contract fixture is synthetic and was checked by Node; it is not captured native output.

## Source connection

- `LiftingCore/VideoPredictionExport.swift`: immutable Encodable rational PTS, prediction samples/runs/envelope. Values serialize as decimal strings; ordering uses signed full-width products to avoid Int64 cross-multiplication overflow. Epochs must fit a safe JSON integer; the current native trace/export accepts epoch0, matching VideoSampleClock's decoder policy. Exact Double seconds equality checks that the original PTS/sample arrays are paired; it never reconstructs PTS from those seconds.
- `BarAnalysisService`: records actual upright decoded CGImage width/height and rejects a dimension change. These are the bounded clean-aperture decoded image dimensions, not unverified natural video dimensions or phone screen size. Reference annotations must use that same upright aperture/declared dimensions.
- `BarPredictionExporter` actor: reads the captured managed file with128KiB chunks, hashes via CryptoKit SHA-256, compares explicit expected manifest hash, checks ordinary size/modification changes, then builds the envelope with actual result mode/dimensions/elapsed and original BarFrameTime. File bound500MiB, cooperative elapsed guard60seconds, cancellation checks between synchronous reads; in-flight file operations/cleanup can overrun. No network URL or implicit source scan is accepted.
- `VideoModel.predictionJSON(context:)`: snapshots completed analysis/media, awaits the actor and rejects after cancellation, clip generation change, new analysis, clear/remove/trim change or processing restart. Returns Data so an obsolete result is rejected before any caller publishes it. No automatic file write, upload or broad UI was added.

Caller supplies `BarPredictionContext(clipID:expectedSHA256:modelID:synthetic:)` explicitly. Clip/model/provenance have no guessed defaults. The expected hash must be the exact managed media bytes associated with the manifest. Model ID identifies the actual detector revision/settings; the encoder does not certify revision or human permission evidence. `synthetic:false` is a caller assertion that requires real native/media/reference evidence; this checkpoint emits no observed run.

Example developer invocation, **not executed here**:

```swift
let context = BarPredictionContext(
    clipID: manifestClipID,
    expectedSHA256: manifestMediaSHA256,
    modelID: recordedDetectorRevisionAndSettings,
    synthetic: manifestIsSynthetic)
let data = try await videoModel.predictionJSON(context: context)
// Developer selects a private local diagnostics destination after this succeeds.
try data.write(to: selectedLocalDiagnosticsURL, options: .atomic)
```

The caller is responsible for a private local destination and retaining dated metadata. The application hook returns data only. Run the exported JSON through `score-video-traces.mjs` with the matching private reference/root. Hash checks do not by themselves establish actual native timestamps, correct geometry or semantic target identity; actual Apple execution remains the gate.

## Validation and source tests

Envelope/run constructors reject empty/invalid metadata, malformed hash, unsupported dimensions, nonfinite duration, duplicate clip/mode, zero or unequal timestamp/sample counts, >450samples, unsupported epoch, unordered/equivalent rational timestamps, mismatched sample time, manualReference prediction kinds, missing accepted track identity and manual-mode automatic labels. Explicit lost point/identity null keys match the JSON Schema. Foundation timestamp helper preserves Int64 strings, including values above JavaScript's safe integer range; such standalone helpers do not imply the bounded native decoder accepts those playback times.

Four package XCTest methods cover original PTS/null JSON and shared fixture, full-width ordering/duplicate scales/epoch guards, count/time/mode/manual/identity failures and explicit metadata/unique-run guards. Two app XCTest methods use synthetic temporary bytes for expected-hash/change rejection and mode/schema metadata. **All six are unrun.** App-host test target sources already include Tests/App; package Fixtures resource already includes the new file.

Actual Windows checks: seven local Node evaluation tests pass (~0.17seconds), including `Fixtures/video-prediction-synthetic.json` formal/semantic/scoring contract; git whitespace passes. No claim that the Swift encoder produced that fixture or passed its own tests. Official Apple [full-width multiplication](https://developer.apple.com/documentation/swift/int64/multipliedfullwidth(by:)) and [bounded synchronous file read](https://developer.apple.com/documentation/foundation/filehandle/read(uptocount:)) Markdown API signatures inspected. Native API/isolation/cancellation/file behavior remains unverified until the first Apple diagnostics.
