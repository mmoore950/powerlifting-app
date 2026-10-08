# Run19 core compilation failure

October 8, 2026, 07:47 ET. [Run37771657886](https://github.com/mmoore950/powerlifting-app/actions/runs/37771657886),
job113292468047, exact revision `b06eb77497d1f9551709954c974b59ef6f951b96`,
completed failure. No retry was dispatched.

- Setup succeeded: actual11 POSIX supervisor methods passed7.388s,29 orchestration
  methods passed11.810s,5 pure selector/receipt methods passed0.007s. Captured
  simulator SDK receipt is18.5. Pure selectors do not boot a simulator.
- macOS `swift test` failed compilation with exit1. The compiler identifies
  `OPLProfileTests.swift:27`: stored private `name` conflicts with inherited
  `XCTestCase.name`, causing accessibility/override and subsequent ambiguity
  errors. No core test pass is claimed. This is a concrete source error, separate
  from prior simulator migration waits.
- Narrow source correction renames only the test fixture's stored property and
  its four associated uses to `sourceName`; URLQueryItem.name remains unchanged.
  No production profile behavior, test inventory or assertion is changed. The
  correction is uncompiled/unrun on Windows and needs later Apple verification.
- HTTP setup/contract, simulator preparation/build, UI/non-UI and both attachment
  exports skipped. All67 iOS tests and SDK-matched live runtime behavior were not
  exercised. No live runtime selection receipt exists for this execution.
- Cleanup phase0, `owned-ui-cleanup.json` cleanupComplete true with reason
  `preparation-not-started`. No simulator was created by this run; this is not
  deletion evidence for a created simulator. Native phase supervisor/outer/
  boot/test receipts are absent because those phases were never launched.

Verified diagnostic artifact11548436735, ZIP102529 bytes, SHA256
`af18f4f5627c37c53881423b16640d60f2ad8553e4de162e430463e7825f1abe`;
203 entries,147659 uncompressed bytes. Retained under ignored
`artifacts/native-ci-runs/37771657886/diagnostics`, with traversal/absolute/colon/
backslash/symlink refusal and1000-entry/4MiB-per-file/32MiB-total bounds. Metadata
confirms exact SHA; remote expiry October11 at07:43:01 ET. Local copy retained.
Full artifact11547912850 was uploaded; bounded diagnostic evidence suffices here.

Diagnosis and narrow source correction complete. Leader review precedes any
future push/CI; no automatic retry. No reliable native-readiness ETA exists until
the reviewed source compiles and a later run supplies actual readiness/test/export
receipts. Existing build8/test10/job30 limits remain; process completion is separate
from feature/production/private-video/release acceptance. Approved shared native
additional-filter editing continues independently.
