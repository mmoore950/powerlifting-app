# Generated two-window implementation handoff

October 8, 2026. Implements the approved
`generated-two-window-native-scope.md`; source and Windows contracts only.
Run17 reviewed47b406b excludes this change and failed before app-host tests or
attachment exports. No actual Apple two-window bytes exist yet.

## Native source

One additional XCTest method:
`BarFrameBundleExporterTests/testGeneratedTwoWindowAbsolutePTSOverlap()`.
It generates the scoped rotated128x96/15frame30fps movie, sequentially captures
A0.1...0.3 and B1/6...0.4, and asserts intended actual rational decoded times,
original nonzero tuples, distinct clip/analysis/capture IDs and common source SHA.
The shared helper retains the existing independent zero-tolerance raster oracle,
prediction hash/session/PTS, PNG/hash/geometry, raw ledgerText and embedded-image
byte checks; it also checks embedded ledger content and actual epoch/geometry.
Single-window source/attachments and default-no-capture proof remain intact.

Shared actual frames must have identical original tuples/PNG bytes/decoder and
geometry. Predictions remain separate and are not required equal. Assertions are
not observed decoder counts; mismatching output fails the fixture, never rewrites
the input. Source inventory now requires63 iOS methods, **not63 passed tests**.

One source plus two original ledger/prediction/bundle sets and their frames use
the approved names. The common explicit `XCTestCase.add` publisher snapshots all
files before attaching, with20files/1MiB each/2MiB combined bounds unchanged.
Intended4+5 frames need16 files; caps6perwindow would need19.

## Prepared reconstruction contract

`tools/annotation/generated_two_window_contract.mjs` exports:

- `selectTwoWindowAttachments(manifestBytes, observedMapping)`: <=1MiB strict
  manifest; exact one named group; complete one-to-one explicit reviewed rows
  `{logicalName, exportedFileName, suggestedHumanReadableName}`; failed associations,
  traversal, duplicate paths/names and unknown logical names refused. Original
  suggested/exported strings match exactly. No Xcode suffix/MIME/extension
  normalization is implemented or guessed.
- `validateTwoWindowSnapshots(Map<relativePath, Buffer>)`: approved bounded file
  set, existing strict native ledger/prediction validators, original source and
  PNG/header/geometry/hash checks, exact bundle content/raw bytes, exact rational
  expected PTS and shared original tuple/raster/decoder equality. Intended raw9/
  unique6/shared3 validated; returned synthetic/zero-observed/accuracyfalse is
  fixture context, not decoder authentication or annotation truth.

This is **not an automatic disk extractor**. A future successful reviewed job,
exact test verdict, both successful exports and verified artifact bytes are
prerequisites. The actual successful manifest must be inspected to supply the
explicit mapping. Disk integration must retain the existing regular/nonsymlink/
realpath and stable bounded-read checks; write unchanged bytes to a fresh owned
staging root, verifyAssets with shared top-level movie assetRoot, then rename
without overwrite. Actual naming/type behavior remains unobserved. The original
single-window reconstruction route remains available independently.

## Executed contracts and remaining gates

Four new Node methods cover exact mapping rejection, substitutions/identity/
equivalent-component conflicts and byte budgets. Explicit header-shaped PNG bytes
and non-movie source strings are labeled synthetic contract fixtures. Both strict
evaluators and the existing aggregate ran with generated all-unreviewed envelopes:
raw9/distinct6/shared3/reviewed0/observed0/unreviewed6, no baseline conflicts,
null scalar metrics, accuracyfalse, continuityunverified and unknown groups.
Different shared predictions are accepted and originals preserved.

Full relevant Node verification:27methods passed, no skips; final results are
recorded in docs/status.md. Native Swift compilation/XCTest execution cannot run
on this Windows host. Existing limits/production capture/detector are unchanged.
No push/newCI before leader review. Native extraction cannot be estimated until
reviewed successful exported bytes exist; re-estimate from the observed mapping.
Source handoff has no hard deadline. Private-browser, Files provider/device and
real accuracy/release gates remain separate.
