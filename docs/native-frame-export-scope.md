# Authoritative native annotation frames: source-only scope

October 8, 2026. This is the accepted preimplementation audit/proposal, retained as the scope record. Implementation source and actual verification are now recorded in [status.md](status.md); developer invocation and native bundle fields are in [local-annotation-guide.md](local-annotation-guide.md). No media upload, workflow change or CI dispatch was performed for this source checkpoint. Apple execution and offline browser acceptance remain pending independently.

## Smallest authoritative capture point

Current `App/BarAnalysisService.swift` creates AVAssetImageGenerator with preferred-track transform, clean aperture, maximumSize1024x1024 and zero requested tolerances. Line70 receives the returned CGImage/actualTime; lines76–77 let the existing VideoSampleClock accept it or skip a duplicate/out-of-range result. The detector consumes that same image and accepted time; line112 records original integer CMTime components.

Add an **optional developer-only capture sink, default nil**, immediately after `clock.accept` succeeds and before detector processing. Encode that exact `frame.image` to PNG inside the analysis actor/autorelease pool, retaining no CGImage across an actor boundary. Pair it with `BarFrameTime(value: String(actualTime.value), timescale: actualTime.timescale, epoch: actualTime.epoch)`, the returned width/height and an ordinal ID. Send only immutable PNG `Data` and Sendable scalar metadata to a bounded local writer. No second decode, seek, nominal-FPS reconstruction or independent sampler is needed.

This location captures the actual detector input for every accepted observation, including observations that later abstain. Requested times may be recorded as diagnostics, but they cannot replace returned PTS. If detector processing fails after a captured frame, the bundle stays incomplete; no valid completed ledger is published. Default analysis skips PNG encoding/writing entirely and keeps its existing behavior.

Apple's [Image I/O destination API](https://developer.apple.com/documentation/imageio/cgimagedestination) supports adding a CGImage to a mutable-data destination. The encoder must check [finalization success](https://developer.apple.com/documentation/imageio/cgimagedestinationfinalize(_:)) before treating the bytes as an image. Official Markdown signatures were retrieved; no Swift signature/isolation compilation is claimed here.

## Proposed writer and contract

An explicit developer context supplies clip ID, expected media hash, source group/split, permission evidence, lift/target, synthetic flag and a new local destination. Reuse the existing BarPredictionExporter streaming SHA-256/size/modification/cancellation policy; do not invent identity or inspect a folder. Keep media hash tied to the same managed URL and verify before/final publication. The existing500MiB/60s hash policy is cooperative, not an external filesystem timeout.

The writer creates a fresh private diagnostic directory, refuses overwrite/traversal/network URLs, and writes numbered PNGs plus hashes. Initial proposal: selected range <=1 second, <=16 accepted frames and <=32MiB total PNG payload, within the existing <=450frames/30second/120second analysis limits. These developer capture limits bound the first seam without changing default analysis limits. Later larger bundles need explicit measured sizing; no budget expansion is proposed now.

Complete a ledger only after:

- Analysis returned successfully, was not cancelled, and still belongs to the same clip/analysis generation.
- Captured frame count/order/exact rational PTS equal `BarAnalysisResult.timestamps` and its paired trace samples.
- Every PNG reopens with the captured upright dimensions; byte hashes match and dimensions remain consistent.
- Source hash and caller-provided clip metadata validate; the destination remains new and local.

Use the existing `VideoModel.predictionJSON(context:)` generation-check pattern if the model exposes completion. A sink invoked by a developer test can finalize directly against its returned result; a future model entry point needs generation guards before publishing. Incomplete directories can be retained as recoverable diagnostics, clearly without a valid ledger; never silently relabel them as completed bundles.

Record producer `AVAssetImageGenerator`, actual configured transform/aperture/size/tolerances, OS/toolchain/revision, actual accepted PTS/dimensions and association with the same prediction result. **An authoritative native bundle is a distinct producer contract.** Extend the adapter/browser only after review to accept that contract and verify its image hashes, source identity and exact result association. Do not flip PyAV's `nativeParityVerified:false` flag or silently scale/reuse Windows coordinates to force a match. User labels should be made on the captured native images; matching geometry alone does not establish cross-decoder content parity.

Likely changes: optional sink in `BarAnalysisService`, one `BarFrameBundleExporter`/capture value type, focused app-host tests, a native-producer branch in the current frame-ledger validator/UI/adapter, and guide/status. No detector changes, generic video-reader replacement, product export screen or training pipeline.

## Meaningful Apple gate

Reuse the existing app-host test target and tiny synthetic AVAssetWriter approach, keeping existing defaults/30s encoder deadline. For capture tests, explicitly generate30fps frames matching the15Hz request grid. Current lifecycle fixture is10fps with three frames; it proves import/decode, not this sampling path. Do not weaken production zero tolerances to make a test pass.

1. **Actual rotated native capture:** asymmetric synthetic raster with explicit rotation; run the production analysis path with capture. Reopen the PNG, verify returned dimensions/pixel orientation and exact accepted PTS/count against the completed prediction result, including abstentions. Derive assertions from actual returned CGImage dimensions, never natural track size. Synthetic marks remain synthetic evidence.
2. **Actual size-limited capture:** small-duration wide fixture above1024pixels; show PNG and detector-input dimensions coincide and both fit the maximumSize. Verify no extra PNG orientation/resizing transform. Record actual returned dimensions rather than guessing rounding behavior.
3. **Default/failed/stale capture behavior:** default nil creates no diagnostic files; cancellation/writer failure/clip replacement cannot publish a completed ledger, and previous completed bundles/source bytes remain intact. Exercise bounded count/bytes rejection without encoder-failure-as-product-failure confusion.

Use existing pure clock/export tests for equivalent rational timestamp and large Int64 helper rejection/preservation; those helper values do not imply the native playback range accepts huge times. This seam cannot pass an accuracy gate: a synthetic contour observation or all-abstained trace has no real hub reference truth.

## Execution options and timing

| Route | What it can establish | Access/privacy condition |
| --- | --- | --- |
| Existing hosted macOS/iOS simulator CI, generated fixtures only | Apple compilation, Image I/O/native capture geometry/PTS and bounded lifecycle behavior | Leader reviews implementation and dispatches a later run. No media acquisition/upload needed for this gate. No workflow run in this scope. |
| Later opt-in native public-clip pass | Actual source hash/native accepted frames on the approved licensed H.264 MyDeadlift sample | Separate review of explicit asset URL/hash/attribution, bounded runner download/output and artifact exposure. No real labels or accuracy without human annotation. The local Commons H.264 derivatives need an approved transfer route or reproducible native-host preparation; this scope does not upload them. |
| User-authorized local Apple host or device diagnostics | Private source → authoritative images/labels kept locally | User has no Mac currently and no private folder was supplied. Do not upload private clips to CI or assume signing/device access. A host/access choice is needed before a private native ETA. |

Implementation source checkpoint estimate **35–60 minutes after approval**, no hard implementation deadline; uncertainty is Swift actor isolation, PNG write/finalization ownership and actual generator behavior. First Apple run estimate **10–18 minutes after runner start**, based on the last successful11minute job, with queue/encoder/simulator uncertainty. Existing hard simulator test10minutes and whole job30minutes (queue excluded), synthetic writer30seconds and analysis120seconds remain distinct. Capture/hash checks are cooperative and may overrun an in-flight native or filesystem operation.

Source scope completion is the next review decision, not native readiness. A reliable private/native-annotation readiness estimate is unavailable until the browser correction/request gate and authorized Apple capture access pass; re-estimate after the first actual capture result. Representative accuracy, device behavior and hosting remain separate gates.
