# Full-rep window registry and aggregation scope

October 8, 2026. Proposal only, following portable export46a50ef/a13135d and UI
isolation scope081e904. No capture-limit/detector/schema/tool implementation here.

## Current boundary

The native producer and strict wrapper validate ONE <=1s/16frame window, with
absolute accepted CMTime components and a distinct window/analysis/session ID.
Portable packages preserve the whole managed recording at its recorded basename.
Repeated windows use a recording hash group, but the adapter emits one clip and
only checks an explicitly supplied existing reference registry. It neither merges
windows nor measures complete-rep coverage. Native continuity state restarts on
each analysis; its local track IDs cannot establish cross-window identity.

Existing components to reuse: `timestampKey`/orderedTimestamps and formal reference
validation; strict native ledger/prediction association; streaming source hashes;
label adapter; score policy preserving mode/split/synthetic groups and
accuracyGatePassed:false. Do not turn a derived aggregate into a fabricated single
native capture or rewrite authoritative ledgers/predictions to make IDs match.

## Smallest proposed milestone

An explicit local CLI takes a user-selected plan naming ONE recording/rep, the
desired positive <=30s rep interval, and bounded native windows. Each entry names
its ledger, reviewed labels, explicit asset root and strict evaluation receipt.
No folder scan, media discovery/upload or implicit human labels. Resolve roots and
named regular files under their supplied local roots, using existing bounds and
fresh byte/association verification. Preserve both original capture and evaluation
receipts/bytes; flags in an editable receipt are insufficient to trust inputs.

Produce a new exclusive derived directory with:

- `registry.json`: recording/rep/window IDs, explicit group/split/permission review,
  chosen ranges, original input file digests and paths, model/mode/geometry,
  immutable window-analysis associations and any explicit conflict selections.
- `aggregation.json`: exact distinct-time coverage, missing/unreviewed inputs,
  conflicts, gaps and seam diagnostics; links to original per-window evaluation.
- `aggregation-receipt.json`: input/output hashes/byte counts, selected source
  identity, policies/bounds and completion. Its kind is `native-window-aggregation`,
  not native-analysis/native-evaluation or an accuracy attestation.

Keep existing per-window scores visible. Initial aggregate can report counts and
seams while unresolved conflicts are explicit; publish no pooled localization
metric until input-selection/denominator policy is reviewed and conflicts resolve.
No private-media or full-rep detector accuracy claim follows from source tests.

## Identity and partition policy

The rep belongs to the whole recording SHA, not the window UUID or package path.
Repeated byte-identical recordings retain one registry identity across managed
basenames/imports. Verify the bytes at every referenced distinct physical source
path; never trust an expected hash as proof that another copy has those bytes.
Canonical-file verification may be reused only for the same resolved input path
and immutable snapshot within this operation. Source cropping/transcoding changes
hash and needs an explicit original-recording relationship; do not infer one.

Preserve original window clip/analysis/session/model/mode identities in every row.
Repeated receipt/ledger IDs with changed bytes refuse the operation. Byte-identical
copied inputs are listed once; distinct overlapping captures are compared as
overlaps. Never rename their runs into one original native run.

All windows for a rep must agree on recording hash, selected lift/target,
synthetic provenance and split. Source-group/hash partition checks apply across
the whole existing registry, including clips outside this rep. Initial UI exports
remain development; aggregation cannot promote them to training/holdout. A hash
group establishes identical-recording grouping only. Subject/session independence
requires explicit reviewed group relationships, preserved as registry evidence
without rewriting ledger metadata or weakening a prior grouping constraint.
Unknown independence remains unknown. Research permission is explicitly supplied,
separate from the earlier local-export action. Keep identifiers anonymous/local.

## Absolute timestamps and overlaps

Use original integer value strings/timescale/epoch. Never reset a window to zero,
add its Double rangeStart to PTS, round to milliseconds, interpolate, or infer time
from nominal fps. Native exact component matching remains per window. For
cross-window overlap discovery use BigInt rational equivalence (`timestampKey`),
while retaining every original component tuple and frame hash in the registry.

For the same recording/target and equivalent rational PTS:

1. Matching PNG bytes, geometry/decoder contract and exact components identify a
   duplicate raster. Identical reviewed reference state/point/uncertainty counts
   once in a distinct-time denominator. Unreviewed duplicates stay unreviewed;
   they do not silently supply a point or increase observed sample count.
2. Different raster hashes/geometry/decoder geometry metadata, different original
   component tuples, or contradictory review/visibility/point/uncertainty create
   explicit conflicts. No nearest-time match, averaging, lower-uncertainty winner,
   latest-file winner or inferred visibility. Record both identities and refuse
   metrics pending explicit reviewed selection/correction with source hashes.
3. Predictions remain separated by mode AND maintained model/build. Distinct
   window predictions at the same frame can disagree despite identical images
   because tracker state differs. Report that as a seam disagreement. A proposed
   future scalar aggregate needs a predeclared deterministic window-selection
   policy; do not choose the best prediction after inspecting reference error.

Requested rep boundaries are explicit plan metadata, not guessed from first/last
sample. Store exact rational boundary components for an aggregate plan. Original
ledger Double ranges remain unmodified/request-range evidence; never pretend
converting those Doubles reconstructs exact decoder boundary timestamps.

## Seam and completeness policy

Report union of declared window ranges versus selected rep interval, distinct
decoded/reference timestamps, missing windows, unreviewed timestamps and declared
gaps. Interval coverage alone is not frame/reference coverage. A point at each
seam does not establish the complete motion between samples.

Do not connect overlay paths or compare local track-ID strings across windows.
Identical frame overlaps can compare accepted points/loss/visibility explicitly;
record target ambiguity, reference conflicts and prediction disagreement. Without
an overlap, mark cross-window continuity unverified. Existing0.25s continuity gap
policy must not become permission to interpolate or infer correct reacquisition.
Any no-image/unreviewed/occluded/uncertain interval stays visible in diagnostics.
Whole-rep validity needs reviewed target identity, adequate coverage and a
representative design decision; a successful CLI cannot set accuracyGatePassed.

## Bounds, storage and publication

Proposed initial bounds: one rep/recording per invocation, <=30s desired interval,
<=64 windows/16frames each (<=1024 raw frame records), <=32MiB selected JSON inputs
in total with existing per-file limits, <=4GiB verified distinct physical media
reads, <=32MiB PNGs/window, and <=8MiB derived output. Stream/verify windows
sequentially and retain small canonical metadata rather than all bundle base64 or
movie buffers. No movie/PNG copy belongs in the derived report. Explicitly reject
larger plans, sources, output collisions, partial receipts and changed inputs.

Repeated portable packages each contain the whole movie and can consume substantial
local storage; 64 maximum-sized exports would exceed this first aggregation budget.
Users can explicitly supply one matching preserved source root across windows
whose recorded basenames resolve there, with actual byte checks. Do not silently
remove duplicate movies or rewrite ledger paths. Shared-source storage, repeated
native capture automation and larger-rep formats require separate review.

Use exclusive owned staging/final rename and cooperative per-file60s checks. A
proposed aggregate300s cooperative phase limit must be stated as such, with a
separate caller process deadline if required; no hard I/O/OS bound claimed. Never
modify inputs/old registries or remove a user's package during failure/cleanup.
Corrections publish a new registry version linking the previous receipt.

## Meaningful checks and decision

Generated contract tests should cover disjoint/nonzero-start windows preserving
absolute PTS, rational equivalents above JS safe integer, overlap deduplication,
changed component/raster/reference conflicts, model/mode-separated predictions,
no-overlap seam uncertainty, missing/unreviewed denominators, group/hash partition
leakage through the existing registry, reimport basenames with the same source,
changed receipt/source before publication, output collisions/cancellation/bounds
and prior-output preservation. Keep synthetic fixture labels distinct from real
observed annotations. An actual Apple multiwindow input path and browser labels
remain later execution gates, alongside the outstanding single-window wrapper.

Leader decision: approve registry/coverage/conflict reporting first, with all
scalar pooling withheld until reviewed selection policy; choose broader group
review format and desired overlap metadata before implementing. Recommended
Medium for CLI/source implementation, High only for a named remaining exact-time
or conflict-selection correctness risk. Provisional source estimate35–55min after
review, no hard deadline; current scope checkpoint5–10min. Native/private/research
readiness cannot be dated before actual reviewed multiwindow captures/labels and
coverage results. Initial real references remain zero and accuracy unmeasured.
