# Ranking query proposal and bounded profile

October 7, 2026, 3:40 PM ET. Existing genuine snapshot only; no upstream request, import, pruning or index/schema change. Normal leases and last-read bookkeeping were written outside the immutable SQLite file. Evidence is ignored `artifacts/ranking-plan-profile.json`.

## Proposal

`DataService/src/rankings-plan.mjs` shares the original eligibility/filter SQL and offers an explicit experimental narrow projection. The original window query carries all result columns through per-name ranking and global sorting. The proposed query carries row ID, exact source name, metric and date, materializes the top `limit+1` winners, then fetches their complete records by primary key. Filters remain before best-per-person selection. Positive metrics, DQ/DD/NS exclusion, sanctioned/guest semantics, date/name/row-ID ties and cursor signatures remain the same.

Serving continues using the original wide query. The optional `executeQuery(...,{narrowRankings:true})` is used only by the profiling worker and synthetic test. No new runtime dependency or database index is required by this proposal.

## Plans and measurements

Node SQLite reports version 3.53.3. Both plans use `result_category_total (Sex,Equipment,Event,TotalKg DESC,Name)` for category/positive-total selection. Federation, tested and date are residual filters. Both plans show temporary B-trees for per-name and overall ordering. The proposal adds materialized winners and primary-key fetches; it does not eliminate the broad category scan or sorts.

One bounded run used F/Raw/SBD/tested/IPF/from2020 total, limit25, snapshot `bac56dbcedd8cd351765f1d9af6c99e43887819955191a37b242db31850b1ed7` (4,043,255 rows):

| Serial case | Worker latency | SQLite duration | Child reported peak RSS |
|---|---:|---:|---:|
| Original wide baseline | 7,057.8 ms | 6,990.6 ms | 78.8 MiB |
| Narrow proposal first | 1,032.5 ms | 969.1 ms | 78.9 MiB |
| Narrow proposal repeat | 980.1 ms | 919.7 ms | 79.6 MiB |

All three result payloads, including full records, version, source and next cursor, matched exactly after excluding duration. Each returned25 rows. Run completed9.08seconds; all pools closed with zero active/queued workers. Maximum three serial queries, one active child, normal ten-second admitted deadline; tool cancellation timer60seconds after initial metadata. OS/filesystem/event-loop cleanup can overrun timers, so no whole-tool hard wall is claimed. RSS is process-reported before final IPC, not an exit/fleet maximum; SQL temporary-disk use was not measured.

OS/filesystem cache was **uncontrolled**, with the wide query first and the narrow queries later. The snapshot had already been queried earlier today. The earlier wide-query diagnostic also fell from7.32seconds for its first page to1.06seconds for continuation. Therefore these results **do not establish a causal speedup** or memory reduction from narrow projection. They establish executable compatibility and expose limited original-query margin under the ten-second deadline. No throughput or production SLA inference is supported.

Reproduce the bounded tool with `node DataService/tools/profile-rankings.mjs --root artifacts/opl-service`; each invocation is a new profiling run, not a scheduler. Do not repeat against genuine data without a specific measurement question and bound.

## Semantic evidence and recommendation

Focused synthetic test checks independent expected exact-name/row/date ties; suffix identities; filter-before-max; guests; DQ/DD/NS, unsanctioned and failed/null/negative exclusion; literal `+`, `-74`, `100+` classes; inclusive dates; bodyweight boundaries; all five metrics; complete DTOs and every continuation page against the original. Four existing service suites also passed after extraction. These fixtures do not establish native or production behavior.

Recommend keeping the serving default unchanged for now. The narrow projection is a low-storage candidate, but the order/cache confound must be resolved before attributing performance benefit. A subsequent explicitly bounded warm paired original/proposal comparison in alternating order could address that question; this run's fixed three-query budget is complete. A dedicated `(Sex,Equipment,Event,Federation,Tested,Name,TotalKg DESC,Date DESC,row_id DESC)` index is a separate higher-cost alternative: it could narrow this exact filter and support per-name order, but optional federation/tested queries, other metrics, added snapshot bytes and import time need measured tradeoffs. No such index was built or selected.

Next independent authorized task is local video evaluation schema/hash/scoring tooling. Native compile/device accuracy and recurring hosted refresh remain separate external gates.
