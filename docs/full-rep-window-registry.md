# Local full-rep window registry

Source implementation, October 8, 2026. This CLI verifies selected native-contract
windows and reports coverage/conflicts. It has not processed actual Apple
multiwindow captures or real reviewed videos. No pooled localization score,
automatic winner, label propagation or accuracy acceptance is implemented.

## Explicit local inputs

First retain the original portable packages and run the existing strict
`evaluate_native_bundle.mjs` for each window. Each package supplies its original
ledger, adjacent prediction/frames, reviewed-label JSON and an explicit preserved
movie root. The aggregate freshly verifies these bytes and the five artifacts
bound by each `evaluation.json`; editable `nativeAssociationChecked` flags alone
cannot satisfy the gate. References/reports and score policy are recomputed from
the selected original buffers. Hashes bind bytes; they do not authenticate origin.

Example plan structure (replace every example identity/path/time with selected
local evidence; the all-zero hash below is a placeholder, not media evidence):

```json
{
  "schemaVersion": 1,
  "kind": "native-window-plan",
  "repID": "rep-001",
  "recordingSHA256": "0000000000000000000000000000000000000000000000000000000000000000",
  "interval": {
    "start": { "value": "6000", "timescale": 600, "epoch": 0 },
    "end": { "value": "7800", "timescale": 600, "epoch": 0 }
  },
  "groups": {
    "recordingGroupID": "anonymous-recording-001",
    "sessionGroupID": null,
    "subjectGroupID": null,
    "reviewStatus": "unknown",
    "permissionEvidence": null
  },
  "windows": [
    {
      "id": "window-001",
      "ledger": "saved/window-001/ledger.json",
      "labels": "labels/window-001.json",
      "assetRoot": "saved/window-001",
      "evaluation": "evaluated/window-001/evaluation.json"
    },
    {
      "id": "window-002",
      "ledger": "saved/window-002/ledger.json",
      "labels": "labels/window-002.json",
      "assetRoot": "saved/window-002",
      "evaluation": "evaluated/window-002/evaluation.json"
    }
  ],
  "expectedOverlaps": [
    {
      "windows": ["window-001", "window-002"],
      "interval": {
        "start": { "value": "6540", "timescale": 600, "epoch": 0 },
        "end": { "value": "6600", "timescale": 600, "epoch": 0 }
      }
    }
  ]
}
```

Window paths are relative to the plan's directory or explicit local absolute
paths. Output and optional existing/previous files resolve from the caller's
working directory. There is no folder scan, URL fetch, upload or automatic label
creation. The output parent directory must already exist; output itself must be
absent. Group IDs use anonymous ASCII letters/numbers/dot/underscore/hyphen,
maximum200 characters. Missing group IDs default null and review status unknown.
Supplied IDs/review status are metadata, not proof of independent subjects or
sessions. Research permission is separate from choosing a local export.

```powershell
node tools/annotation/aggregate_native_windows.mjs `
  --plan C:\selected\rep-plan.json `
  --output C:\selected\reports\rep-001
```

Use `--existing C:\selected\references.native-reference.json` to check the whole
selected existing reference registry, including clips outside this rep. The
authoritative validator still caps the combined unique manifest at100clips and
refuses any recording-hash/source-group split leakage. Matching original clip
IDs must have matching reference contents. Existing plus64 new windows can exceed
100; the CLI reports that incompatibility and requires smaller explicit inputs.

For a correction, choose a new output directory and supply
`--previous-receipt C:\selected\reports\rep-001\aggregation-receipt.json`.
The previous registry/coverage bytes must match their receipt. The new registry
links its SHA/path and preserves prior same-recording group relationships.
`partitionConstraints` carries a cumulative typed map from recording SHA,
source group, anonymous recording group, session group and subject group to the
assigned split. A new recording B cannot forget recording/group A before a later
C correction; conflicting assignments refuse publication. Constraints from an
explicit existing reference registry also survive through this cumulative map.
Only the explicitly selected previous receipt and its bound registry/coverage
files are opened; ancestor paths are not followed. The previous report is never
overwritten or deleted.

The map has schemaVersion1 and at most4096 unique `{kind,id,split}` assignments.
Types are `recording-sha256`, `source-group`, `recording-group`, `session-group`
and `subject-group`; splits remain training/development/holdout. The previous
registry must carry its own recording/group/source assignments with the same
split, without duplicates. Earlier format registries lacking this transitive
evidence are conservatively refused for chaining, even when their receipt hashes
match. They are not automatically scanned or migrated; select the authoritative
original inputs explicitly for a fresh derivation. Hashes bind bytes rather than
authenticate group origin or independence. The shared32MiB selected-input and
8MiB derived-output limits also apply to this history.

## Outputs and interpretation

- `registry.json`: original clip/analysis/capture IDs, model/mode/decoder/request
  ranges, frame tuples/hashes, selected paths/digests, group metadata, original
  per-window evaluation receipts and scores, and duplicate aliases. Keep original
  input files; the report contains their bindings/metadata, not copies of movies,
  PNGs or byte-for-byte original JSON.
- `aggregation.json`: distinct rational timestamp rows retaining every original
  tuple and conflict, reviewed/unreviewed/conflicted counts, visibility counts,
  separated model/mode prediction comparisons, declared request gaps, pairwise
  seam diagnostics and expected-overlap sample counts. `scalarMetrics:null` and
  `accuracyGatePassed:false` remain mandatory.
- `aggregation-receipt.json`: hashes/byte counts for both outputs and all selected
  JSON/PNG/source files, limits/counts and completion. Its kind is
  `native-window-aggregation`, distinct from a native analysis/evaluation receipt.

Samples use original integer CMTime components and BigInt rational equivalence,
never zero-resetting, nominal frame rate or millisecond rounding. Identical
reviewed overlap references count once per distinct rational time. Unreviewed
rows stay unreviewed; reviewed/unreviewed disagreement is an explicit conflict.
Different original tuples, raster bytes, geometry/decoder or reference meaning
preserve conflicts without choosing a winner. Repeated original clip/analysis/
capture IDs with changed input bytes refuse publication. Byte-identical copies
retain an alias and one unique-window/time denominator.

Prediction comparisons stay separated by model and mode. Point/loss/kind/confidence
differences are diagnostics; local track IDs remain in original rows and are not
cross-window semantic identity. Every seam and expected overlap has continuity
unverified, including overlapping points. No shared exact PTS is explicitly
reported. Missing input files fail verification; no fabricated missing-window
placeholder is accepted as a verified window.

Declared request coverage converts the serialized ledger Double request ranges
to decimal rationals and intersects them with the explicitly selected exact rep
interval. This is request-range evidence, not reconstructed exact decoder
boundaries or dense frame/reference coverage. Counts never establish full-rep
completeness, reacquisition accuracy or representative held-out performance.

## Bounds and publication

One positive <=30s rep, <=64selected windows, <=16frames/window and <=1024raw
records. All windows must agree on recording SHA, lift/target, split and synthetic
provenance. A development export cannot become holdout through this CLI.

Selected JSON has a shared32MiB limit, including receipt-bound artifacts and any
existing/previous registry. Original ledger/prediction <=1MiB, labels <=4MiB,
per-window PNGs <=32MiB, source <=500MiB and derived output <=8MiB remain bounded.
The4GiB media-read budget includes BOTH initial and fresh prepublication hashes:
up to2GiB distinct physical sources can fit those two passes. Every distinct
canonical source path is verified, even when multiple files have the same hash.
An explicitly shared matching source root/basename reuses the same initial
verification and is checked again before publication. Different original managed
basenames remain different physical paths. No media is copied/deleted/rewritten.

The aggregate has a cooperative300s budget; bounded stream operations use60s
abort timers. Existing raster/media validators retain their own policies; checking
at phase boundaries is cooperative and cannot guarantee hard filesystem/OS
termination. Caller-enforced process deadlines are separate. All JSON, PNGs and
distinct sources are freshly checked before exclusive sibling staging/final
rename. Failure/cancellation removes only this operation's fresh staging; inputs,
old reports and selected user packages are preserved. Trusted local filesystem
is required; this is not an adversarial path-race security guarantee.

The native validator's existing epoch-zero/nonnegative/<=1800s/Int32-timescale
policy remains. Thus admissible native integer values are at most
`1800*2147483647 = 3865470564600`, below JavaScript's safe-integer maximum.
Generic `timestampKey` tests exercise above-safe BigInt equivalence independently;
those values are explicitly rejected as native fixtures. No native validator was
relaxed to fabricate that test path.

## Executed checks and open gates

`node --test tools/annotation/native_aggregation.test.mjs tools/annotation/native_evaluation.test.mjs`
uses generated shape/header contract bytes and synthetic labels only. It checks
nonzero/disjoint ranges, overlap deduplication, tuple/raster/decoder/reference
conflicts, model/mode separation, original-ID collisions, changed receipts/assets,
publication-time mutations/cancellation, three-generation typed partition
constraints, legacy/missing/duplicate/oversized history refusal, retained existing
reference constraints without ancestor traversal, global reference
split leakage/100clip bound, canonical source reuse, collision preservation,
strict input bounds and the actual local CLI. It does not decode a real video or
execute Swift/Files export/Apple capture. Real references remain zero and accuracy
unmeasured. Actual Apple multiwindow capture, browser review/private access,
coverage design and a separately reviewed selection/denominator policy remain
required before a scalar full-rep score or accuracy claim.
