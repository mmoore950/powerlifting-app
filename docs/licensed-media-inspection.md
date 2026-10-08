# Licensed media acquisition and feasibility inspection

October 8, 2026, America/New_York. Exactly four approved small originals acquired into ignored `artifacts/licensed-media-inspection/originals`; total **2,205,257 bytes**. No media committed/uploaded or added to CI. These are development candidates, not held-out accuracy evidence. The reference manifest remains empty: zero manually annotated/scored clips.

## Actual acquisition and bytes

Exact asset/source/license URLs and attribution are in [the research document](evaluation-assets-and-zero-cost-hosting.md); the local `asset-provenance.json` repeats them with original bytes, digests, source grouping and development-only intent.

| Original | Bytes | SHA-256 | Publisher check |
| --- | ---: | --- | --- |
| MyDeadlift `GB_S01_R01.mp4` | 804,132 | `00ac077b0468064837f37d627867d975c4d89923da1879a9c23d61449eb807db` | Matches sample page SHA-256; CC BY 4.0 |
| Commons squat | 564,942 | `2440985661c3533a4ce78472b0f4577dbdf023aff3f8f9a225bbb5ff8071b1e9` | SHA-256 computed; no publisher SHA checked; CC BY 3.0 |
| Commons bench | 389,315 | `4b843d33d7b439884ed64d722edc6c7c46a3430060d4e2059f42b103e9187be7` | Publisher SHA-1 `619a8ca8c5ad851bb6b7d1775f8babefd478e623` matches; CC BY 3.0 |
| Commons deadlift | 446,868 | `d7870f6d8abfde8d7daf2c97252738e89617a03eda7f9a4c4adbf7996e6c9c1f` | Publisher SHA-1 `b551a2420b838299eb39185bfe77bec4ddfc33f5` matches; CC BY 3.0 |

One Commons deadlift request returned HTTP 429; a subsequent single sequential request succeeded. Existing successful files were retained. Originals were not altered. Attribution: MyDeadlift authors Ivan Conanta/Gloria Virginia, dataset v1/DOI; Commons FitnessScape/asset titles/Half Rack Workout and excerpt uploader Prototyperspective. Preserve credit/source/license/change notices for any future redistribution. Local acquisition does not authorize CI publication by itself under this project dispatch.

## Decoder and inspection evidence

No existing FFmpeg/PyAV/OpenCV decoder was located. Leader approved isolated prebuilt PyAV provisioning, without system/PATH changes or source compilation. Bundled Python 3.12.14; `av==19.0.1`, prebuilt `av-19.0.1-cp312-abi3-win_amd64.whl`, **28,149,519 bytes**, SHA-256 `906fc3db09288319a75ea23ffefb59961c7dbe0d1c074601507a89de7d8593d8`, verified against [official PyPI metadata](https://pypi.org/pypi/av/19.0.1/json). Tool/packaged-library provenance retained in `tooling-provenance.json`; tooling is ignored local research material, not an app dependency. [PyAV documentation](https://pyav.basswood.io/docs/stable/api/frame.html) describes frame PTS/time bases. FFmpeg library versions are recorded locally.

Actual Windows decode completed for **all 768 original video frames**, with per-frame exact integer PTS, rational time base, rotation and side-data types written to `inspection/*-frames.json`. Chronological contact sheets every third decoded frame (10 sampled frames/second) cover the whole assets; all four sheets and full-resolution detail frames were visually inspected. This inspects movement over complete sequences, but is not exhaustive per-frame hub labeling or a claim that every brief occlusion was reviewed. No approximate browser playback time supplied the timestamp data.

| Asset | Actual video and orientation | Actual presentation timeline | Motion/suitability observations |
| --- | --- | --- | --- |
| MyDeadlift | H.264/yuv420p, **480×848 portrait**, 120 frames; AAC audio; decoded frame rotations all 0 | `1/90000`, first PTS 0, last 357000 = 119/30 s; 119 deltas exactly 1/30 s. Video stream 4 s; container 4.041875 s includes audio timing. | One lifting/lowering sequence, side view with slight obliquity, near-side small open-grip plate/hub visible in inspected frames. Busy gym/background people and circular plates provide distractors. Best initial native decode/development candidate; low resolution and one subject/session limit coverage. |
| Commons squat | VP9/yuv420p, 1280×720, 213 frames, no audio; rotations all 0 | `1/1000`, PTS 0…7067; 141 deltas 33 ms, 71 deltas 34 ms | Two squat cycles, rear oblique view, both plate ends/rack visible. Near-side plate on image right remains identifiable in sampled sequence; low position/text overlay approaches lower plate region. Far-side plate is a competing circular target. Useful oblique/distractor case, not perpendicular side-view validation. |
| Commons bench | VP9/yuv420p, 1280×720, 213 frames, no audio; rotations all 0 | `1/1000`, PTS 0…7067; 141 deltas 33 ms, 71 deltas 34 ms | Repeated presses, oblique foot-side view. Near-side right hub is visually identifiable in sampled sequence; rack/second plate compete. Text overlay lower right. Useful multi-target development footage; repetition boundaries are edited and require annotation. |
| Commons deadlift | VP9/yuv420p, 1280×720, 222 frames, no audio; rotations all 0 | `1/1000`, PTS 0…7367; 147 deltas 33 ms, 74 deltas 34 ms | Rear oblique lifting/lowering sequence. Text overlay **obscures near-side right plate/hub during part of motion**. This is a visibility/abstention case; do not infer hidden hub coordinates from the far plate or interpolate them as observed reference. |

All observed PTS are strictly increasing. The Commons 33/34-ms pattern is consistent with 30-fps rounding into a millisecond time base; it is not evidence of a challenging VFR/discontinuous source. No nonzero rotation metadata was observed. Portrait encoding is not equivalent to a rotation-transform test.

The MyDeadlift sample's actual encoded size conflicts with the publisher's 1920×1080 acquisition description. Use **480×848** for this exact asset's geometry; original capture metadata cannot substitute for decoded dimensions. The Commons assets contain at least two apparent athletes: squat/deadlift share one apparent athlete, bench uses another; all share source/environment. Conservatively keep the entire Commons source in one development group. MyDeadlift subject 01 is another development group. Neither group is independent held-out coverage.

An initial helper named `inspect.py` exited with an access violation. Renaming it to avoid a Python standard-library name collision was followed by a successful complete probe and conversions. This does not establish native decoder behavior or a general PyAV reliability guarantee. The successful commands/scripts/probe output are retained in ignored artifacts.

## Supported-format development derivatives

Converted the three Commons sources to H.264 MP4 via local PyAV/libx264: CRF 18, preset fast, yuv420p, no B frames, same dimensions, no crop/rotation, no source audio. Source PTS and time base were supplied explicitly. Then every derivative was reopened and fully decoded: frame counts, dimensions/zero rotation and **every rational presentation time** matched its original. Output time base changed to `1/16000`; integer PTS therefore changed. Equality is measured for these files, not an assumption about conversions generally.

| Derivative | Bytes | SHA-256 | Frames / last PTS at 1/16000 |
| --- | ---: | --- | --- |
| `commons-squat-h264.mp4` | 1,532,111 | `9bcee5e14465fd61b9b798828697f768826172ab146a6da233d04690107ac9ed` | 213 / 113072 |
| `commons-bench-h264.mp4` | 990,651 | `4e4233a0a55e9899fd4ba183f384a8411675829e24601e0615b2e366f5018c70` | 213 / 113072 |
| `commons-deadlift-h264.mp4` | 1,240,449 | `d6c035e8fce2661aa1b2ff0e86f57484c98cd7c3b143d144e1393af77f2eb6f4` | 222 / 117872 |

Conversions plus individual derivative PTS ledgers/transform descriptions are under ignored artifacts. Original media/rights preserved. Contact sheets/detail PNGs are inspection derivatives. None of these derivative bytes is shipped or published. H.264 container compatibility is a candidate for AVFoundation, not an actual Apple import/decode pass.

## Proposed minimum native scope for leader review

1. Start with original MyDeadlift H.264 and the three explicitly pinned derivatives, supplied locally to an **opt-in** Apple development harness; no implicit public-media CI/upload. Run managed import/metadata/upright dimensions and actual AVAssetImageGenerator returned-image/actualTime export through existing app paths. Source inspection in the following annotation scope confirms the app uses preferred transform/clean aperture, a1024×1024 size cap and about15requested frames/second; it does not decode all source frames through AVAssetReader.
2. Compare the native accepted sample subset/actual CMTime rational values against each exact selected file's ledger; preserve epoch/value/timescale and orientation. Measure the actual returned upright image geometry, including the size cap, before making reference images. Check actual audio/container versus video duration rather than using nominal30fps to synthesize time. Diagnose platform differences before treating a discrepancy as product failure.
3. Run existing automatic and manually initialized prediction export on development clips, retain abstentions/identity runs and actual timestamps in separate prediction JSON. First validate schema/hash/geometry/time pairing. Empty references still mean no accuracy metric; no detector-derived coordinates become ground truth.
4. Obtain manual near-side hub/visibility annotations through the forthcoming local workflow. Do not label an obscured hub by guessing. Tune only on development groups; independent user clips and an untouched held-out group remain required before any accuracy gate.

No native harness implemented or Apple tests/CI run in this checkpoint. Device memory/thermal/performance and real-video native lifecycle remain open. Acquisition/Windows decode/conversion completion does not close them.

Next authorized independent task: scope a simple local user annotation workflow with actual-PTS predecoded frames, clicks/visibility/corrections and manifest-compatible export, using existing reusable tools where appropriate. Scope checkpoint expected 5–10 minutes after this report, no hard deadline; private folder availability and first native measurements determine later estimates. The original acquisition estimate was 15–25 minutes/no hard deadline; successful decode evidence arrived within roughly 6 minutes, with documentation/review finishing separately. Full accuracy/release ETA remains unavailable until media/device/hosting gates are established.
