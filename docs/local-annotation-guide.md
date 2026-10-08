# Local hub labeling

## Current acceptance

Source/runtime checkpoint, October 8, 2026. **Private-video use is pending the final browser correction/reload/request check.** The in-app browser stalled on a confirmation dialog during testing; the revised interface uses an explicit **Clear point** action and save-first messages. No private folder has been supplied or read. No real references or accuracy scores have been created.

Windows PyAV bundles produce development drafts. They do not establish that their images or presentation times match the app's AVAssetImageGenerator output; their `--purpose native-scoring` remains refused. A separate native producer branch is implemented in source, with Apple compilation/execution pending. Native labels must be made on those captured native images. Keep each export's `.report.json` beside it; the unchanged reference schema cannot carry producer association by itself.

## Developer native capture: Apple host required

This is an internal developer method, without a product export button. It cannot run on this Windows host. No private videos are authorized for CI; a proposed first Apple run uses only generated test movies. Private local capture needs an authorized Apple host/device and the remaining browser gate below. Do not upload a managed movie or bundle to GitHub to work around those requirements.

On an Apple development host, import the explicitly selected clip into `VideoModel`, then select a range of at most **one second** using the existing start/end controls. The context describes the **managed imported copy** returned by `model.video.url`. Compute its SHA-256 locally; `assetRoot` must contain that copy and `localPath` must resolve to it. The original filename outside the managed directory will fail identity checks. Choose a new destination with an existing parent directory, outside Git. No folder scan occurs.

```swift
// Inside a developer harness on the main actor, after successful import/trim.
// These values must come from the explicit local clip registry and tested build.
let context = BarFrameBundleContext(
    prediction: BarPredictionContext(clipID: clipID, expectedSHA256: managedMediaSHA256,
        modelID: testedDetectorBuildID, synthetic: isGeneratedFixture),
    assetRoot: managedAssetRoot, localPath: relativeManagedMoviePath,
    sourceGroup: subjectSessionGroup, split: "development",
    permissionEvidence: recordedLocalPermission, lift: "deadlift", targetID: "near-side-hub")
let capture = model.captureAnnotationBundle(context: context, destination: newLocalDestination)
let completedDirectory = try await capture.value
```

The caller supplies actual clip/group/partition/permission metadata and an identifiable detector/build revision in `modelID`; the exporter does not infer consent, subject identity, toolchain version or Git revision. Mark generated movies `synthetic:true`/`lift:"synthetic"`; real footage stays `synthetic:false`. Manual Vision capture is available via `mode:.manual` after an actual seed at the selected start; it remains a distinct mode.

The hook encodes the **same accepted CGImage** consumed by the detector and preserves its **actual CMTime integer components**. It introduces no second production decode, resizing, timestamp reconstruction or change to detector/default analysis limits. Completion contains:

| File/field | Meaning |
| --- | --- |
| `frames/frame-NNNNNN.png` | Accepted upright detector-input image, at most 1024 pixels on either axis |
| `ledger.json` / `clip` | Explicit relative managed-media path/hash, grouping/partition/permission, actual image dimensions |
| `ledger.json` / `frames` | Numbered image filenames/hashes and original PTS string, timescale and epoch |
| `ledger.json` / `decoder` | AVAssetImageGenerator, OS version, preferred transform, clean aperture, maximum size and zero tolerance |
| `ledger.json` / `association` | Analysis/session UUIDs, exact accepted timestamps, range, model/mode and SHA-256 of adjacent prediction bytes |
| `prediction.json` | Existing prediction schema from the same returned analysis result, including lost/abstained observations |
| `bundle.json` | Embedded PNGs, unchanged ledger text and its SHA-256 for offline labeling |

Native bounds are ≤1 second/16 accepted frames/32 MiB PNG payload/48 MiB bundle; source ≤500 MiB. Existing analysis 120-second and per-hash 60-second checks remain **cooperative**, not external kill deadlines. Publication uses a fresh partial sibling directory and a final local rename. Failure/revocation/source mismatch removes completion files and retains partial PNG diagnostics. A retry requires a fresh destination. Import/removal revokes publication before changing clip generation and waits for cleanup before deleting the managed copy. Cancellation after the final rename preserves the already completed historical bundle; it cannot make that bundle refer to the replacement clip.

After successful capture, use `bundle.json` in the same labeling steps below. The native UI branch displays the declared producer/session and requires the CLI to verify the actual prediction/media files before scoring. Browser import is not producer authentication or an accuracy result. Do not edit/re-hash the ledger: UUIDs and hashes bind accidental mismatches; they are not signatures against fabricated bundles.

## Prepare one explicitly selected clip

The existing isolated PyAV 19.0.1 wheel lives under ignored artifacts. No system install is required. Use a new output folder for each preparation. Keep original media, bundles, drafts and reports local and outside Git. For your own clips, provide the authorized folder and identify subject/session groups before preparation. Excerpts from one recording/subject/session stay in the same partition. Do not tune on holdout labels.

The following known public sample command is reproducible from PowerShell:

```powershell
Set-Location C:\codex\powerlifting-app
$annotationPython = 'C:\Users\micha\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $annotationPython tools\annotation\prepare_frames.py `
  --asset-root artifacts\licensed-media-inspection `
  --media artifacts\licensed-media-inspection\originals\mydeadlift-GB_S01_R01.mp4 `
  --output artifacts\my-new-label-bundle `
  --tooling artifacts\licensed-media-inspection\tooling `
  --clip-id mydeadlift-GB-S01-R01 --source-group mydeadlift-subject-01 `
  --permission-evidence 'CC BY 4.0; asset-provenance.json; DOI 10.17632/w5prmmxyt9.1' `
  --lift deadlift --split development --every 15 --max-frames 8
```

`--every` selects actual decoded frame ordinals; it does not manufacture frame times. Output is `frames/*.png`, `ledger.json` (authoritative media/image hashes, exact PTS, geometry and partition), and `bundle.json` (embedded local PNGs for the browser). Preserve `ledger.json` unchanged, separately from editable labels. A failed preparation may leave partial frames; it does not produce a valid bundle. Use a fresh folder for a retry.

Initial bounds: media ≤512 MiB; ≤450 selected frames; ≤32 MiB PNG payload/48 MiB browser bundle; preparation checks ≤27,000 decoded frames and 120 seconds between decode iterations. A blocking decoder call can exceed that elapsed check; this is not an external process kill deadline. Nonzero display rotation/non-square pixels are refused until an authoritative native export exists. Native preferred transform, clean aperture, 1024-pixel scaling and accepted 15-Hz request times remain unverified.

## Label and keep recoverable drafts

Open [offline-via.html](../tools/annotation/offline-via.html) locally. Use this reviewed derivative, whose pinned provenance and retained BSD notice accompany it. Loading the HTML does not grant permission to publish videos. File-URL behavior still needs verification; the completed partial UI checks used loopback serving of only the HTML.

1. **Load frame bundle** → choose `bundle.json`. The UI shows clip, actual PTS string, frame ordinal and review state. Every frame begins **unreviewed**, without a point or visibility default.
2. Navigate using **Previous frame / Next frame**; **Zoom in / Zoom out** changes display scale. For **visible**, click exactly one near-side hub. Drag the point to correct it, or **Clear point** and click again. Never substitute the far plate for an occluded near hub.
3. Enter uncertainty radius in original image pixels, at least **1 pixel** for VIA's integer rounding. Increase it when the center is hard to locate; this radius is your labeling uncertainty, not statistical confidence.
4. Choose **occluded**, **outside-frame** or **uncertain** when the near hub cannot be observed. **Clear point first**; these labels require no point/uncertainty. Leave an undecided frame unreviewed instead of guessing.
5. **Mark reviewed** checks the current label. Point edits or changes mark it unreviewed again. **Save draft** downloads a timestamped local JSON. Save before changing bundles or reloading drafts; those actions refuse unsaved changes.
6. To recover, load the matching bundle, then **Reload saved draft**. **Export labels** saves the same strict VIA metadata envelope for the adapter. Keep earlier downloads until a new validated export succeeds. PyAV and native bundles have different ledger hashes; a draft from one cannot be reloaded against the other. Relabel native captures on their actual images.

## Validate and export a development draft

```powershell
$annotationNode = 'C:\Users\micha\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
& $annotationNode tools\annotation\adapt_labels.mjs `
  --ledger artifacts\my-new-label-bundle\ledger.json `
  --labels 'C:\Users\micha\Downloads\hub-labels-REPLACE-WITH-ACTUAL-DOWNLOAD.json' `
  --asset-root artifacts\licensed-media-inspection `
  --purpose development `
  --output artifacts\my-new-label-bundle\references.development-draft.json
```

For multiple clips, also pass `--existing PATH-TO-EXISTING-REFERENCE-MANIFEST.json` so the existing validator checks source-group/media-hash partitions across the project. The adapter emits this clip only, plus a completion report; it does not merge or overwrite earlier exports. Keep the full reference registry for every subsequent clip. Export creation is exclusive: choose a new output filename for corrections.

Exact PTS comes from the immutable sidecar, never editable UI metadata or playback time. The adapter checks actual selected media/image bytes and PNG geometry. It rejects duplicate JSON keys, missing/foreign frames, changed hashes, unordered/equivalent duplicate timestamps, unknown fields, multiple/non-point/out-of-bounds points, coerced/zero uncertainty, stale points on non-visible labels, and partition leakage against `--existing`. Reviewed frames become manual references (or explicitly synthetic references in the test fixture); unreviewed frames are reported and omitted.

## Validate a native reference export

Only use this branch for a completed native directory, after labeling its captured images. Keep `prediction.json` adjacent to `ledger.json`. Preserve the managed movie or explicitly copy it unchanged into a new local asset root using the **same relative path** recorded by the ledger; the adapter does not translate original/managed paths.

```powershell
& $annotationNode tools\annotation\adapt_labels.mjs `
  --ledger 'PATH-TO-COMPLETED-NATIVE-DIRECTORY\ledger.json' `
  --labels 'PATH-TO-ACTUAL-hub-labels-DOWNLOAD.json' `
  --asset-root 'PATH-TO-ROOT-CONTAINING-RECORDED-MANAGED-MOVIE' `
  --purpose native-scoring `
  --output 'PATH-TO-LOCAL-OUTPUT\references.native-reference.json'
```

The adapter checks the native decoder contract and bounds, hashes actual media/PNGs/prediction JSON, validates the unchanged prediction schema, and matches clip hash/ID, mode/model, dimensions, sample count and **exact timestamp components**. Equivalent rational times with changed components are rejected here. Use `--existing` for cross-clip partition checks as above. Native companion reports record the analysis/session/prediction association. Exports remain exclusive; a new correction gets a new filename.

This output can be supplied as `--manifest` to `tools/score-video-traces.mjs`, with this bundle's `prediction.json` as `--predictions`, the same `--asset-root`, and a fresh `--output`. The scorer verifies media automatically. Retain the adapter report with any score. Synthetic references still count as synthetic; producer association alone does not establish near-hub accuracy, independent subject coverage, device performance or readiness.

## Developer verification and remaining gate

```powershell
& $annotationNode --test tools\annotation\annotation.test.mjs
& $annotationPython tools\annotation\prepare_frames_test.py
& $annotationPython tools\annotation\build_offline.py
```

Pinned upstream and derivative SHA-256 are in [provenance.json](../tools/annotation/provenance.json). The builder uses only the committed upstream bytes; it removes analytics and remote import/project/search-path implementations, neutralizes remote links, adds CSP (`connect-src 'none'`, data/blob images only), and embeds the project panel. No external libraries are loaded. `vendor/via-2.0.12.html` is the unmodified provenance copy, **not the labeling entry point**.

Actual partial browser evidence: synthetic local import; 1.5× zoom click exported original `(100,150)` → normalized `(0.25,0.75)`; draft save/load retained the point; visible uncertainty/review and a separate occluded frame exported; adapter produced two synthetic labels with PTS above JavaScript's safe-integer range. Loopback log recorded HTML GETs only in that partial run. This is not a complete network/privacy acceptance.

Remaining browser gate: revised explicit visible→occluded correction; draft save/reload and export after that correction; public-frame navigation usability; request/CSP/API observation across the complete final flow; direct file-URL behavior. The stalled test is IAB tab **4**, `http://127.0.0.1:8766/offline-via.html`; last visible state was the synthetic first frame reviewed/visible with uncertainty 2, followed by a confirmation action. Documented dialog/close/Escape and tool-session reset did not recover file selection; no browser/app processes or user settings were changed. Do not begin private use until this gate passes.

Eight actual public MyDeadlift frames were prepared and verified against media/image hashes under ignored `artifacts/annotation-public-mydeadlift-final2`, without labels. PyAV reports unspecified sample aspect ratio (`0/1`) for this source, preserved as unspecified provenance; there is no native display-geometry inference. New native capture XCTest source covers rotated/capped generated raster/PTS identity, bounded writer failure and model-removal cancellation, but has **not been compiled or run**. Representative accuracy, private/native access, browser acceptance, device performance and service hosting remain separate gates. Human labeling effort can be estimated after clip inventory and roughly 20 actual labels; no reliable full readiness estimate exists before those results.
