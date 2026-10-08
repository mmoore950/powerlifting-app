# Local video foundation and automatic localization handoff

October 7, 2026. Source checkpoint only; no AVFoundation playback, Swift tests or real tracking accuracy measured.

This records the initial import/playback/manual-annotation foundation. The subsequent experimental automatic and separate manual Vision pipeline source is documented in [automatic-bar-experiment.md](automatic-bar-experiment.md); its native execution and real accuracy remain pending.

## Implemented source

Bar path tab imports a user-selected video from Photos Picker or Files into private Application Support. Security-scoped Files access covers copying; temporary Photos transfers are copied before their transient URL disappears, then removed. Managed copies are excluded from backup. Per-file500MiB, managed-directory1GiB, duration30minutes and transformed image8192pixel guards reject unsupported imports. Metadata checks playability and orientation. Failed/cancelled staging copies are removed. Original videos remain unchanged. Replace/remove/clear actions remove only UUID-named managed copies, with a clear action for abandoned copies after interruption. No upload or inference service is added.

Playback uses AVPlayerLayer, explicit seek/play/pause and a selected rep capped at30seconds. Periodic observation tokens are paired with removal on replacement/destruction. Generation guards reject old-player/import callbacks; playback errors are exposed. Play waits for seek completion when returning to rep start. Switching tabs/background pauses. Initial import and reference points are session state, not a persisted video library.

Canonical trace coordinates are normalized in the upright displayed image, origin top-left. The domain models validate point/sample/range decoding, monotonic asset timestamps, sample count, confidence and explicit missing observations. Vision bottom-left conversion is separate and only applies after orientation has been resolved. Preferred affine transformation handles translation, rotation/mirroring and rejects singular geometry. UI overlay/taps use the actual ready AVPlayerLayer.videoRect, avoiding guessed clean aperture/pixel aspect behavior. Black-bar taps do not produce image points.

The user can pause/tap manual **reference annotations** at the player's current asset time. They are not automatic detection or a tracker. The app shows no synthetic path as real output. Trace rendering stops at playback time and breaks across lost/low-confidence/time-gap samples; it never interpolates fabricated continuation. Native tests sources cover rotated/mirrored/letterboxed geometry, invalid decoding/ranges, monotonic timestamps and explicit gaps. These tests have not run. No distance, velocity or technique claims are computed.

## Focused automatic localization recommendation — for Sol High dispatch

Keep native on-device AVFoundation/Vision interfaces. First establish a bounded frame sampler using actual presentation timestamps and upright orientation, then evaluate automatic near-side plate/hub candidates separately from following an initialized target. Prefer a small native candidate baseline before introducing model weights of unresolved rights. Vision tracking can support a manually initialized fallback; that must remain labeled and cannot pass the automatic gate.

References re-inspected/pinned:

- Marticles/barbell-path-tracker MIT at `501daea5c0666b3564fadbbebb51e6f6ac0b2428`: tracker.py records bounding-box centers after user box initialization. Adapt the workflow/evaluation baseline; no copied Python dependency/code. It does not automatically identify a bar.
- cluffa/BarTracking at `cd415ca757fbef682943885333b65676ec2ee006`: segmentation, contour/ellipse-center approach and competition-domain bias are relevant. Root/model licensing remains unresolved; do not vendor its ONNX files/source. A native geometric candidate baseline is an original evaluation candidate, not proven accuracy or equivalent segmentation.
- Apple's AVPlayer periodic-time-observer documentation requires paired removal; AVPlayerLayer.videoRect is the actual video display rectangle. CoreTransferable FileRepresentation documents transient file copying. Markdown API docs were fetched with PowerShell because web rendering requires JS. No runtime validation is inferred from documentation.

Proposed High task: design/implement bounded sample/observation interfaces and an automatic candidate baseline (contour/circularity/temporal coherence/near-side ambiguity), plus Vision fallback initialization/tracking. Confidence must represent explicit heuristic evidence rather than fabricated probability; ambiguous competing candidates and occlusion produce a gap/request for correction. Reject far-side/wall/rack circular distractions. Reacquisition needs consistency checks before extending a path. Use async cancellation and resource guards; prohibit private video upload.

## Real evaluation gate

Need representative locally authorized squat/bench/deadlift side-angle clips with different plates/backgrounds/lighting, rotated/mirrored video, VFR, camera motion, partial occlusion and multiple circular distractors. Keep clips/device local. Build frame/timestamp reference annotations for near-side hub, visible/occluded state and target identity. Include holdout clips; do not tune thresholds and report accuracy on the same clips alone.

Measure automatic initialization success/false target selection, normalized/pixel center error, lost frames/drift, reacquisition identity switches, overlay alignment, processed/asset timestamps, processing duration/peak memory and device thermal behavior. Separate manually initialized tracking from automatic initialization. Agree acceptance thresholds after inspecting clip resolution/annotation uncertainty and baseline errors; no invented universal success threshold. Synthetic traces validate geometry/gaps only.

Next source result can be estimated after focused High dispatch; automatic readiness cannot be estimated reliably without licensed representative clips and first native measurements. Hosted CI job timeout30minutes is a build bound, not a tracking-readiness ETA. Current foundation took about15minutes, ahead of its30–50minute source estimate. Continue authorized independent finite-refresh harness while detector reasoning/access gates are addressed.
