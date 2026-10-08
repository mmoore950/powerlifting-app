# Product accessibility and error-state source pass

October 7, 2026. Bounded inspection/source fixes across plates/reverse, training/attempts and Competition. **No native compilation, visual, Dynamic Type or VoiceOver execution.** This is an inventory and source checkpoint, not an accessibility conformance claim.

## Concrete findings and fixes

| Surface | Source finding | Change |
|---|---|---|
| Target/rep/training/attempt inputs | Several fields relied on placeholder or nearby unit text once editing began | Stable accessibility labels include field purpose and current units; completed reps include supported range |
| Reverse loading | Generic per-side text did not explicitly describe both-side update in accessibility hint | Weight/unit/per-side label, selected pair count and availability/both-side hint |
| Load summary | Separate plate-weight and multiplier labels could require users to combine the relationship | One per-side plate/count label on the noninteractive row; existing labeled plate diagram retained |
| Warm-up reps | Repeated `Reps` controls were ambiguous across editable sets | Each repetition stepper names its set and current value |
| Errors | Plain orange error paragraphs had limited explicit error context | Shared symbol/text error view with `Error:` accessibility label; loading and retry remain labeled controls |
| Competition filters | Date/bodyweight/raw-class/name purposes relied on placeholders | Persistent accessibility labels with units/optional/date context; short and overly long search inputs show guidance |
| Competition setup | Prototype endpoint/API/Windows details surfaced as ordinary setup | Discoverable data Settings opens connection status plus explicitly named Developer connection/diagnostics disclosure; endpoint/version/technical setup live there |
| Competition pages | Inline result version prefix distracted from freshness meaning | Result save date stays inline; configured endpoint/current full dataset version available in Developer diagnostics |
| Competition results | `S/B/D` abbreviations can obscure the lift names | Accessibility text says squat/bench/deadlift and retains missing/failed wording |

Inspection found that attempt percentage steppers already have distinct opener/second low/high text, and plate colors already have visible weight/unit text plus an accessible diagram description. Those source observations do not establish usable contrast or actual VoiceOver behavior. The earlier sizing report's generic “Min/Max” ambiguity description did not apply to the already descriptive attempt percentage labels.

No endpoint was invented. Without a configured/reachable service the main screen says competition data is not connected/unavailable, with a discoverable Settings action. Source dataset date, successful service check, device save time, offline/stale wording and retry remain visible. Moving technical controls does not configure hosting or make loopback reachable on an iPhone. No repository/client/cache/recovery-generation logic was changed in this pass.

## Actual verification and next native checks

Source inspection of all changed view/control bindings plus `git diff --check` passes. No implementation-mirroring UI tests were added for these reversible label/copy changes. Native execution remains the meaningful check:

- VoiceOver labels/value/adjustment on both reverse plate steppers and repeated warm-up controls; no lost increment/decrement action or duplicate focus caused by modifiers.
- Target/weight/unit edits preserve numeric value announcements, optional filters preserve editing context, and plate summary count/weight is announced together.
- Errors, stale/offline and “missing”/“failed” rows are understandable without color. Dynamic Type, contrast, target size and layout clipping require rendered checks.
- Data Settings is discoverable from no-connection and connected screens, Developer disclosure remains operable, failed connect errors remain visible, source/check/device save dates are retained and Try again/load more behave correctly.
- Version expiry, busy/timeout and offline cache still need existing native lifecycle/XCTest execution; source-only copy changes do not validate recovery.

No reliable full app/native readiness estimate until repository/runner approval and actual Apple diagnostics; future CI hard30minutes is a job bound, not release readiness.
