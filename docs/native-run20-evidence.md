# Run 20: diagnosis from existing artifacts

Inspected October 8, 2026 without dispatching another workflow.
Run: https://github.com/mmoore950/powerlifting-app/actions/runs/37773690035
Job: 113299195700. Revision: cb26556475b1080ff58796b826c76f2220e1efe4.

## What actually ran

- macOS core: 47 executed, one skipped, zero failures (46 passes).
- Separate Swift-to-Node HTTP contract: one passed, zero skipped.
- Unsigned simulator build succeeded. Selected runtime was iOS 18.5.
- The UI smoke test launched the app and opened Plates, Training, Attempts,
  Competition (disconnected), and Bar path (no video). One UI test passed in
  74.608 seconds. Its xcodebuild command completed successfully in about 231 seconds.
  These results establish launch/tab rendering only, not all feature behavior.

## Exact failure

After UI success, test-unit-ready ran `xcrun simctl list --json` with a ten-second
child timeout, despite 328 seconds remaining in the shared test budget. It timed
out. During cleanup, process-group probes and a signal reported PermissionError
(Operation not permitted). The supervisor returned 125 after 19.945 seconds.
The outer wrapper did not accept its cleanup receipt. The non-UI simulator tests
were never launched. No failing app assertion is recorded in this phase.

The inventory command's underlying stall and permission-error cause remain
unproven. Increasing its timeout is not an established cure. The total test phase
ended after 252.554 seconds of its 560-second budget, not at the overall deadline.

The workflow's success-only screenshots step was skipped, including UI screenshots
from the successful test. The full xcresult artifact was preserved remotely.
Later simulator cleanup and both artifact upload steps succeeded.

## Retained evidence and recovery decision

Downloaded diagnostic artifact 11549942012 (214622 bytes) to
`artifacts/native-ci-runs/37773690035/diagnostics.zip`. SHA256 matches GitHub's log:
`2d9872c7412e669a0d82eac5b8ef5f36a63527b6562c32e41c7f4820824db446`.
Read test-phases.json, test-ui.log, test-unit-ready.log and its outer receipt
directly from the ZIP. No new native execution occurred.

Do not blindly retry or extend deadlines. The next native change should isolate
the already successful UI result/export from the remaining simulator tests and
avoid using an additional full simulator inventory as a prerequisite for starting
those tests, while retaining verified destination ownership for cleanup. Review
that change locally before any run. This is a proposed recovery direction, not a
verified fix for CoreSimulator. Existing full-result artifact 11549752132 can be
used to recover screenshots with xcresulttool on an Apple environment without
running the app tests again.

No new CI run is authorized. If the human approves a later experiment, propose
one run maximum, no automatic retry, existing 30-minute job hard limit. Diagnosis
is complete; a native validation ETA requires that approval and an execution
environment. No claim of release readiness or real-video accuracy follows.
