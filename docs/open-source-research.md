# Source research and reuse decisions

Initial inspection 2026-10-07. The human explicitly directed the team to draw from available open-source resources, including Bar Is Loaded and existing bar tracking tools. These are inspected candidates, not validated dependencies or measured tracking results. Extend this research as each feature is implemented.

## Bar Is Loaded

- https://github.com/dongledan/bar-is-loaded : the current master tree contains documentation, issue templates, screenshots, and privacy policy. No application calculation source or license file was found in that tree; the branches API returned only master.
- https://github.com/dongledan/bar-is-loaded-app : a separate public repository with a 0BSD LICENSE, Gatsby/React website source, and screenshots. Read `src/pages/index.js`, `src/components/Content.js`, and `src/utils/index.js`: these assemble the marketing page and utility functions, not the mobile calculator. The LICENSE carries Gatsby's copyright notice; do not infer mobile code or all third-party assets are licensed by it.
- Both were discovered through the author's website and public repository list. We have not verified a public repository containing the current mobile application's calculation implementation. This does not prove one cannot exist elsewhere or historically.
- Use the actual feature documentation, screenshots, and issue history to guide UX and edge-case coverage. Seek further genuine mobile/calculator source when useful; never claim that inspecting website source establishes the app's algorithms.

## Bar tracking candidates

### Marticles/barbell-path-tracker

Source: https://github.com/Marticles/barbell-path-tracker . MIT license present. Inspected `tracker.py` and README. Python/OpenCV 3/Dlib project, last push reported by API as 2020-04-19. Implements selectable generic trackers and stores box-center samples to draw a trajectory. Requires an initial user-drawn bounding box.

Decision: useful licensed baseline for user-assisted tracking and comparison of algorithms. Evaluate a modern compatible implementation and failure handling before reuse; it does not itself meet automatic bar identification or provide a native iOS integration. Do not treat old dependencies or included demo footage as automatically suitable for redistribution.

### cluffa/BarTracking

Source: https://github.com/cluffa/BarTracking . Inspected README and `BarTracking/track.py`; tree includes ONNX model files. Segments plates, fits ellipses, and estimates their centers. README explicitly warns of competition-video bias. Source uses ONNX Runtime and OpenCV; it is a Python prototype, not an iOS library. No root license file or GitHub-detected license found in initial tree inspection.

Decision: useful detection/ellipse-fitting research and a warning about gym-footage domain shift. Establish source and model-weight rights before incorporating files. Compare the approach against near-side hub tracking; do not adopt its plate-diameter or two-side averaging assumptions blindly. No runtime accuracy measured here.

### wdiasjunior/BarbellTracker

Source: https://github.com/wdiasjunior/BarbellTracker ; demo/docs https://wdias.dev/BarbellTracker/ . OpenCV.js browser project. Documentation says its automatic background-subtraction mode identifies a green marker attached to the bar; MeanShift/CamShift modes require a selected box. GitHub API did not report a license during initial inspection; further file review is needed before reuse.

Decision: marker tracking and interaction reference. A required green sticker would not fulfill automatic analysis of ordinary existing training videos.

### Kinovea

Source: https://github.com/Kinovea/Kinovea . Public sports-video analysis project; GitHub identifies GPL-2.0. Initial repository-level inspection only.

Decision: investigate trajectory correction, calibration, and annotation workflows as a reference/possible evaluation aid. Assess actual file/dependency licenses and platform suitability before copying code. It is not established here as an iOS component.

## Next technical evaluation

Before committing to the video implementation, compare Apple Vision user-assisted tracking, a modern OpenCV tracker, and segmentation/plate-center detection on representative squat/bench/deadlift videos. Measure initialization, drift, occlusion recovery, false target selection, timestamps, memory, and processing time. Separate automatically finding the bar from following it. Only use appropriately licensed code, models, and evaluation assets. Record adopted/rejected options and why; retain notices for reused components. Prefer a small proven dependency to unnecessary custom rebuilding, while keeping videos on device.

## Milestone 1 worker decisions

Worker independently reviewed Bar Is Loaded's README and the two tracking implementation pages on 2026-10-07. No third-party source/model/assets were copied into the app.

| Feature | Adopt / adapt / reject | Evidence and remaining gate |
| --- | --- | --- |
| Plate/reverse loading | Adapt Bar Is Loaded's documented per-side loading, custom equipment and lb/kg interaction; implement an original Swift domain/UI. | README explicitly describes rounding down to the smallest plate; our requested finite-inventory nearest/lower/upper behavior needs complete combination search. The inspected repositories do not establish a reusable mobile solver. 13 independent fixture checks passed; Swift execution pending. |
| iOS project generation | Adopt XcodeGen manifest workflow as a development tool. | MIT project, manifest minimum version 2.46.0; reviewed Usage/ProjectSpec. No runtime dependency. Actual generation/build remains a Mac gate. https://github.com/yonaskolb/XcodeGen |
| Training/meet calculators | Adapt documented workflows; no verified reusable calculation source selected yet. | Formula/range and legal-increment implementations remain Milestone 2; review applicable sources before adopting components. |
| Data | Adopt official OpenPowerlifting bulk snapshots and public-domain facts; adapt to recurring full-version publication and compact native queries. | Actual 42-column archive header inspected; recurring ingestion, indexes, scheduler and query behavior remain stage 3. Do not copy AGPL website code by assumption. |
| Tracking | Adapt Marticles' box-center trajectory as an evaluation baseline; prefer Apple's native tracker for first user-assisted iOS source. Research cluffa segmentation/ellipse approach; reject direct vendoring pending rights. | Marticles MIT, old manual initialization; cluffa license/model rights unresolved. Neither inspected implementation was run. Ordinary-video automatic localization and real-device evaluation remain open. |

Repository branch names are observed references, not locked dependency versions. Before any source/model is incorporated, pin its exact commit/hash, inspect the relevant file and model licenses, keep notices, and validate on our acceptance cases. No license conclusion is inferred solely from a repository description.



## Data service and native client reuse record

- Adopted exact csv-parse7.0.3/yauzl3.4.0 MIT and crc-321.2.2 Apache2.0; yazl3.3.1 MIT is test-only. Locked in DataService/pnpm-lock.yaml. Actual stream/ZIP/SQLite integration ran on Node24.19.0, including CRC/UTF-8/correction/removal/failure tests. Keep dependency licenses if distributing the service; no AGPL website implementation copied.
- Adopted Node24 built-in SQLite and parameterized queries, with immutable indexed snapshots. API/concurrency limitations and genuine full-import evidence are in data-service-runbook.md. The native client adapts this explicit original read contract; it uses Apple's URLSession/CryptoKit rather than an external networking library.
- Pinned XcodeGen2.46.0 development ZIP by verified SHA; official checkout/upload-artifact actions pinned to verified tag commits. Hosted workflow configuration and local verification are in hosted-native-build-plan.md. No Apple execution yet.

## Milestone 2 worker decisions

- Adapted named Epley/Brzycki formula selection and single-rep identity from MIT FineGym `fitness-calc`, commit `55d2590a110406de62a10e2896e49f039324afe8`. Inspected `src/one-rep-max.ts`, `tests/one-rep-max.test.ts` and LICENSE. Kept full notice in source and app resource. No TypeScript package runtime; use exact rational physical mass and reject reps outside 1–10. Independent Windows specification checks pass; native implementation execution remains pending.
- Inspected MIT `GunnarStrandbergAB/strength_tracker`, commit `b9cae294f7feed4721730230c1a24f77509f0f93`, README and E1RMConsolidationTests. Shared formula consistency is useful; rejected its formula-switch/clamping behavior for this requirement. No code copied.
- Reviewed primary research equation tables and current IPF technical rules for formula conventions, ordinary increment and calibrated kg colors. Exact references/limitations appear in `calculator-decisions.md`.
- Warm-up and attempt planning adapt the established finite loading engine; no inspected component supplied the native finite-inventory constraints, honest goal handling and migration behavior needed here. Presets remain explicitly editable examples. No external training-app runtime dependency added.
