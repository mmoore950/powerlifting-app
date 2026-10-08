# Profile additional-filter editing scope

Scope only, October 8, 2026, 07:44 ET. No new implementation or CI.

## Evidence

`OPLHistoryView` currently preserves and displays ranking drill-down filters and
can clear the additional ones, but cannot edit federation, date range, bodyweight
range or exact source class. `OPLRankingsView` already has six matching text inputs
and explicit Apply behavior. `rankings-plan.mjs` supplies their shared service
validation for rankings and full-snapshot summary. No additional dataset semantics
or API route is needed.

## Recommended small slice

- Add one local SwiftUI additional-filter editor reused in rankings and profile:
  exact federation, inclusive from/through dates, minimum/maximum actual bodyweight
  in kg, and literal source weight-class label. Reuse existing keyboard types,
  accessible field labels and source-class explanation. Keep category/tested controls
  and profile metric units unchanged.
- Use a small dictionary of draft text for these six fields. Populate the profile
  draft from inherited applied scope; keep the applied scope visible separately.
  Typing does not fire a request or relabel existing values. Explicit Apply trims
  optional outer whitespace, removes empty optional values, preserves other
  category/tested filters and starts one query transaction. Existing profile
  scope/response guards hide previous bests on application of changed filters.
- Replace only the equivalent six ranking draft fields with the same editor and
  optional-text application helper. Preserve its explicit Apply behavior, selected
  metric/category/tested context, and drill-down passed applied dictionary. Keep
  reset/clear drafts synchronized so cleared values cannot silently reappear.
- Preserve existing exact class semantics including `+`, `120+` and negative
  source labels. Do not reinterpret classes, round bodyweight, infer federation
  records or add currently unsupported country/age/division filters.
- Keep the existing service predicate validation authoritative for dates,
  ranges and categories. Invalid applied filters surface through the current
  profile/ranking error and explicit retry flow; no separate approximate Swift
  validator. Display draft-versus-applied state and the retained all-category
  history clearly when a summary request fails. Native offline cache reuse remains
  keyed by applied filters and selected version.

Likely files: `App/OPLBrowserView.swift`, one small pure application helper alongside
`OPLProfileScope` in `OPLModels.swift`, focused cases in `OPLProfileTests.swift` and
the existing profile service fixture only if it lacks an applicable rejection
case. No repository/schema/scheduler/hosting/architecture change is proposed.

## Focused evidence and estimate

Verify draft edits cannot change the applied dictionary, empty optional removal
preserves core category/tested values, unknown keys are omitted, literal class
labels survive, inherited filters initialize correctly, and reset clears both
draft and applied optional fields. Existing service guards should reject reversed
dates/bodyweights, invalid dates and class labels identically for summary and
rankings. Source inspection must retain stale-scope hiding and existing retry,
offline and version-change handling. Actual keyboard, VoiceOver, Dynamic Type,
SwiftUI task ordering and rendered states still require Apple interaction.

Scope complete; leader decision next, review ETA unavailable before a response.
If approved, source/checkpoint15–25 minutes, no hard source deadline, uncertain
shared editor binding and draft/application coordination. Re-estimate after a
review correction. Run19 remains on exactb06eb77 with67 expected iOS methods;
later filter edits would be excluded. A future test addition changes the source
inventory only and must not be counted as a run19 pass. Run19 outcome remains
priority, provisionally15–22 minutes after runner start, build8/test10/job30
limits. Native feature validation, continuing upstream freshness and release
remain separate gates.
