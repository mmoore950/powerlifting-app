# Local query isolation and cancellation

October 7, 2026. Implemented HTTP query execution with bounded child processes and tested on synthetic SQLite roots on Windows. No deployment, genuine pruning or native app validation occurred.

## Execution design

HTTP search/history/rankings use `QueryPool`. The parent validates query kind/keys/limit/cursor/signature, admits the request, selects an immutable snapshot and creates its lease with `withSnapshot`. The child receives only the prepared request and selected metadata. `executeQuery` runs the existing parameterized SQLite read logic and closes the database before returning. Children acquire no catalog locks or leases.

Default limits per server pool:

| Limit | Default |
|---|---:|
| Simultaneous child queries | 2 |
| Queued queries | 8 |
| Queue wait | 5 seconds |
| Admitted-job deadline, including selection/startup | 10 seconds |
| Result JSON acceptance | 8 MiB |
| Child V8 old-space setting | 64 MiB |
| SQLite page-cache target per child | 32 MiB |

The parent stays available for metadata and cancellation while SQLite works in children. A process is started for each query; startup overhead trades latency for simple termination/cleanup. The 64 MiB old-space setting and SQLite cache are not hard whole-process memory ceilings: native allocations, young-generation heap, IPC copies and SQL temporary files also consume resources. Result size checks occur before child send and after IPC reception, not as a streaming transport memory bound. Parent JSON parsing/encoding can briefly block its event loop. Production peak RSS/temp-disk/concurrency throughput remain unmeasured.

Direct library/CLI `query()` remains synchronous SQLite inside its invoking process, under a lease. It has no new process deadline; isolation applies to HTTP `serve()` / `QueryPool`. Loopback remains the default. The HTTP request/header timeouts are separate protocol guards, not SQL termination.

## Deadlines, disconnect and confirmed cleanup

Queue overflow and queue expiry return HTTP 503 with Retry-After. An admitted-job timeout aborts the job and requests `SIGKILL`; after confirmed child close and lease cleanup it returns `QUERY_TIMEOUT` / HTTP 504. Client disconnect cancels queued or active work. Server close cancels queued/active queries. Internal worker failure/wrong-version protocol responses fail rather than accepting mixed-version results.

After any successful result, timeout, cancellation or failure, the parent waits for the child `close` event before releasing its lease. This event follows process exit, or a spawn error with no created child. Lease registration must also finish before cleanup, so a late metadata write cannot recreate a released lease. A failed kill retains the lease/active slot until actual process shutdown; it cannot safely pretend cleanup completed.

The ten-second deadline is a parent timer followed by OS termination. It does not guarantee the entire HTTP operation returns within ten seconds or queue wait plus ten seconds: event-loop scheduling, filesystem lock/lease work, OS close and deletion of bookkeeping can overrun. Catalog acquisition's five-second wait is checked between filesystem calls. Synthetic SQL was actually interrupted with forceful child termination, rather than a cooperative check after a synchronous query finishes.

## Parent-crash ownership

Before SQL is permitted to begin, the parent registers the child reader PID atomically **inside the same catalog critical section as prune**, validating the lease's version/controller/start identity. This prevents prune from reading a parent-only lease, then probing that stale ownership after registration and parent death. It also keeps atomic temporary lease files out of a concurrent prune scan. Prune protects a lease when **either controller or reader PID is alive/unknown**, and removes it only when all recorded PIDs are confirmed dead. An idle child whose registration fails is terminated without being sent SQL work. Children never own catalog locks, so terminating a query child cannot leave a live-parent catalog lock behind.

A parent crash outside the short catalog critical section may leave a reader/lease. In this Windows parent-kill fixture, the child also exited (`Reader survived parent termination: false`); this does not establish portable descendant termination. A separate test uses a real open independent SQLite reader and a simulated dead-controller ledger, proving the reader PID alone prevents retirement. On a host where the child survives parent death, retention remains conservative but CPU/resource usage may continue. Deployment needs process-tree supervision and an operator cleanup policy; no portable orphan-process lifetime guarantee is claimed. PID reuse may conservatively retain a version. Parent death during its own catalog critical section still requires explicit dead-owner catalog recovery.

## Actual evidence

Fifteen combined service test suites pass, approximately **5.9 seconds** after the registration race correction. A deterministic held-catalog test confirms registration waits and the actual child receives no SQL before registration commits. Six new query suites cover:

1. Parent process termination, atomic child-PID registration and dead-lease cleanup; Windows observed child termination is recorded explicitly.
2. A real read-only SQLite billion-step recursive statement interrupted at a shortened 400 ms deadline; metadata remains responsive, child is confirmed dead, leases/catalog lock absent, then a subsequent query and synthetic prune succeed.
3. A real surviving database reader under a synthetic dead-controller/reader-PID ledger, retained while open and eligible after release.
4. Queue capacity/expiry, queued cancellation and active cancellation, followed by a successful query.
5. HTTP 503 busy, 504 timeout, client socket disconnect and server shutdown, including child termination and subsequent query/lease cleanup.
6. Actual child results matching direct search/cursor/history/rankings plus worker crash, wrong-version response, invalid limits and closed-pool rejection.

The first disconnect test treated expected socket reset as a rejected event wait; its setup was fixed. The added independent-reader fixture initially omitted its lease directory, also fixed in setup. No observed failure was omitted from this record. Timing tolerances are synthetic test bounds, not production latency promises. All destructive tests use isolated temporary roots.

Primary API reference: [Node 24 child_process documentation](https://nodejs.org/docs/latest-v24.x/api/child_process.html), checked October 7 for fork/close/error/kill semantics. Fork uses no shell and hides Windows child windows. No extra runtime dependency was added.

## Existing genuine-snapshot measurement — 3:06 PM ET

Ran `tools/benchmark-query-pool.mjs` once against the existing 4,043,255-row / 1,015,391-lifter snapshot `bac56dbcedd8cd351765f1d9af6c99e43887819955191a37b242db31850b1ed7`, source date October 3. At most five requests/two children, ten-second admitted deadlines and sixty-second tool cancellation timer. **Zero upstream requests, imports or prunes.** Evidence: ignored `artifacts/query-isolation-benchmark.json`. Leases/last-use bookkeeping were written by normal reads; no snapshot data was changed.

| Case | Full local worker latency | SQLite duration | Rows |
|---|---:|---:|---:|
| Taylor Atwood prefix search | 71.8 ms | 1.4 ms | 1 |
| History concurrent with rankings | 78.3 ms | 11.6 ms | 25 |
| F/Raw/SBD/tested/IPF/2020+ best totals | 7,317.2 ms | 7,227.0 ms | 25 |
| Version-bound ranking continuation | 1,056.7 ms | 990.0 ms | 25 |
| Repeated prefix search | 61.3 ms | 0.7 ms | 1 |

All results and metadata retained the same version. Metadata took **62.9 ms** with two jobs admitted at both start and completion. Whole measured mix finished in **8.51 seconds**; pool closed with zero active/queued jobs. Largest returned page was 22,574 bytes.

Child process-reported RSS peaks, sampled after result JSON creation and before final IPC send, were approximately **41.1, 42.3, 79.1, 79.2 and 41.8 MiB**. Parent process-reported peak was **45.9 MiB**. These are per-process readings, not simultaneous fleet/OS-cache memory, final exit-time maxima or guarantees. SQL temporary-disk peaks were not measured.

The first ranking's 7.32-second latency is materially larger than its 1.06-second continuation and the earlier direct-query measurement. Cache state or host I/O may explain part of the difference, but causation was not isolated. The ten-second default leaves limited margin for slower hosts/concurrent wide rankings. This small run establishes executable full-data compatibility, not production capacity; profiling/index changes or deadline policy need separate review.
