# Next user-facing feature: filtered lifter profile best performances

Scope assessment, October 8, 2026, 07:21 ET. No implementation approval or native pass is implied.

## Evidence and recommendation

The product brief requires native lifter profiles as well as meet history. In
`App/OPLBrowserView.swift`, both search and rankings open `OPLHistoryView`, which
shows paginated source rows and freshness but no profile summary. The service
offers search, history and rankings only (`DataService/src/server.mjs` and
`query.mjs`); `OPLModels.swift` has no profile DTO. Calculators already expose
editable warm-up steps and manual meet attempts. This profile gap is a concrete
user-facing next slice independent of private videos or Apple access for source
implementation and service verification.

Recommend adding a best-performance section above the existing history for one
exact source name. Require explicit source sex category, equipment and event;
offer tested designation. Show best positive total, squat, bench, deadlift and
DOTS with each winning row's meet/date and category. Separate lift bests can come
from different meets: never sum them into a competition total. Missing eligible
values display as unavailable. Preserve source suffixes and state that an exact
source name is not a verified cross-version identity or a federation record.

## Bounded implementation proposal

1. Add a version-pinned `/lifters/{id}/summary` read, limited to one result
   containing at most five winning source rows. Query the complete selected
   snapshot for that exact name, not the downloaded history pages. Use prepared
   SQL and the existing snapshot lease and HTTP query pool; retain existing
   admitted query timeout, queue limits and cleanup ownership.
2. Reuse the current rankings category/eligibility semantics: exclude DQ/DD/NS
   and unsanctioned rows, retain eligible guests, use positive selected metrics
   and best-three lifts. Resolve ties by date then source row ordinal. Factor
   shared predicates only as needed to avoid two conflicting definitions.
3. Return the existing versioned page envelope with zero or one summary DTO and
   no cursor. Reuse repository cache keys and `OPLPageStore` recovery/cancellation
   for the summary. The summary and history must show the same selected version;
   during recovery, hide or clearly mark an older summary rather than presenting
   two versions as one profile. Retain cached offline content and freshness.
4. Add a small profile filter/summary section to the existing native destination;
   keep full history readable and retain its explicit repeated-division-row
   wording. Do not infer lifetime bests from the first history page or label row
   counts as unique meets.

Likely files: `DataService/src/query.mjs`, `rankings-plan.mjs`, `server.mjs` and
focused service tests; `Packages/LiftingCore/Sources/LiftingCore/OPLModels.swift`
and repository contract tests; `App/OPLBrowserView.swift` with page-store tests
only where version recovery requires a material change. No hosting, scheduler,
accounts, cross-name identity merge or video work is included.

## Verification and limits

Service fixtures should cover a winning row beyond the first history page,
different winning meets per metric, failed/missing values, disqualified and
unsanctioned rows, category separation, source suffixes and deterministic ties.
Demonstrate added/corrected/removed winners across two immutable versions and
version-pinned reads. Swift contract/cache checks should cover malformed DTOs,
offline reuse and expiration recovery where applicable. Native compilation and
screen interaction need subsequent Apple execution; Windows checks cannot
establish them. Production recurring freshness and reachable service setup
remain separate existing gates.

## Estimate and decision

Assessment complete. Leader decision is next; no reliable review ETA exists
before a response. If approved, source and focused Windows service evidence are
estimated at 45–75 minutes, with uncertainty in shared filter factoring and
summary/history recovery coordination; there is no hard source deadline.
Re-estimate after contract sizing or a review correction. A later authorized
native run retains the existing build 8 / test 10 / job 30 minute limits and
provisional 15–22 minutes after runner start. Neither source completion nor a
successful native run completes production freshness, private-video accuracy or
release readiness.
