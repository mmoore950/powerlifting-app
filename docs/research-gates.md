# Data and video research gates

Checked 2026-10-07. These are implementation decisions and acceptance plans, not completed features.

Later measured checkpoint: full streaming import/index/CRC and genuine queries ran; see `data-service-runbook.md`. Four integration suites verify transitions/failures and pinned metadata. Native client/cache/screens source is described in `native-data-integration.md`; it has not run. Initial-inspection limitations below remain a historical record. Production scheduled freshness and automatic localization remain open.

## OpenPowerlifting route and actual archive inspection

Primary sources: [bulk downloads](https://openpowerlifting.gitlab.io/opl-csv/bulk-csv.html), [schema documentation](https://openpowerlifting.gitlab.io/opl-csv/bulk-csv-docs.html), [data licensing](https://openpowerlifting.gitlab.io/opl-csv/).

Official complete ZIP: https://openpowerlifting.gitlab.io/opl-csv/files/openpowerlifting-latest.zip . The service says it publishes nightly. Its landing page currently reports source date 2026-10-01, revision `199bb416`, 4,043,256 rows and 163M ZIP size. These are landing observations, not an independently counted row total.

`tools/inspect-opl.ps1 -Download` successfully fetched and inspected the actual archive at 2026-10-07T16:06:46Z. It did not extract or index the full CSV:

- Archive: 170,132,164 bytes. CSV entry: `openpowerlifting-2026-10-03/openpowerlifting-2026-10-03-199bb416.csv`.
- Uncompressed CSV length from ZIP metadata: 826,444,366 bytes.
- HTTP Last-Modified: 2026-10-03 02:05:35 UTC.
- SHA-256: `f97c5dce230843d871e42be76359efbe01694838285c3b82530f13e71a5cbba8`.
- Header: 42 columns, including `MeetTown`, which is absent from the inspected rendered field list.
- Full inspection JSON and archive are retained under ignored `artifacts/`. No row count, ZIP CRC verification, full-row validation, query speed or production freshness was measured.

Actual CSV header:

```text
Name,Sex,Event,Equipment,Age,AgeClass,BirthYearClass,Division,BodyweightKg,WeightClassKg,Squat1Kg,Squat2Kg,Squat3Kg,Squat4Kg,Best3SquatKg,Bench1Kg,Bench2Kg,Bench3Kg,Bench4Kg,Best3BenchKg,Deadlift1Kg,Deadlift2Kg,Deadlift3Kg,Deadlift4Kg,Best3DeadliftKg,TotalKg,Place,Dots,Wilks,Glossbrenner,Goodlift,Tested,Country,State,Federation,ParentFederation,Date,MeetCountry,MeetState,MeetTown,MeetName,Sanctioned
```

Record the landing date, archive date, HTTP timestamp and source revision independently. They disagree here; do not substitute a recent check time for the source's actual age. The ingestion parser must allow documented additive fields, reject missing required fields, and preserve upstream fields/semantics. Failed attempts are signed; missing values remain missing; suffixed names distinguish lifters; weight-class strings can use `+`; equipment and tested values denote categories. Unsanctioned results require explicit ranking treatment. Best performances are not automatically federation-ratified records. Data is public domain; keep visible OpenPowerlifting attribution.

## Recurring ingestion and compact native API

Proposed stage-3 design, pending measured ingestion and scheduler integration:

1. One small service checks official metadata every six hours in UTC. This exceeds the human's at-least-daily requirement without assuming the export hour. Persist each check time separately from the most recent successful publication.
2. Compare revision and archive metadata; use conditional HTTP where supported. Revision sameness is not sufficient proof of identical bytes because artifact dates may change. Fetch changed candidates into staging, enforce configurable compressed/decompressed limits, stream parse, count rows, check required fields, categories, dates and numerical validity, and calculate a content hash.
3. Build a new indexed SQLite snapshot off the serving path. Index normalized name search, lifter identity, meet history and specified ranking filters. Benchmark actual storage/query cost before selecting hosting resources. Use complete replacement snapshots, not an invented delta feed or append-only updates.
4. Use content hash as immutable dataset version and publish a manifest plus snapshot atomically. Queries pin a version, including pagination; search/profile/rankings use the same published version. Retain the previous valid version until readers finish and rollback remains possible.
5. Expose `/dataset`, `/lifters`, `/lifters/{id}/results`, and `/rankings` as a designed service API, **not an OpenPowerlifting API claim**. Responses/cursors include version; a retired version returns a specific retry response rather than combining pages. IDs include the source's name discriminator; renames and duplicated division entries need a documented identity/deduplication rule before implementation acceptance.
6. iOS checks `/dataset` on launch/foreground, at most once per configured freshness interval, plus explicit manual refresh. Queries use versioned cache keys. Switch versions transactionally and clear incompatible pagination/results; retain older cached content offline with its version/source date visible. Refresh currently visible content after a successful version change. Device background execution is optional.
7. Retry failures after 15 minutes, one hour, and six hours; enforce one ingest at a time, idempotent content-addressed publication and restart recovery. Keep last known good data. Mark service degraded after 24 hours without a successful metadata check; separately expose source age so upstream stagnation is detectable even when checks succeed.

Freshness target is a candidate publication within six hours **plus measured ingestion time** after an upstream export becomes available. Nightly export delay adds separately to website-to-app lag and has no guaranteed bound here. Check cadence is a configured operational target, not an upstream SLA or real-time parity. Ingestion duration cannot be estimated credibly until full parse/index benchmarking; estimate again after that first measured run. No production scheduler/service has been installed.

Data acceptance must exercise at least two versions with added meet, corrected result and removed result; prove refreshed search/profile/rankings, version-consistent pagination, cache invalidation, offline stale display, idempotency, interrupted ingest and corrupt/failed update recovery. Synthetic fixtures prove mechanics. Production readiness additionally requires an actual scheduler run against upstream, observed check/publish times and freshness monitoring.

## Automatic bar path feasibility

Apple [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest) follows a previously identified observation. It does not automatically recognize a bar. Separate two prototypes: user-assisted initial selection and automatic near-side hub/plate localization. Review the concrete open-source candidates in `open-source-research.md`; do not introduce obsolete runtime dependencies or unlicensed models.

Early on-device path: import via PhotosPicker/file selection, copy accessible assets locally, inspect AVFoundation tracks/transform and timestamps, trim a rep, decode samples, initialize a Vision sequence tracker, and produce timestamped centers/confidence/gaps. Playback uses the asset's orientation and aspect-fit transform; never infer timestamps only from nominal FPS. Handle variable frame rate, occlusion and tracker loss explicitly. Pause/offer correction after loss instead of extending a fabricated trace. Camera motion must be measured or warned about because screen coordinates mix bar and camera movement. No velocity/distance without time and scale calibration.

Automatic candidate options: plate segmentation followed by ellipse/hub localization, or a licensed compact trained detector with native/Core ML execution. Generic circle detection is only a baseline: oblique plates are ellipses and racks/backgrounds create competing shapes. Choose the near side explicitly and evaluate reacquisition/target switching. Existing marker or manually initialized projects do not satisfy the ordinary-video requirement.

### Proposed evaluation, for leader review

- Obtain 18 consented local side-angle clips: six each squat/bench/deadlift, including different plate colors, oblique angles, lighting, occlusion, moving cameras and multiple circular distractors. Keep evaluation assets private/local.
- Manually annotate near-side hub points and visibility; report automatic initialization success, wrong-object rate, position error normalized by visible plate diameter, drift, confidence gaps and recovery. Keep a separate failure set; no pooling that hides failure modes.
- Candidate prototype target: correct automatic initialization in at least 90% of eligible visible-start clips; median position error below 5% of plate diameter and 95th percentile below 10% during visible frames; any high-confidence wrong-object continuation is a gate failure. These are proposed criteria, not measured results or a promised accuracy.
- Measure end-to-end processing duration versus clip length, peak memory, thermal behavior and cancel responsiveness on at least one real iPhone. Establish the supported device/clip limits from those measurements.
- Independently verify portrait/landscape/mirrored geometry, rotation metadata, variable timestamps and overlay synchronization. Synthetic clips can check transforms, not ordinary-video detection accuracy.

No reliable automatic-detection readiness estimate exists until representative clips and iPhone execution are available. The first estimate becomes possible after baseline runs on annotated clips. User-assisted tracking remains a useful fallback but does not close this gate.
