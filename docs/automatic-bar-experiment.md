# Automatic bar candidate experiment

October 7, 2026. This checkpoint contains native source, not executed detection or measured bar identification accuracy. No Swift compiler, AVFoundation/Vision execution or observed evaluation clips are available in this Windows workspace.

## Modes and implementation

The Bar path screen has two explicit modes. **Experimental automatic** runs an original native contour/geometry and temporal candidate baseline without a user seed. **Manual Vision** requires a reference point at rep start and follows that user-selected region with VNTrackObjectRequest. Manual references and manually initialized tracking cannot satisfy the automatic identification gate. Videos remain in the app's local managed storage; no model weights, private uploads or inference services were added.

`BarAnalysisService` processes one generated upright image at a time. AVAssetImageGenerator applies the preferred track transform and explicitly uses clean aperture, including pixel aspect ratio. Vision receives the resulting image with `.up` orientation. Vision's bottom-left coordinates are converted into upright, normalized top-left coordinates. Playback overlay uses the actual AVPlayerLayer.videoRect. Rotated/mirrored, anamorphic and clean-aperture media still need native alignment checks.

Requests are spaced at 15 per second, but observations use the generator's **actual presentation timestamp**, never a nominal frame number. The returned value/timescale/epoch ledger preserves rational timestamp components. Unsupported epochs/scales throw; duplicate, backwards and out-of-trim observations are skipped. Decoder failure stops the run and preserves the previous completed trace. There is no invented observation at a requested time when decoding fails.

## Candidate evidence and abstention

`ContourFrame` uses native Vision contours and bounded original geometry: outer circularity at least 0.65, aspect at least 0.4, radius between 3.5% and 35% of the shorter image dimension, and a centered nested hub with radius ratio 0.04–0.35 and circularity at least 0.55. The hub center is the reported point; outer radius, aspect, hub ratio and mean RGB provide appearance evidence.

Background contour landmarks vote for median scene translation, excluding candidate regions. At least eight coherent matches, 80% agreement and horizontal/vertical spatial spread are required. Unreliable scene evidence, translation over the allowed normalized range, or frame gaps over 0.25 seconds discard initialization/identity and emit a missing sample. This translation baseline cannot reliably explain camera rotation, zoom, parallax or moving backgrounds.

`BarCandidateTracker` requires six consistent frames within a 1.2-second evidence window, scene-compensated movement of at least 0.015, net displacement at least 0.012 and directional coherence at least 0.6. Multiple qualified moving candidates require 1.35 radius dominance; otherwise the system abstains. Association also abstains on nearly equal alternatives. Size dominance is a heuristic for the near side, not semantic proof of a bar. Moving circular distractors can still be selected, and valid bars can be missed.

After initialization, radius/aspect/hub/color compatibility and bounded motion prediction must identify exactly one candidate. Loss and competing matches emit explicit gaps. Reacquisition needs three consecutive unique matches; identities expire after 0.75 seconds without an accepted observation. A new identity, missing sample, low score or excessive time gap breaks the rendered line. No extrapolated point is drawn during loss. Scores are uncalibrated geometric evidence, not probabilities of correct bar identity.

Manual Vision uses a local seed box, accurate tracking and a 0.6 observation confidence threshold. Loss is sticky until the user explicitly restarts; it does not silently reacquire. Vision confidence describes tracker evidence, not automatic semantic identification. Manual and automatic results retain their labels.

## Bounds and cleanup

- Selected rep at most 30 seconds; imported clip duration at most 30 minutes.
- At most 450 decoding requests/accepted samples; image output at most 1024 by 1024; contour request dimension 512.
- At most 128 starting contours, 256 inspected contours, 16 children per traversal/hub check, 512 sampled points per contour, 64 candidates and 80 background landmarks. Apple's internal decoder/Vision allocations are not measured or hard memory limits.
- A 120-second elapsed guard is checked between iterations. This is **cooperative**, not a guaranteed wall-clock cutoff: an in-flight Apple operation can overrun it. Cancellation requests cancel image generation/current Vision work; their response time is unmeasured.
- Single analysis per service; progress and results guarded by run/clip generations. Replacing/removing a managed clip waits for analysis cleanup before deletion. Leaving the tab/background cancels analysis. Cancellation/errors retain the previous completed trace and discard incomplete output.

No distance, velocity, technique or medical claims are produced.

## Evidence and remaining gates

Added seven BarCandidateTracker and two VideoSampleClock XCTest **source** methods for stationary/camera-only distractors, competing moving candidates, appearance/ambiguity loss, camera-shift accumulation, reacquisition/expiry, identity breaks, malformed evidence and actual VFR timestamp/resource bounds. Existing four VideoTrace test sources cover transforms, fit and explicit gaps. **None has run.** Windows semantic evaluation-manifest validation and its synthetic guard test pass with zero observed clips; they do not execute this detector.

The deliberately empty `video-fixture-manifest.json` is the starting ledger, with reference schema and provenance/split requirements in `video-evaluation-manifest.md`. Native compilation/test diagnostics come first. Then authorized representative local squat/bench/deadlift clips must measure automatic initialization/false selections, hub error, identity switches/reacquisition, abstention, alignment, duration, peak memory and thermal behavior on held-out clips. Thresholds remain development choices until those measurements exist. No reliable accuracy-readiness ETA exists; it can be re-estimated after clips and the first native results are available.

## Reference and license decisions

The foundation research inspected MIT Marticles/barbell-path-tracker at `501daea5c0666b3564fadbbebb51e6f6ac0b2428` (manual box initialization) and cluffa/BarTracking at `cd415ca757fbef682943885333b65676ec2ee006` (contour/segmentation reference with unresolved source/model rights). No code/model from those repositories was copied. The original native heuristic avoids depending on unlicensed weights; it does not establish equivalent performance. See `video-foundation.md` and `open-source-research.md`.

Apple primary API documentation was fetched as Markdown on October 7: [image generation](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/image(at:)), [aperture mode](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/aperturemode-swift.property), [clean aperture](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/aperturemode-swift.struct/cleanaperture), [contours](https://developer.apple.com/documentation/vision/vncontour), and [tracking](https://developer.apple.com/documentation/vision/vntrackobjectrequest). API documentation is not runtime validation.
