# OpenPowerlifting local service — Milestone 3

## Outcome and limits

Runnable Node 24 / SQLite prototype, tested on Windows. It imports full official CSV ZIPs into immutable indexed snapshots and serves native-client-compatible JSON. A successful local run is not production continuing freshness. No permanent scheduler, public host or native app connection has been installed.

Dependencies are exact-pinned with `DataService/pnpm-lock.yaml`: csv-parse 7.0.3 (MIT), yauzl 3.4.0 (MIT), crc-32 1.2.2 (Apache-2.0); yazl 3.3.1 (MIT) is a test-only ZIP fixture writer. Keep dependency license files when distributing the service. Reviewed official [CSV stream/options docs](https://csv.js.org/parse/api/stream/), [yauzl](https://github.com/thejoshwolfe/yauzl), [CRC implementation](https://github.com/SheetJS/js-crc32), [yazl](https://github.com/thejoshwolfe/yazl) and [Node 24 SQLite docs](https://nodejs.org/docs/latest-v24.x/api/sqlite.html). The latter was fetched with PowerShell because the web fetch failed. Built-in DatabaseSync/StatementSync were exercised on Node 24.19.0; no external SQLite binding/native install.

## Reproduce

From the project root, install packages with pnpm 11+, using the locked versions:

```powershell
pnpm --dir DataService install --frozen-lockfile
node --test DataService/test/service.test.mjs
node DataService/src/cli.mjs refresh
node DataService/src/cli.mjs dataset
node DataService/tools/probe.mjs
node DataService/src/cli.mjs serve --port 8787
```

Current workspace pnpm executable is `C:\Users\micha\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd`; it is not on PATH. The bundled Node executable is on PATH. Use the full pnpm path here. Service artifacts default to `C:\codex\powerlifting-app\artifacts\opl-service`, ignored by Git. `--root` selects an explicit service directory. The probe creates a temporary loopback server, checks genuine HTTP responses and closes it; it saves response evidence under ignored artifacts.

Explicit local import (fixture/diagnostic, not an upstream freshness check):

```powershell
node DataService/src/cli.mjs import --file 'C:\path\snapshot.csv' --root 'C:\path\service' --minimumRows 8
```

## Read contract

Review correction: `/dataset` pins `latestValidatedSource`, `sourceDate` and `validation {version, validatedAt}` to its selected immutable content version. Global refresh `status` remains separate; `statusMatchesDataset` tells whether accepted status metadata refers to that content version. Refresh stores explicit `validatedVersion` (legacy lastPublishedVersion is a migration fallback). Source metadata from another version never overrides the selected manifest, including publication/status gaps. A same-content newly dated archive can update accepted source metadata for that same version. Fast-path checks preserve import time only for a matching version. Malformed/null cursor objects return stable INVALID_CURSOR.

| Route / query | Behavior |
| --- | --- |
| `/dataset` | Content version/manifest, published time, latest validated source metadata, last successful check/import/failure/retry, source age and separate check/source stale flags. |
| `/lifters?q=Taylor%20Atwood` | Literal accent-normalized, case-insensitive **prefix** search, 2–128 characters; returns exact source name and encoded ID. |
| `/lifters/{id}/results` | All source rows for that exact source name, newest meet first. Division duplicates remain visible; history does not claim deduplicated meets. |
| `/lifters/{id}/summary?sex=F&equipment=Raw&event=SBD` | Up to five best-positive metric winning rows for the exact source name across the complete pinned snapshot; one summary or no source name, no cursor. |
| `/rankings?sex=F&equipment=Raw&event=SBD` | Best positive performance per exact source name among eligible filtered rows. Requires all three categories. |

CLI uses `query --kind search/history/rankings/summary` with equivalent `--key value` parameters. All data queries support `version`, `cursor`, and `limit` (1–100). Rankings and profile summaries additionally support `tested=yes` or `not-designated`, exact `federation`, inclusive `from`/`to`, actual recorded `bodyweightMin`/`bodyweightMax` in kg, exact raw `weightClass`, and rankings select metric `total/squat/bench/deadlift/dots`. Summary returns each available metric separately, with its winning full source row and echoed category/filter scope; different winners may come from different meets. Summary does not accept metric/cursor, and missing eligible values are omitted. Unknown/duplicate parameters and invalid categories are errors. Age, country, division, parent-federation and ratified-record filters are not exposed yet; no silent ignore. Weight-class filters are literal labels, not normalized cross-federation classes. Gender category/equipment/tested semantics remain the source's categories, not a claim about an individual's equipment or testing.

Every response/page is pinned to one content version. Opaque cursors include version, query digest and offset; mismatched filters/version are rejected. Ordering is deterministic; old snapshots remain readable after publication. Search uses normalized name then exact name; history uses meet date then source-row ordinal; rankings use metric/date/name/ordinal. Source suffixes such as `#1` are preserved. Name-derived IDs avoid merging equal display names with different suffixes; a source rename can change ID and this prototype has no cross-version identity alias map. Cache keys must include version. Cursors are pagination state, not authentication tokens.

Rankings exclude DQ/DD/NS, unsanctioned rows, and missing/nonpositive selected metrics; fourth attempts are not used for best-three lift metrics. Guest results remain eligible as dataset performances. Results are **best performances in the filtered dataset**, not federation-ratified records. Missing numerical values remain null; negative failed attempts/best-lift fields are preserved in histories. Kilogram amounts are stored as integer hundredths and returned as kg. All 42 columns plus additive unknown fields are retained.

HTTP SQLite reads now use bounded child-process isolation: two active queries/eight queued, five-second queue wait and ten-second admitted-job termination timer, with parent-owned controller/reader-PID leases retained until confirmed child close. The 30-second HTTP request timeout is separate. Whole-request/cleanup timing and process RSS are not hard bounded by these settings; direct CLI/library queries remain synchronous. See `query-isolation.md` for actual synthetic cancellation/concurrency evidence and limits. Loopback binding is intentional for this prototype. A native phone cannot reach Windows `127.0.0.1` directly; an authorized reachable host/API configuration is a separate integration step.

## Publication, validation and failure recovery

1. Acquire `refresh.lock` using exclusive creation. Refuse overlap; never guess that an old lock is safe to remove while its process is alive.
2. Check official landing revision/date and archive HEAD metadata, bounded to 20 seconds/request and 256 KB landing content. Reuse the previously downloaded archive only after ETag/revision match and local SHA-256 matches the recorded inspection. If changed, stream download with a 120-second timeout and 256 MiB cap; compare response ETag to checked ETag.
3. Stream one CSV from ZIP, validate actual uncompressed byte count and CRC, fatal UTF-8, BOM/quoted commas/newlines/empty fields, record/column bounds, required values, enum categories, calendar dates, numerical shapes/ranges. No custom CSV parser. All missing original columns fail; additive fields are retained. Small snapshot rejection uses at least 95% of the reported/previous row count; it is a protective threshold, not proof of completeness.
4. Parse into a staging SQLite database. Batch commits, bounded cache/name set, disk temp sorting. Preserve signed/missing facts. Create search/history/category-total/date indexes, ANALYZE and run SQLite integrity_check. Do not claim meet-result authenticity or total/lift/federation rule consistency from these structural checks.
5. Use SHA-256 of actual CSV bytes plus importer schema version as immutable version. Close the database, rename the fully built directory, then publish `current.json` by same-directory temporary-file rename. If rename/publication fails, retain the last pointer. No serving DB is overwritten. Readers pin immutable versions with lifecycle leases; publication records the previous version for rollback. Dry-run-default retention protects current/rollback/count/active/recent versions. See `snapshot-retention.md`; no genuine pruning or recurring retention was run.
6. Persist check/attempt/success/failure/retry separately. Successful unchanged checks never imply newly dated source data. If a newly fetched archive has identical CSV content, revalidate it, keep the same cache version, and store the latest accepted upstream metadata separately.

Actual source edge cases: 371 bare `+` class labels and 25 negative labels (such as `-74`) exist in this archive. These are preserved as literal upstream values, counted as warnings, and not silently reinterpreted as numeric classes. Rust weight-class source was inspected for serialization, but the meaning/data quality of every atypical record was not individually adjudicated.

## Scheduler-ready entry

```powershell
.\DataService\scripts\run-refresh.ps1
# Manual forced revalidation:
.\DataService\scripts\run-refresh.ps1 -Force
```

This wrapper starts a hidden child, saves stdout/stderr, and enforces a **hard 1,200-second wall limit** (configurable down to one second). It terminates the child on timeout and only recovers its lock if the recorded PID matches and is no longer alive; timeout/failure and retry remain visible. The importer also checks a 20-minute elapsed budget while streaming and before publication, but direct CLI synchronous indexing cannot be interrupted by that cooperative check. Use the wrapper for the hard bound.

Other limits: 2 GiB uncompressed CSV, ten million result rows, 1,000 ZIP entries, 100 columns, 64 KiB record, 4,096 characters per cell, 50,000 cached names and 64 MiB SQLite import cache. These are resource guards, not an exact whole-process memory guarantee; measured process peak is below.

For eventual Windows Task Scheduler, configure the wrapper action every 15 minutes; the command checks `retryAt` or `nextCheckAt` and skips while not due. Successful checks schedule the next upstream check six hours later; failures use 15-minute / one-hour / six-hour backoff. The scheduler's 15-minute polling quantizes retries/checks by up to 15 minutes. No task was registered. Ongoing production acceptance requires observed scheduled runs against upstream and monitoring, not this configuration text or manual execution.

Manual crash recovery only after proving the owner is dead:

```powershell
node DataService/src/cli.mjs recover-lock --pid RECORDED_DEAD_PID
```

Never remove an active lock. Interrupted staging/download files may need operator cleanup after confirming they are unowned. Snapshot retention and explicit dead catalog-owner recovery are documented in `snapshot-retention.md`; no automatic deletion job is installed. No deployment or hosting cost has been incurred.

## Measured evidence — 2026-10-07

- Genuine official archive reused (170,132,164 bytes), revision `199bb416`, SHA-256 `f97c5dce230843d871e42be76359efbe01694838285c3b82530f13e71a5cbba8`.
- Full CSV bytes verified: 826,444,366. Result rows: **4,043,255**; distinct exact source names: **1,015,391**. Landing reports 4,043,256 rows, equal to result records plus one header; that is an observed difference, not a verified description of their counting method.
- Content hash `0dec66dfd43a288742b8875ff8667aeaab1866496611b910b42ddc550d4c2b97`; published version `bac56dbcedd8cd351765f1d9af6c99e43887819955191a37b242db31850b1ed7`.
- Full initial successful import: **118.13 seconds**, roughly 90 seconds parse then indexes/integrity. SQLite file **1,343,746,048 bytes** (~1.25 GiB). Sampled RSS peak 271,556,608 bytes; process-reported peak 337,502,208 bytes (~322 MiB). Measurement is on this Windows host/cache, not a universal SLA.
- Forced full revalidation through scheduler wrapper: **90.55 seconds**, unchanged version, no reindex/publication; later due-only invocation correctly skipped. Local isolated one-second timeout demonstration killed the child, recovered only its dead-PID lock and logged failure/retry. Logs are under ignored `artifacts/opl-service/logs` and `artifacts/opl-timeout-proof`.
- Real loopback HTTP probe found Taylor Atwood and histories, plus filtered F/Raw/SBD/tested/IPF/2020+ total best performances. Example first results were Brittany Schlater 756.5 kg, Sonita Muluh 751 kg, Alexis Jones #1 704.5 kg in this dated snapshot; these are not ratified-record/current-website claims. Probe HTTP-to-response-header timings: search ~8.4 ms, history ~19.1 ms, ranking ~1,032 ms. Subsequent page pinned the same version and avoided duplicates. Full responses saved under ignored `artifacts/opl-query-evidence.json`.
- Four executable integration suites pass: version replacement/add/correct/remove, held old readers/current readers and overlap/publication failure; refresh entry/idempotence/failure logging/recovery/due checks; ZIP download/CRC/truncation/UTF-8/additive-schema handling; pinned metadata across publication/status gaps, direct import, same-content new-source date and fast-path import timestamp. Malformed cursor shapes are tested. Fixtures are synthetic.

Source snapshot date is October 3 from the actual archive filename; landing date October 1 and successful check October 7 stay separate. `/dataset` currently flags source stale (>two days) while check stale is false. Six-hour checks plus the measured ~two-minute import give a tentative export-to-local-publication target; upstream nightly publishing delay and scheduler/hosting availability add uncertainty. A real repeating scheduler has not run, so no continuing freshness guarantee is established.
