# Local snapshot retention

October 7, 2026. Implemented and exercised on isolated synthetic temporary roots. **No genuine artifacts were pruned and no automatic retention job was installed.**

## Policy

`pruneSnapshots` defaults to dry run. It retains the current version, explicit previous publication for rollback, at least the three newest imported versions, every version with an active reader lease, and versions imported/published/read within seven days. The configurable count is at least two and age is at least one day. Legacy current pointers without `previousVersion` also protect another available snapshot. Missing current/rollback data or malformed lifecycle metadata aborts pruning.

The age window is measured from the latest recorded import/publication/read. A continuation's first page touches its version; subsequent reads renew the window. Cursors do not reserve snapshots forever. A cursor for a retired version receives stable `VERSION_UNAVAILABLE` / HTTP 409, allowing a client to refresh the dataset and begin a new query. Cached native pages remain separate version-scoped device data.

This is a retention policy, not a fixed disk cap. Frequent new versions, active readers or recent use can retain more than three snapshots. With the measured 1.25 GiB genuine database, seven daily versions alone would use about 8.8 GiB, plus source archives/staging/other retained versions. Deployment needs an explicit storage budget and monitoring. Usage metadata is retained as small bookkeeping; interrupted import/download staging cleanup remains separate.

## Publication and reader lifetime

- Import/prune share the existing exclusive `refresh.lock`. Prune refuses to overlap publication or another refresh. Installation/publication continues to validate immutable snapshots and atomically rename the current pointer.
- Publication, reader selection/lease creation and retirement share `lifecycle/catalog.lock`. Readers choose the pointer/version and create a lease in this critical section before opening SQLite. Publication records `previousVersion` and touches publication time in the same critical section.
- Search/history/rankings and `/dataset` use `withSnapshot`. Its lease covers metadata/SQL/all asynchronous work and is released after the database closes, including thrown errors. HTTP queries now run in bounded child processes; see `query-isolation.md`. Direct CLI/library queries remain synchronous.
- Prune treats live or inaccessible/unknown controller or registered reader PIDs as active. Only confirmed `ESRCH` death of all recorded owners allows stale lease removal. Query children are registered atomically before SQL starts; the parent releases after confirmed child close. PID reuse can retain an unused version conservatively. Leases never expire merely because a slow healthy reader exceeds a timer.
- Local process IDs assume one host and a trusted local filesystem. Multi-host/network filesystem deployments need a different lease/lock authority. Direct database readers bypassing `withSnapshot` are outside this protection; operators must register such reads or stop pruning while they run.

The catalog lock has a five-second acquisition wait checked between attempts; filesystem calls can overrun it. A killed owner leaves the lock and fails subsequent work closed (`SNAPSHOT_BUSY`, HTTP 503). Explicit recovery requires the exact recorded dead PID and matching nonce; live, inaccessible or changed owners are rejected. Recovery commands must be serialized by the operator. No speculative automatic lock removal occurs.

## Deletion safety

Eligibility is fully inspected before directory retirement. A reader and prune cannot race between version selection and lease creation. Under the catalog lock, an eligible snapshot directory is renamed on the same filesystem into `retired-snapshots/<version>-<UUID>`. New readers then see the version as unavailable; completed retirement has no serving database path to partially remove.

Deletion follows outside the catalog lock while retaining the refresh lock. Only an explicitly retired directory with a matching persisted receipt is removed. Receipts live outside the directory so partial deletion can be retried. A rename failure leaves the serving snapshot intact; a deletion failure leaves the retired data/receipt for a later explicit retry. Unknown entries/unverified retired directories are reported and preserved. Interrupted receipts without a directory can remain as small bookkeeping.

Managed snapshot/retirement/lifecycle/lease directories reject symlinks and Windows junctions. Version/directory names and resolved child paths are bounded to the explicit root. Snapshot symlink directories fail closed. Root must be explicitly supplied to the CLI; a filesystem root is rejected. This is not a defense against another process maliciously replacing trusted directories during a filesystem operation.

## Reviewable commands

Commands below are examples; **none was executed against the genuine root**. Review the dry-run report/storage plan before applying to real data.

```powershell
node DataService/src/cli.mjs prune --root C:\PATH\TO\SERVICE
# Explicit application, with policy overrides if reviewed:
node DataService/src/cli.mjs prune --root C:\PATH\TO\SERVICE --apply true --keep 3 --days 7
# Only after proving the recorded catalog owner is dead; one operator at a time:
node DataService/src/cli.mjs recover-catalog-lock --root C:\PATH\TO\SERVICE --pid RECORDED_DEAD_PID
```

Refresh crash recovery remains the existing separate `recover-lock` command. A refresh killed during publication can leave both lock files; inspect both owners and recover only the matching dead owner.

## Actual executable evidence

`node --test DataService/test/retention.test.mjs DataService/test/service.test.mjs`: eight suites pass on Windows, approximately 0.8 seconds at this checkpoint. Four new retention suites exercise:

1. Real forked process with an open SQLite reader/lease across prune; no active-version deletion; release and expiry; old cursor's HTTP 409 and current queries.
2. Dry-run preservation, access grace, count policy and explicit oldest-version rollback protection.
3. Publication/prune exclusion, thrown-reader cleanup, killed-process stale lease cleanup, and explicit catalog recovery refusing a live/mismatched PID.
4. Malformed leases, missing rollback, policy bounds, unknown/unverified directories and a genuine Windows junction to a synthetic outside sentinel preserved intact.

The first run exposed a missing fixture lease directory, which was fixed in test setup. No genuine full import/query/deletion, deployment or production stress claim follows from these small synthetic tests. Query workers and timeout cleanup are the next bounded local task.
