# Strict native evaluation wrapper: source proposal

October8,2026, approximately02:37ET. Accepted source proposal, retained as the scope record. Implementation and actual checks now appear in [status.md](status.md) and [local-annotation-guide.md](local-annotation-guide.md); [generated-native-extraction.md](generated-native-extraction.md) records the source-only attachment route. No new CI dispatch was performed. Addresses integration-gap6 without changing detector, reference/prediction schemas, generic scorer or accuracy policy.

## Minimal entry point

Add `tools/annotation/evaluate_native_bundle.mjs`, importing existing `validateLedger`, `verifyAssets`, `verifyNativePrediction`, `adaptLabels`, strict JSON parser and `scoreVideoTraces`. One explicitly selected native capture directory, label download and local media root. Proposed CLI:

```text
node tools/annotation/evaluate_native_bundle.mjs
  --ledger <completed native ledger.json>
  --labels <matching actual hub-labels download.json>
  --asset-root <root containing the recorded relative source movie>
  --output <new local evaluation directory>
  [--existing <project reference registry for partition checks>]
```

No `--manifest` input, purpose override, free-form report or previously adapted reference as an alternate route. Therefore renaming a PyAV development draft cannot make this entry point treat it as native. The generic scorer remains available for valid synthetic/diagnostic uses and retains `accuracyGatePassed:false`. The wrapper is an additional strict path, not a change claiming every scorer invocation is native.

## Execution and binding

1. Read bounded ledger/labels/optional existing registry into immutable byte buffers; check stat and actual byte length, parse with duplicate-key rejection. Require the distinct `native-analysis` producer contract BEFORE evaluating anything. A flag or filename alone never satisfies it.
2. Invoke existing actual local media/image verification, including safe realpaths, <=500MiB source, <=32MiB PNG payload and matching PNG headers. Read actual adjacent `prediction.json` into one bounded buffer. Require its digest/schema and clip/model/mode/dimensions/count/exact timestamp components to match the authoritative ledger. Use those captured prediction bytes for the rest of this run, never reread an independently selected predictions path.
3. Invoke `adaptLabels(...,{purpose:'native-scoring',predictionBytes,existing})` against the captured ledger digest. References come solely from strictly validated reviewed labels on those frames; unreviewed remains explicit. Existing registry checks partitions and duplicate clip IDs; it cannot contribute annotations into this clip's score.
4. Serialize the resulting manifest once to the exact reference bytes that will be published. Compute reference SHA-256. Score that in-memory validated manifest against the parsed, already verified prediction buffer using the existing pure `scoreVideoTraces`; avoid `evaluateVideoFiles` rereading reference/prediction files. Do not create/infer point labels, train a model, interpolate PTS or promote accuracy gates.
5. Publish into a fresh sibling staging directory and final rename only after all verification/scoring succeeds. Refuse an existing final destination. Proposed files: exact `references.native-reference.json`, unchanged `prediction.json`, unchanged `ledger.json`, adapter report, score report and `evaluation.json` binding their byte digests plus input label SHA. Any failure publishes no completed evaluation directory; preserve prior outputs. Media/PNG files remain in the original explicit roots, without copying/uploading them.

`evaluation.json` is a new audit receipt, not a reference/prediction schema expansion. Minimum fields: wrapper contract/version; successful native association check; ledger/prediction/reference/label/adapter-report/score-report SHA-256; clip ID/media SHA/relative path/upright geometry; source group/split/synthetic flag; model/mode/analysis/session identity; reviewed/unreviewed counts; policy and created-at. Preserve exact ledger/prediction bytes; consumer can recompute reference/report digests. Do not include absolute private paths in published receipts. This binds a local evaluation's inputs/outputs, not cryptographic producer origin or unchanged files forever. Trusted local filesystem remains required.

## Bounds and planned tests

- Ledger/prediction <=1MiB each, labels <=4MiB, optional existing registry <=32MiB; native <=16frames/1s, source <=500MiB, PNG payload <=32MiB. Reuse existing60s per-file media hash cancellation; inspect actual buffer counts after reads. Target receipt/reference/score/report output total<=8MiB and cooperative overall120s checks around phases. Blocking I/O may exceed checks; no external hard process deadline is implied. No new runtime dependency or file scanning.
- Planned Node contract tests: valid clearly synthetic native input produces all expected exact digests and still false accuracyGatePassed; PyAV and renamed development manifest refused before output; changed ledger/labels/prediction/media/PNG mismatch refused; rational-equivalent component substitution refused; partition/foreign-review metadata refused; failed validation creates no final output; prior output remains unchanged; unreviewed/occluded cases retained; saved artifact digest verification detects changed reference/score bytes.
- Use independent expected hashes/normalized known points/visibility/counts for assertions. CLI test checks actual disk files and exclusive final output. Existing40adapter tests continue to cover component/model/mode/clip/schema distinctions; new tests should cover wrapper orchestration/binding rather than duplicate every validator case.

## Actual generated-native execution route

The ninth run at4a700f5 executes generated app-host capture assertions, but tests delete their temporary bundles. Its ordinary logs/XCResult therefore do not yet supply a preserved native movie+PNG+ledger+prediction directory to the Node wrapper. A passing XCTest is not an actual wrapper round trip. No private/public media acquisition/upload is proposed.

After leader review, smallest hosted option: retain **one generated rotated fixture only** as explicitly named XCTest attachments (movie, ledger, prediction and captured PNGs; optionally bundle). Export through the existing XCResult attachment path, reconstruct files from the named attachment manifest under a fresh bounded local directory, then invoke the strict wrapper with clearly synthetic hand-reviewed fixture labels. Respect recorded relative filename/hash. Keep generated capture PNGs distinct from the five UI smoke screenshot names/counts. Synthetic fixture labels are adapter tests, not observed hub truth. This requires a scoped test/evidence-export change and an actual subsequent approved Apple run; it is not authorized merely by this proposal.

Alternative: an authorized local Apple developer harness saves the generated native directory and runs Node on that same local host. No Mac currently available to the user; do not assume this route exists. Hand-built Windows native-shaped fixtures remain contract evidence only until one actual Apple output crosses the wrapper boundary.

## Estimate and next decision

Scope checkpoint5–10minutes from dispatch, no hard deadline. Proposed implementation25–40minutes after approval (buffer/receipt/output ownership is uncertainty), then local Node tests. Actual Apple-to-wrapper evidence requires preservation/export route and a later run; estimate10–18minutes after runner start with queue/encoder/simulator uncertainty, existing hardtest10min/job30min excludingqueue. The currently running ninth build/test can complete independently. Browser/privacy, private Apple access, whole-rep/registry and representative-accuracy gates remain open.
