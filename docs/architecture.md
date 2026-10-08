# Architecture decisions — Milestone 1

## Native layers

SwiftUI owns interaction and presentation. `LoadingModel` is a main-actor screen model; the finite inventory search runs off the main actor, cancels prior work and rejects old results. The domain package has no UI dependencies; the data repository adds Foundation URLSession and Apple CryptoKit. Shared numerical rules support warm-up and attempt plans without separate plate arithmetic.

Physical mass is an integer nanogram count. The international pound uses its exact 0.45359237 kg definition; nominal input accepts up to three decimal places. Unit conversion rounds only presentation. The canonical target and bar/collars survive a display-unit change; saving unchanged equipment fields also preserves their original mass. Display and inventory units are separate state. Reverse plate selections are retained separately for each inventory system. Counts mean pairs, and one-collar mass is always included twice.

Forward loading uses bounded knapsack over all achievable per-side sums. For an equal total it minimizes pair count, then prefers larger denominations. Closest selects minimum physical mass difference; equidistant loads choose the lower result. Explicit lower/upper results and unavailable-target messaging accompany the selected solution. No greedy assumption is made for custom inventories.

Bounds: 1–16 unique positive sizes, 0–40 available pairs per size, at most 40 pairs total, nominal inputs/plates up to 10,000 units. A 50,000 reachable-state cap reports an explicit complexity error instead of silently approximating. Stock inventories include small plates; they are editable starter configurations, not an assertion about a particular gym. Arithmetic is validated at construction and decoding. Overflow is an error.

## Build and dependency decision

Use one pure Swift package plus an XcodeGen manifest for the iOS shell. No Swift/Xcode toolchain exists here, and generating a large hand-edited `.pbxproj` adds avoidable uncertainty. XcodeGen is used only on a Mac; Apple frameworks are the only runtime dependencies in this slice. `SWIFT_VERSION` is 5.0 (language mode); Package.swift requires tools 5.9 or later. Native compile/test/UI validation is a remaining gate.

## Data boundary

Milestones3/4 implement runnable local `DataService` and source `OPLRepository`/SwiftUI Competition tab. See `data-service-runbook.md` for actual full-import evidence and `native-data-integration.md` for version-scoped client/cache behavior. Native execution, reachable host and continuing scheduler remain unvalidated gates. The following original stage plan is retained for context.

Next data stage introduces a compact read service backed by atomically published indexed OpenPowerlifting versions. A Swift `PowerliftingRepository` will expose native search, ranking, profile/history and published-version operations. Each response carries the same version ID; page cursors and caches are scoped to that version. Local cache supports previously fetched content offline. No browser handoff and no claim of a full offline database are implied.

The required recurring import replaces complete snapshots so corrections and removals propagate. See `research-gates.md` for cadence, schema, failures, and acceptance. This service is justified by millions of source rows and daily freshness. No backend is implemented in Milestone 1.

## Video boundary

A later `BarTrackingService` consumes locally imported/trimmed AVFoundation assets and produces timestamped observations, confidence, and explicit gaps. Vision can track an initialized observation; a separate automatic hub/plate candidate detector needs real evidence. The UI transforms normalized observations through orientation and aspect-fit geometry at playback time. Video stays on device. No model or external inference dependency has been selected.

## Current limits

Milestone 2 adds one shared equipment model across tabs, versioned validated local preference persistence and recovery, named rep-max estimates and loadable training/attempt plans. All calculators reuse sorted unique loads from the finite inventory engine. The diagram is a labeled per-side schematic, not a physical thickness model. No lifter data or fabricated tracking outputs appear in the app. No public repository, cloud service, Apple signing, or deployment has been created. Native execution remains pending.
