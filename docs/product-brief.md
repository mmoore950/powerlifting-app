# Product brief

Created 2026-10-07 from the human user's request. Working name: Powerlifting App; final branding can wait.

## Product

An iPhone app for powerlifters with fast plate math, training and meet calculators, native browsing of OpenPowerlifting data, and bar path overlays on imported side-angle training videos. Use Bar Is Loaded as a functional reference while building an original interface and implementation.

Human direction on 2026-10-07: actively draw from existing open-source implementations, libraries, research, and relevant public resources for every major feature. Inspect applicable source before building a replacement; reuse or adapt sound compatible components when useful. Record sources, versions/licenses, limitations, and the reuse decision. Public availability alone is not evidence that mobile implementation or model weights have a usable license. Initial findings are in `docs/open-source-research.md`.

## Required features and acceptance

### Plate loading and reverse loading

- Enter a desired total in pounds or kilograms, independently select pound or kilo plate inventory, and see a clearly labeled plate diagram and list per side.
- Include configurable bar weight, collars (explicit per-collar versus total), available pairs, and small plates. Preserve a selected physical load when changing display units.
- Reverse mode adds/removes plates and instantly reports the full total including both sides, bar, and collars, with both unit displays.
- Handle unavailable targets, below-bar targets, decimal plates, invalid inputs, and limited inventory. Explain the nearest achievable load and its difference; never silently imply an impossible load is exact.
- Verify reference cases such as a 45 lb bar plus two 45 lb plates per side = 225 lb; a 20 kg bar plus 25+20+10+5 kg per side = 140 kg; 2.5 kg competition collars add 5 kg total. Unit changes must not introduce or remove collars.

### Calculators

- Estimated one-rep max from weight and reps, with named formulas (start Epley and Brzycki), valid ranges, single-rep handling, and honest estimate wording.
- Warm-up plan from today's top-set target, configurable lift/reps and progression, with practical rounded/loadable weights and plate diagrams; allow editing. Presets are starting points, not claims of universally ideal programming.
- Meet attempt planning works backward from a desired third attempt and suggests editable ranges for opener and second, with documented percentages/assumptions and configurable legal increments. Distinguish aspirational third target from demonstrated strength. Avoid presenting a goal as evidence the attempt is achievable.

### OpenPowerlifting inside the app

- Native search for lifters, profiles and meet histories, rankings, and best performances/records filtered by sex/category, bodyweight or class semantics, equipment, tested category, federation, event, and date as supported by the data.
- Assumption: "doesn't open the internet" means no browser handoff or embedded website for the experience. In-app background network requests are allowed; cached data should remain usable offline. A completely offline full database is a separate storage/refresh tradeoff to assess.
- Prefer published bulk data and a documented ingestion/indexing layer over scraping pages or inventing an official API. Record source URL, snapshot date, schema, and data coverage; refresh should be atomic and preserve usable cached data on failure.
- Human clarification on 2026-10-07: OpenPowerlifting changes daily across many federations. Keeping up with ongoing additions and corrections is mandatory; a one-time download is only bootstrap data and cannot satisfy this feature.
- Implement a recurring ingestion service that checks for new official source revisions at least daily, validates and indexes each new snapshot, and atomically publishes a versioned dataset/read API. Choose and document the check cadence, upstream publishing delay, measured ingestion time, retry policy, and attainable freshness target. Do not claim real-time parity with website edits when using nightly exports.
- Process corrections and removals as well as new meets/lifters. Refresh profiles, meet histories, rankings, and best-performance results consistently against the same published version. Do not assume an append-only feed or a supported upstream delta API.
- The app checks the published version on launch/foreground and supports user refresh, invalidating stale query caches as versions change. It should fetch current search/ranking/profile results within native screens without making each phone download the full raw CSV every day. Background device refresh is an optimization, not the only freshness mechanism.
- Show the source dataset date separately from the last successful synchronization/check; expose offline/stale status when relevant. Retain the last validated version if ingestion or networking fails, retry automatically, and make a stalled update pipeline detectable.
- Acceptance requires a demonstrated transition between two source versions, including an added meet, corrected result, and removed result; refreshed search/profile/rankings, consistent versioning, idempotent retries, and recovery from a failed update. Synthetic fixtures can verify mechanics; a production-readiness claim also requires an actual scheduled refresh against the upstream source.
- Distinguish best performances in the database from federation-ratified records. Use the data's actual tested/equipment/category semantics and handle missing values and repeated lifter names carefully.
- First slice may use a clearly labeled genuine small data snapshot or fixtures, but the complete requirement remains real searchable data and rankings. Do not market sample rows as a complete current database.

### Bar path video analysis

- Import a training video, select/trim a rep, identify the near-side bar end/plate hub, and draw its path in sync with playback.
- Automatic identification is a required research target. A user-assisted initial tap/box is an acceptable first prototype/fallback, but does not satisfy automatic detection by itself.
- Prefer on-device AVFoundation and Vision. Evaluate automatic candidate detection/reacquisition separately from tracking an already identified object. Apple's generic tracker is not a trained bar detector.
- Preserve video orientation, aspect ratio, timestamps, and coordinate transforms. Handle lost confidence, occlusion, multiple plate-like objects, camera shake, and drift explicitly; allow correction and do not draw confident fabricated continuation.
- Plan evaluation with real representative side-angle squat/bench/deadlift clips, manually checked reference points, confidence failures, and processing-time/memory measurements. Synthetic traces validate math, not real video accuracy.
- No velocity or distance claims without valid time/scale calibration. No medical or technique diagnoses. Export is a useful later addition after reliable playback overlay.

## Architecture and stages

Default: SwiftUI native iOS app, minimum iOS 17 unless APIs provide a reason to change; a pure Foundation domain module for plate/calculator logic; AVFoundation/Vision behind a tracking service; a data repository abstraction backed by an indexed snapshot/cache. Avoid adding accounts, ads, subscriptions, or a large backend before required behavior exists.

1. Foundation: architecture/build feasibility, source scaffold, calculator domain + meaningful tests, plate/reverse UI, and an honest toolchain report.
2. Training/meet calculators with consistent plate rendering and saved equipment preferences.
3. Recurring data ingestion and publication, search/rankings/profile screens, attribution/freshness, cache invalidation, update failure recovery, and measured storage/query strategy. A static snapshot does not complete this stage.
4. Imported-video tracking prototype and automatic-detection feasibility; establish real-device accuracy and performance gate early.
5. End-to-end iPhone validation, accessibility, error states, privacy/storage behavior, and TestFlight preparation.

Research on data scale and video feasibility should happen early enough to expose architectural blockers before extensive polish. Preserve progress on independent modules if native validation is blocked.

Local development is on Windows. As of October 8, GitHub macOS CI has built the unsigned app and passed 53 simulator tests, 42 ordinary macOS core tests and a separate actual Swift-to-Node HTTP contract test. Physical-device access, real-video accuracy, production hosting/recurring freshness, signing and release validation remain open gates. See docs/status.md for current evidence and limits.

## Research sources checked 2026-10-07

- Bar Is Loaded App Store listing: https://apps.apple.com/us/app/bar-is-loaded-gym-calculator/id1509374210 . Confirms forward/reverse plate math, equipment configuration, rep-max and attempt tools; release history confirms warm-ups and OpenPowerlifting profile integration. Reference research is the public listing, not a hands-on app session.
- OpenPowerlifting FAQ: https://www.openpowerlifting.org/faq . Says data is public domain, website code AGPLv3+, and the dataset covers competition results. Use data independently; avoid copying their website code into a proprietary app without assessing its license.
- OpenPowerlifting bulk data: https://openpowerlifting.gitlab.io/opl-csv/bulk-csv.html . Official service publishes nightly CSV ZIP snapshots. At initial inspection the rendered page reports a 2026-10-01 snapshot, 4,043,256 complete-dataset rows and a 163 MB ZIP; these are page observations, not a verified downloaded manifest or freshness guarantee. Worker must inspect the current schema/download metadata. This scale favors a prebuilt indexed snapshot and measured subset/cache strategy over decoding all CSV on the main thread.
- Apple tracking docs: https://developer.apple.com/documentation/vision/vntrackobjectrequest and https://developer.apple.com/documentation/vision/tracking-multiple-objects-or-rectangles-in-video . Track previously identified observations; automatic bar localization needs separate evidence.
