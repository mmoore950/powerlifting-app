# Local trace/reference evaluation tooling

October 7, 2026. Executable Windows tooling now validates both schemas, checks selected local media bytes and scores separate prediction exports. **Zero observed clips, no native trace export or real accuracy evidence.** Synthetic tests establish tooling behavior only. No private media is fetched or uploaded.

## Install and run

Use the existing DataService development dependency installation (`pnpm --dir DataService install --frozen-lockfile`). Ajv8.20.0 is pinned as a development dependency in its package/lockfile; these root tools resolve that installation. It is not an iPhone or service runtime dependency. [Ajv's official Draft2020-12 documentation](https://ajv.js.org/json-schema#draft-2020-12) requires the separate2020 export; [options](https://ajv.js.org/options) describe strict validation and data mutation settings. This tool uses strict schema compilation, all errors, no coercion/default insertion/property removal. Package MIT license inspected locally and recorded in THIRD_PARTY_NOTICES.md. Schemas are repository-owned static files; validation makes no remote schema request.

From the project root:

```powershell
node tools/validate-video-manifest.mjs docs/video-fixture-manifest.json
node --test tools/video-manifest.test.mjs tools/video-scoring.test.mjs
node tools/score-video-traces.mjs --manifest docs/video-fixture-manifest.json --predictions docs/video-empty-predictions.json --asset-root artifacts --output artifacts/video-evaluation-empty.json
```

The actual empty run reports0clips/0observed,0hashedbytes, empty groups and `accuracyGatePassed:false`. Exit0 means the tooling command completed, not that tracking passed an accuracy gate.

For authorized local clips use populated private reference/prediction JSON files and an explicit private asset root. Keep them and output reports in ignored artifacts. No command scans for media automatically. Optional `--pixel-threshold` defaults10pixels and `--minimum-confidence` defaults0.5; they are explicit evaluation settings, not release acceptance or calibrated probabilities. Fix thresholds on development data before evaluating held-out clips.

## Input integrity and bounds

Reference format remains `video-evaluation.schema.json`; prediction format is `video-prediction.schema.json`, with an empty example in `video-empty-predictions.json`. References retain permission/source group/lift/split/target/provenance and actual presentation timestamps. Predictions contain model identity, clip hash, mode, synthetic flag, upright dimensions, elapsed processing time and ordered samples. Automatic and manual Vision runs are distinct. Manual reference annotations are forbidden prediction kinds.

Formal schema rejects missing/unknown fields, types, invalid enums/geometry. Semantic checks reject Int64 overflow, unsafe integer epochs, duplicate/unordered rational timestamps, hash/group leakage across partitions, target/provenance errors, prediction/reference hash/dimension mismatches, duplicate clip/mode runs and loss/point inconsistencies. Track-instance IDs are detector labels, distinct from the manifest's intended semantic target ID; matching those strings would falsely imply semantic bar identification.

References permit at most100clips/10,000annotations per clip; predictions at most200runs/10,000samples per run. CLI JSON inputs have a32MiB acceptance bound (also checked after buffering). That is not a hard total RSS bound. Each selected asset resolves via realpath under the explicit root; traversal/absolute/drive/alternate-stream paths are rejected and outside symlink/junction resolution fails. Streaming SHA-256 verifies a nonempty regular file, with500MiB per-file and4GiB whole-run byte limits and a60-second per-file cancellation timer. Before/after file size/modification checks detect ordinary concurrent changes. OS/filesystem cleanup can overrun the timer, and trusted owner-controlled filesystem is assumed; no adversarial race-proof path guarantee is claimed.

Hashing verifies bytes. It **does not decode media**, confirm dimensions/aperture/orientation or establish that timestamps came from native decoding. Reference permission/provenance claims require human evidence; the schema does not authenticate them. A byte/hash/validation failure throws before publishing a new report; any existing older report remains dated evidence, not a successful new run.

## Scoring definitions

- Match only exact rational value/timescale equivalence within the same epoch, using BigInt. A numerator above JavaScript's safe numeric range is preserved. No nearest-frame matching, interpolation or nominal-FPS clock is introduced. References should be annotated at the export's actual decoded timestamps; other prediction timestamps are counted as unreferenced and receive no invented ground truth.
- Visible reference with no exported sample is missing; a matching lost/null/low-score sample is an abstention. Both reduce coverage. A missing run yields explicit missing samples and null conditional error, not a perfect score.
- Accepted visible localization error is Euclidean distance in declared upright display pixels. Report mean, nearest-rank median/p95 and maximum only for accepted matched visible samples. Accepted coverage and within-threshold localization coverage use **all visible references** as denominator; conditional mean alone can hide abstentions.
- With annotation uncertainty radius `u`, report distance interval `[max(0,error-u),error+u]`, counts definitely within/outside threshold and overlapping it. Radius is supplied annotation uncertainty, not a statistical confidence interval. Pixel comparisons use1e-9epsilon for floating boundary arithmetic.
- Uncertain references are excluded from point accuracy. Occluded/outside-frame references separately count accepted assertions; these are not automatically labeled false positives. Semantic false selections require real reviewed labels/corpus design beyond this scorer.
- Track-ID changes between accepted matched visible samples are continuity diagnostics. Changes after loss/low score, epoch change, decoded time gaps over0.25seconds or ambiguous/unobservable/missing reference gaps are separately counted. Unreferenced lost samples still break continuity. Counts do not prove correct near-side identity or quantify reacquisition correctness.
- Reports keep every mode/split/synthetic group separate. Synthetic and development results are never pooled into held-out observed accuracy. No release acceptance thresholds, representativeness decision, thermal test or statistical uncertainty claim is applied; `accuracyGatePassed` remains false.

## Native export hook

`BarAnalysisResult` holds `VideoTrace` and one `BarFrameTime` for every accepted actual decoder sample, plus elapsed/gaps/mode and actual upright decoded dimensions. `VideoTrace` alone stores Double seconds and is insufficient for this exact-time evaluation. A developer-local source encoder now wraps that result; see `native-prediction-export.md`. It is not compiled/executed and has no broad product export UI.

A small developer-local encoder wrapper can produce one prediction run without changing detection:

1. Take a completed `analysisResult` plus explicit manifest clip ID, SHA-256 of the exact managed media bytes and matching upright clean-aperture display dimensions. Use a model ID identifying the detector revision/settings; it must not assert a validated model.
2. Require equal trace/timestamp counts, then zip each existing sample with its original `BarFrameTime`, preserving value string/timescale/epoch. Do not reconstruct times from Double seconds, request index or nominal FPS. Require all sample/time order and loss/identity conditions before encoding.
3. Map experimental automatic to `automatic` and manual Vision to `manual-vision`; emit existing sample kind/point/score/track identity, including null lost points. Reject manually annotated `manualReference` samples from predictions. Coordinates must refer to the same upright aperture as the reference, including mirroring/aspect.
4. Write the JSON to local diagnostics/share export only; no network or automatic upload. Compare file bytes/schema on an actual native run before calling it usable.

The hook is now implemented as source with six unrun native test methods, while the shared explicitly synthetic JSON fixture passes Node validation/scoring. Native capture/device memory/thermal evidence and real authorized held-out clips remain required; no reliable accuracy-readiness ETA until those inputs and first diagnostics exist.

## Actual checks

Six Node synthetic tests pass (~0.16seconds): schema/semantic failures; exact timestamps above safe integer plus mismatched epoch/neighbor frame; independent5-pixel3–4geometry boundary/uncertainty; missing/lost/uncertain/unobservable and ID/gap behavior; mode/split separation and empty corpus; real temporary-byte streaming hash/size/total checks, changed hash rejection before report publication and a real Windows outside-junction rejection. These synthetic bytes are not video fixtures. No Swift, XCTest, AVFoundation or Vision ran.
