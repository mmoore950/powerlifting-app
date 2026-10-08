# Finite local refresh demonstrations

October 7, 2026. Neither demonstration installs an OS task, service or public host.

## Accelerated synthetic timeline — executed

Run `node DataService/tools/demo-refresh.mjs` from the project root. It creates an isolated ignored synthetic service root, injects a scheduling clock and synthetic metadata/source responses, then executes real CSV parsing, SQLite indexing, atomic storage and queries. Network/download/import elapsed-time guards retain the real clock. Production CLI does not expose a fake clock option; normal scheduling uses Date.now.

Assertions passed for bootstrap, pre-due skip without requests, six-hour due full replacement with added/corrected/removed names/results, failed upstream request retaining B, exact15-minute retry deadline, pre-retry skip, recovery with same content/new source date/same version and reset failure state. Search/history/rankings corroborate corrections/removals. Timeline/status/log evidence is under `artifacts/refresh-demo/`; latest summary is `latest-synthetic.json`. Synthetic mock requests are counted; real upstream requests are zero. Scheduling timestamps and lifter facts are synthetic, not real observations or production freshness.

## Finite real due-only wrapper loop — executed

```powershell
.\DataService\scripts\demo-recurring-refresh.ps1 -Ticks 3 -IntervalSeconds 5
```

Actual run: three child commands, all successful, 10.36seconds total. Each called the existing bounded due-only refresh wrapper against the genuine published local service root. All correctly skipped because the actual next due time is October7 at6:49:39PM ET. Thus this run exercised repeated scheduling entry/status/logging but made **zero new official upstream checks**. Prior genuine import/revalidation evidence stays distinct in `data-service-runbook.md`.

Evidence: `artifacts/refresh-demo/official-due-loop-20261007-174259-398.json`, with three corresponding stdout/stderr paths. Process finished; no background service remains. On a due tick the normal refresh command may check official upstream and import a changed snapshot; it is never forced by this demonstration.

The loop is finite by tick count (1–12), pauses1–30seconds between ticks, stops on failure with persisted report, and passes a hard child timeout1–1200seconds (default20minutes). For the default three ticks, bounded child work is at most60minutes plus10seconds polling and process/log cleanup; the observed10.36seconds is not an import completion guarantee. This does not provide a perpetual daily checker. An actual repeating deployment with monitoring and observed due upstream runs is still required for production ongoing freshness.

Next official due state is stored, but no automatic execution is installed. After authorized recurring deployment/due execution, compare actual upstream revision/accepted version/source date/check time and failures before claiming ongoing freshness. Current native CI hardlimit30minutes is an independent build gate.
