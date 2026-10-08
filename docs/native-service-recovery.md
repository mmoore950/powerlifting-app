# Native service expiration, busy and timeout recovery

October 7, 2026. Source checkpoint; **no Swift/Xcode, URLSession runtime, XCTest or native UI execution occurred**.

## Typed service errors

OPLURLSessionTransport classifies HTTP 409 `VERSION_UNAVAILABLE` as definitive expiration, 503 query/queue/catalog busy as busy with a bounded optional Retry-After seconds hint, and 504 `QUERY_TIMEOUT` as a query timeout. Other 409 errors, including cursor mismatch, remain errors instead of automatically changing filters/identity. HTTP 503 `NO_DATASET` has its existing no-data state. Busy/timeout messages explain retry or narrower filters; no timer repeatedly retries them.

Ordinary network/busy/timeout failures may return validated saved data for the exact endpoint/query/version/cursor, with the typed failure described in the offline notice. A definitive expiration response bypasses cache substitution for that attempt. Cached pages remain device data and can still support a separately labeled offline request when no live expiration response is available; they never become current-version pages by relabeling.

## One recovery transaction

`OPLRepository.recoveringPage`:

1. Requests the caller's explicit version/cursor.
2. On definitive expiration, notifies the screen to discard old rows, cursor, saved time and offline state.
3. If the caller still permits one recovery, fetches/validates `/dataset` **online**. Saved expired metadata cannot redirect recovery back to an unavailable snapshot when the live check fails.
4. Notifies the screen of the validated version, then requests the same logical query's first page with that version and **no old cursor**.
5. Returns the restarted page, or surfaces the second failure. It does not recurse on another expiration.

Cancellation is checked around notifications and network/cache work. Every returned page still validates its requested version before saving. Busy/timeout use exact-key saved pages or surface a clear error; they do not trigger dataset recovery.

## Screen reset and lifecycle

`OPLPageStore` holds an automatic recovery budget for the same client/logical query across metadata-triggered task resets. A new query/client resets the budget. Explicit **Try again** grants one new transaction. Recovery immediately clears old rows and retains the new version even when its first-page fetch fails. Pagination appends only after the returned version is accepted; restarted results replace the prior array. A failed continuation retains its cursor for manual retry unless expiration invalidated it.

The recovered metadata is adopted by OPLBrowserModel only for the same repository, superseding an older in-flight metadata refresh. Other pages reset via the shared revision. The originating store skips that adoption's matching reset once, preserving its already restarted page or error; this prevents another automatic transaction or duplicate busy request. Generation/cancellation checks reject older query/recovery results and clear obsolete progress notices.

Search debounce now runs inside reset after old rows are cleared, preserving this recovery budget through the adoption reset. A canceled debounce leaves no request and clears loading. No self-scheduled busy retry or unbounded expiration loop is introduced.

## Test sources and build target

Six new package XCTest sources cover definitive expiration versus cache, old cursor removal, fresh version transition, repeat-expiration/caller budget, forbidden metadata fallback, saved busy/timeout data and HTTP-code/Retry-After classification. These simulate typed transport responses; they are not executed URLSession integration.

Four new iOS application unit-test sources cover adoption/reset retaining new rows and budget, busy after metadata recovery with explicit first-page retry, delayed old results versus a new query/version, and canceled debounce with no request. XcodeGen now declares `PowerliftingAppTests`, depending on the app/core package, and the app scheme names it beside package tests. Pinned XcodeGen 2.46.0 ProjectSpec was checked for app-host unit-test/dependency and scheme syntax. **Project generation, compilation and all ten tests remain unrun.**

Actual Windows verification was whitespace/source review only. Future hosted simulator tests must verify actor isolation, task cancellation/adoption ordering, resource/test-host resolution, endpoint switching, offline behavior, genuine service 409/503/504 responses and UI messages. Source completion is not a native recovery acceptance claim.
