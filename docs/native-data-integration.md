# Native OpenPowerlifting integration — source checkpoint

Updated October7,2026. No Swift/Xcode execution has occurred; this is reviewable source.

Subsequent typed expiration/busy/timeout handling and bounded first-page recovery are documented in [native-service-recovery.md](native-service-recovery.md), including new package/application test sources and their unrun build gate.

## Implemented source

The Competition tab uses native SwiftUI search, exact-name history and filtered best-performance rankings. Filters expose service-supported sex category, equipment, event, tested designation, federation, date range, literal class, recorded bodyweight range and metric. Prefix search retains exact suffix identities. Division rows, missing values and failed numerical facts remain explicit. Rankings are dataset performances, not ratified records.

`OPLRepository` is an actor with injectable `OPLTransport`/`OPLCache`. Default transport uses Apple's async URLSession API; no external mobile networking library. DTOs decode actual field names and nullable amounts. Every page requests an explicit content version; cursors retain version/filters. Wrong-version responses are rejected before caching. Supplied dataset validation metadata must match its content version; source date comes from pinned `/dataset`, independently of global refresh status.

Cache keys include full endpoint/route/filters/version/cursor. SHA-256 filenames and checked key envelopes isolate queries/services. Foundation atomic writes and a 25MiB/200-file bound preserve recent saved pages; oldest entries are evicted and iOS may purge caches. This is previously fetched content, not the full offline database. Old-version cache files remain until eviction, but the current UI never substitutes an old page under a newer dataset label. A new version with no saved pages cannot invent offline results.

Foreground and pull/manual refresh reload metadata and visible queries. Version changes clear old rows; generation/cancellation guards reject late results. Failed requests fall back only to validated same-key saved data with visible error/time. Storage failure after online success exposes an offline-saving notice. Service last check, source date, device save time, stale state and live-refresh-unavailable state remain separate. Cached staleness is recalculated from dates.

## Connection and privacy gate

Configurable HTTPS service URL is persisted locally; embedded credentials/query/fragment are rejected. No ATS exception or network secret is added. The current service binds Windows loopback HTTP. An iPhone cannot use that host's localhost, and this client does not create reachable HTTPS hosting. Authorized TLS/reachable hosting or a reviewed development connection remains a gate. Empty configuration shows setup, with no fixture rows in product. Native requests have no browser handoff.

No videos are uploaded. Selected search/filter requests go to the configured service; no accounts/analytics added. Default request timeout20seconds and response acceptance limit4MiB. URLSession `data(for:)` buffers before checking size; this is not a streaming memory guarantee. Production resource cancellation/streaming remains an improvement.

## Verification and next gates

Native test sources cover version-isolated offline pages, wrong-version rejection before saving, cursor/plus encoding, source/check dates, corrupt cache, endpoint isolation, write-failure notices, real disk persistence/eviction and nullable failed facts. A frozen genuine public October3 snapshot excerpt from the HTTP probe is a dated contract fixture, not current rankings. Synthetic responses are labeled separately. These XCTest sources have not run.

ACTUAL Windows checks: four service integration suites pass, including publication/status metadata gaps, same-content new-source dates, fast-path import-time pairing and malformed cursors. Hosted workflow/actionlint/shell/simulator-selector checks passed. Frozen fixture JSON and whitespace checks passed. None is a native compile/test/UI claim.

Next gates: prepared hosted workflow after authorized repository/runner access, diagnostics repair, reachable API, offline relaunch, foreground/manual refresh, in-flight version change, expiration/busy/timeout and pagination on Simulator/device. Local executable retention/query isolation are implemented and documented separately; production capacity, continuing scheduled upstream checks, hosting and automatic local-video accuracy remain open. Native readiness ETA is unknown until first Apple diagnostics; job timeout30minutes is separate.

Primary APIs reviewed: [URLSession async data](https://developer.apple.com/documentation/foundation/urlsession/data(for:delegate:)) (Markdown fetched with PowerShell), [CryptoKit SHA256](https://developer.apple.com/documentation/cryptokit/sha256). Actors and async protocols follow Swift concurrency; their actual compiler/runtime acceptance remains the hosted gate.
