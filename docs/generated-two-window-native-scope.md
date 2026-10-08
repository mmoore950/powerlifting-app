# Generated two-window native proof scope

October 8, 2026. Scope only. No new Swift test, attachment producer, extractor,
private media, CI run or accuracy evidence is created by this document.
Run16 failed before the iOS tests/exports, so it supplies no transport proof.

## Smallest proposed fixture

Reuse the existing `SyntheticMovieWriter` in
`Tests/App/VideoMediaLifecycleTests.swift`, the asymmetric rotated raster oracle
from `BarFrameBundleExporterTests`, `BarAnalysisService`, native exporter,
strict per-window evaluator and cumulative aggregate. Generate one128x96,
rotated, asymmetric H.264 MOV with15frames at30fps (0.5s duration). The existing
writer accepts at most30frames and already has a30s cooperative encoder guard.
No production capture/decoder/validator limits change.

Propose one new app-host method:
`BarFrameBundleExporterTests/testGeneratedTwoWindowAbsolutePTSOverlap()`.
Retain the existing single-window method/attachments and every current required
method. Source inventory automatically requires the additional method, so a
reviewed later run must pass63 iOS methods if this is the only added XCTest.
This count is a proposal, not current execution evidence.

Capture sequentially from the SAME generated file into two distinct fresh
directories, each with independent analysis/capture session and clip IDs:

| Window | Requested Double interval | Intended generated frame rational times |
| --- | --- | --- |
| A |0.1...0.3|3/30,5/30,7/30,9/30|
| B |(1.0/6.0)...0.4|5/30,7/30,9/30,11/30,12/30|

`VideoSampleClock` requests start+index/15, clipped to end. These intended
requests guide fixture assertions; only actual decoder CMTime values/timescale/
epoch are authoritative. Compare decoded times using exact rational arithmetic,
retain original component tuples, and require the observed expected shared times
5/30,7/30,9/30. If platform decoding differs, fail this proof and inspect the
actual receipt; do not shift to zero, infer FPS timestamps, round, or rewrite
native bytes. In particular, sample/PNG IDs are local to each window and cannot
be equated by basename or index.

Context: clips `generated-native-window-a` and `generated-native-window-b`,
model `generated-two-window-capture-test`, source group
`generated-native-two-window-fixture`, synthetictrue/development/liftsynthetic,
same source SHA and target `near-side-hub`, localPath `generated.mov`, automatic
mode and upright96x128. No real hub truth is claimed. Group metadata remains
null/unknown; one recording does not establish independent sessions/subjects.

## Native assertions before attachment publication

For both windows, retain the current same-analysis prediction hash/session
association checks, original absolute accepted PTS and source hash, actual
geometry, PNG hashes and bundle ledgerText/embedded PNG byte checks. Validate
each decoded PNG against an independently configured zero-tolerance upright
AVAssetImageGenerator at its actual PTS, using the existing raster oracle/tolerance.
Require distinct original clip/analysis/capture identities and the same movie SHA.
Require1...6 accepted frames per window and at least two exact shared PTS; the
intended fixture has4+5 frames and three shared PTS. Verify shared PNG bytes/
geometry/decoder/component tuples agree for this strict deduplication proof.
Unexpected byte/component disagreement is a failed fixture proof, not permission
to replace an original file or hide an aggregate conflict.

The detector starts fresh for each analysis. Predictions at shared PTS may differ
because temporal history differs. Preserve both original outputs and compare only
within the same model/mode; do not assert identical track IDs or shared target
continuity. No localization quality or reacquisition assertion belongs here.

## Named, bounded attachment route

Use explicit XCTestCase.add(_:) association with keepAlways, following the repaired
single-window producer. Select only the proposed named method's exact successful
unit-manifest group. Both UI and unit exports must pass in a reviewed successful
job. Retain the original successful run/revision/manifests/artifact digest and byte
count. No inference from UI screenshots, a failed method or raw result records.

| XCTest attachment name | Type | Reconstruction path |
| --- | --- | --- |
|`native-two-window-source`|QuickTime MOV|`generated.mov`|
|`native-two-window-a-ledger`|JSON|`a/ledger.json`|
|`native-two-window-a-prediction`|JSON|`a/prediction.json`|
|`native-two-window-a-bundle`|JSON|`a/bundle.json`|
|`native-two-window-a-frame-NNNNNN`|PNG|`a/frames/frame-NNNNNN.png`|
|Corresponding `native-two-window-b-*` names|Same types|Corresponding `b/` paths|

These are proposed XCTest names, not observed Xcode suggested filenames or MIME/
extension behavior. Reuse the single-window recipe's strict <=1MiB manifest read,
exact one-group selection, failed-association refusal, bounded regular/nonsymlink
basename resolution and no traversal. Inspect the first actual manifest and
accept only an exact observed mapping; do not invent extension/suggested-name
normalization or glob arbitrary attachments.

Share the source attachment once. Bounds remain<=20 selected files, <=1MiB/file,
<=2MiB combined, with actual byte counts checked before publication. Two windows
at at most6frames each plus source and six JSON files need at most19files;
the intended4+5 case needs16. Enforce the bounds rather than drop frames/JSON or
expand the transport. Wider/current single-window tests retain their own route.
Write unchanged bytes into a fresh owned staging root, never overwrite an old
reconstruction, and rerun source/PNG/prediction/bundle validation before rename.
Each ledger uses localPath generated.mov; explicit shared assetRoot is the
reconstructed top-level root, while prediction/frames remain beside each ledger.

## Current evaluator and aggregate proof

After the actual reconstructed bytes pass, create two explicit GENERATED label
envelopes bound to their original ledger digests with every frame unreviewed.
This exercises association with zero references; do not derive truth from
predictions or colored pixels. Run the existing strict evaluator independently
for each ledger, using the shared source assetRoot and fresh evaluation outputs.
Retain both evaluation receipts and all five bound files with the original inputs.

Select an explicit plan: generated rep interval3/30...12/30, observed movie hash,
two named windows and expected overlap5/30...9/30 (exact epoch0 tuples). The
existing aggregate verifies native ledgers/assets, labels and per-window bound
receipts again. No fabricated combined native ledger or pooled score is emitted.

For the intended actual4+5 case, require raw9/distinct6/shared3, original nonzero
PTS retained and each shared timestamp has two original rows; no raster/decoder/
component/reference conflicts in this baseline. Require reviewed0, observed0,
unreviewed6, accuracyGatePassedfalse, scalarMetricsnull and continuityunverified.
Preserve prediction disagreements as diagnostics. Counts are sampled fixture
coverage, not continuous full-rep coverage or representative detection performance.

The current evaluator cooperative120s and aggregate cooperative300s/60s streams,
32MiB selected JSON/8MiB output/4096 cumulative assignments stay unchanged;
the native fixture transport is much smaller. Caller process limits and existing
prepare2/build8/test10/job30 are separate. No additional CI is authorized by this
scope; after source implementation, review the exact revision before dispatch.

## Estimate and remaining decisions

Proposed source implementation/contract checks:20–35minutes after approval,
no hard delivery deadline; new Swift test/source compatibility and exact rational
fixture assertions are uncertainties. Actual extraction/evaluator/aggregate
execution cannot be estimated until successful reviewed native attachments exist;
re-estimate after observing their exact manifest/count/bytes. This route also
depends on the pending CI diagnostic/lifetime/sequential experiment review.
Windows generated contract tests are not proof that the Apple producer or transport
executes. Files-provider/device/private-browser and real accuracy gates remain
separate. Recommended routine implementation reasoning: Medium; escalate only
for a named decoder/association correctness problem.
