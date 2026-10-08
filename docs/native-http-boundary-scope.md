# Native client / actual service HTTP boundary scope

Scoped October 8, 2026 after run 37726403071. Recommendation only; no new integration test or CI step implemented.

## Existing evidence and gap

| Boundary | Actual existing coverage | Missing evidence |
|---|---|---|
| Native repository/query/cache/recovery | OPLRepositoryTests uses FixtureTransport; OPLRecoveryTests and app OPLPageStoreTests use supplied replies. These methods passed on Apple. | Requests to an actual Node service from Swift URLSession |
| Genuine response shape | testFrozenGenuineServiceContractExcerpt decodes frozen dataset/search/history/rankings JSON from a genuine prior snapshot. | Current server implementation serialized responses received over Swift networking |
| Node server/SQLite/query workers | service.test.mjs exercises real loopback HTTP dataset/search and invalid rankings; query-pool.test.mjs exercises HTTP busy/timeout/disconnect and real SQLite workers. | Swift transport MIME/status/error handling and model decoding against those responses |
| Profile | Current profile is exact selected search identity plus lifters/{id}/results history; no separate profile endpoint exists. | Search identity carried through native history requests to the actual service |

This gap is concrete. Repeating mocked responses or downloading the full upstream dataset would not test it.

## Recommended bounded implementation

1. Extract the existing labeled synthetic row/CSV helpers from DataService/test/service.test.mjs into a reusable test fixture module; retain existing eight-row fixtures and assertions. Extend only for this boundary scenario to fewer than 100 rows: enough distinct qualifying names and one exact-name history to force two pages at the repository's fixed limit of 25. Keep DQ/unofficial exclusion and missing/negative values observable. Clearly synthetic names, no genuine/current ranking claim.
2. A small Node launcher imports that CSV through the existing importSnapshot path and serves the existing server.mjs/QueryPool on 127.0.0.1 with an ephemeral port. It emits a ready descriptor containing URL/version/fixture counts after listening. Own one temporary root, bounded startup/lifetime, graceful shutdown and process cleanup. Use labeled synthetic source/check metadata to test distinct dates/stale flags; no upstream request or permanent scheduler.
3. One macOS-only, opt-in Swift package integration method uses OPLRepository and its real cache plus a test-only transport adapter. The repository receives an HTTPS fixture origin, retaining existing endpoint guards/query construction. Adapter requires that exact origin, rewrites only scheme/host/port to the ready loopback URL, preserves the encoded path/query, and calls the existing OPLURLSessionTransport.get. All response bytes come from the real server. No production changes, trust delegate, ATS exception or custom URLProtocol.
4. Assertions: online dataset validation and source/check date/version consistency; search two pages without duplicate identities; selected exact suffix/name resolves to paginated history with missing/failed values preserved; filtered best-performance rankings two pages with correct exclusions/order/version/label; real 409 VERSION_UNAVAILABLE maps to the native typed error for an unserved version. Existing mock suites retain exhaustive cache/recovery edge cases.
5. Add a separate bounded macOS HTTP-contract phase to the manual workflow. Provision/verify Node 24 and pinned pnpm, install from the existing pnpm lock with frozen-lockfile/ignore-scripts, start the fixture, run only the integration method, close service and preserve text logs. Missing opt-in environment skips ordinary package runs; CI must explicitly require the opt-in and verify execution. Keep the existing simulator test limit 10 minutes and whole-job limit 30 minutes. Suggested contract phase limit 3 minutes, dependency setup 3 minutes; sum of step limits remains subordinate to the job limit.

Provisional size: about 250–350 lines across reusable fixture module, fixture launcher, Swift test and CI script/workflow changes, plus moving existing fixture helpers unchanged. No new application API or data endpoint. Source/local fixture verification estimate 20–35 minutes after leader acceptance, uncertain mainly because hosted runtime provisioning and subprocess cleanup need review. Apple compilation/URLSession execution remains a subsequent authorized CI gate: prior whole job about 10m50; proposed additional phase expected under 1 minute after dependency setup, but first-run estimate 10–18 minutes with queue/install variability and unchanged 30-minute job ceiling. Re-estimate from actual diagnostics.

## Limits

MacOS URLSession-to-loopback validates the Swift repository/transport/model and actual service serialization boundary. The adapter means this does not validate public HTTPS/TLS, deployment routing, app ATS configuration, iOS network behavior, rendered browsing, large dataset capacity or actual recurring upstream freshness. Those require an approved host/device and operational evidence. Do not broaden this into service rebenchmarking or a new recovery mock suite.
