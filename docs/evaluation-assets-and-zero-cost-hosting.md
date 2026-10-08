# Evaluation footage and strictly zero-cost hosting

Research checked October 8, 2026, America/New_York. This extends [open-source-research.md](open-source-research.md). Research only: no media was downloaded, annotated, scored or added to CI; no account, deployment, payment, firewall or access changes were made. Browser preview inspection is distinct from an observed evaluation annotation. The evaluation manifest still contains zero clips and tracking accuracy remains unmeasured.

## Findings for leader review

- Public video asset licenses exist. One small MyDeadlift MP4 has an explicit file-level CC BY 4.0 license; the dataset documents fixed side-view recording. Three tiny Commons clips have explicit CC BY 3.0 asset licenses, but their common source and oblique camera view limit their evaluation value.
- The public candidates do not yet supply a diverse, independently held-out squat/bench/deadlift set. Rights discovery advances acquisition; it does not close automatic localization, hub tracking or device performance gates.
- None of the three cloud options examined meets all existing service requirements and strict $0/no-card/no-paid-overage constraints. This is a conclusion about these three current offerings, not proof no provider anywhere could fit.
- Existing hardware could preserve the architecture, conditional on an approved always-on machine, storage budget and reachable HTTPS route. No such operational arrangement is established.

## Asset permission and provenance

### MyDeadlift: strongest side-view candidate

[Publisher dataset, version 1](https://data.mendeley.com/datasets/w5prmmxyt9/1), DOI `10.17632/w5prmmxyt9.1`, published July 21, 2026 by Ivan Conanta and Gloria Virginia. It describes 191 one-repetition MP4s from seven male participants, fixed side view, iPhone 13, 1920×1080 at 30 fps. Its subject split holds out subjects 04 and 07. Body-pose angles and technique classes are not annotated bar/hub coordinates and cannot substitute for our reference annotations.

Actual browser file listing and file information inspected:

| Field | Observed value |
| --- | --- |
| Sample | `Gerakan Benar/GB_S01_R01.mp4`, 785 KB, uploaded July 19, 2026 |
| Asset page | https://data.mendeley.com/datasets/w5prmmxyt9/1/files/8cd7b69a-a1cf-4299-98a6-77edb3c7d9fc |
| Download link | https://data.mendeley.com/public-files/datasets/w5prmmxyt9/files/8cd7b69a-a1cf-4299-98a6-77edb3c7d9fc/file_downloaded |
| File-level license | CC BY 4.0, displayed in the sample's FILE INFORMATION panel |
| Publisher SHA-256 | `00ac077b0468064837f37d627867d975c4d89923da1879a9c23d61449eb807db` (not independently verified against downloaded bytes) |
| Visual inspection | File information inspected; media preview was still loading. No actual MP4 frame inspected. Side-view suitability is publisher-described until decoded. |

The file-level license supports local evaluation and conditional redistribution/CI use with attribution and retained notices. Future acquisition must check the selected file for any third-party exception; the publisher's license description explicitly preserves that qualification. This subject-01 sample is a development candidate, not the publisher's held-out subject. Inspect exact subject-04/07 files before selecting a test set.

### Commons: tiny licensed barbell footage

All three assets credit [FitnessScape](https://www.youtube.com/@FitnessScapeFitness), extracted by Prototyperspective from [Half Rack Workout](https://www.youtube.com/watch?v=0I6q9NqK9tM), originally published April 25, 2019. Commons uploads date March 19, 2025. The actual file licenses are **CC BY 3.0**, despite the newer YouTube license template name. Preserve the version actually stated for these assets.

| Asset and exact original | Size and format | Actual inspection and limitation |
| --- | --- | --- |
| [Squat asset page](https://commons.wikimedia.org/wiki/File:Squat_-_exercise_demonstration_video.webm); [original](https://upload.wikimedia.org/wikipedia/commons/5/5c/Squat_-_exercise_demonstration_video.webm) | 552 KB; VP9 WebM; 7.1 s; 1280×720 | Rendered final preview frame partially obscured by player sharing overlay; athlete/rack visible. Full bar/hub visibility over the rep was not established. |
| [Bench asset page](https://commons.wikimedia.org/wiki/File:Bench_press_-_exercise_demonstration_video.webm); [original](https://upload.wikimedia.org/wikipedia/commons/d/df/Bench_press_-_exercise_demonstration_video.webm) | 380 KB; VP9 WebM; 7.1 s; 1280×720 | Rendered footage frame inspected: athlete pressing a bar in a half rack, black plates, rack distractors and text overlay. View is oblique from the foot side, not perpendicular side view. |
| [Deadlift asset page](https://commons.wikimedia.org/wiki/File:Deadlift_-_exercise_demonstration_video.webm); [original](https://upload.wikimedia.org/wikipedia/commons/6/62/Deadlift_-_exercise_demonstration_video.webm) | 436 KB; VP9 WebM; 7.4 s; 1280×720 | Rendered final preview frame partially obscured by sharing overlay; both black plates/bar and rack visible. Oblique/front view, not perpendicular side view. |

Description revisions inspected: squat `oldid=1145684703`, bench `1145684665`, deadlift `1198177351`. Local evaluation and redistribution/CI are licensed subject to appropriate credit, asset title/source, license link and derivative-change notices. These share a source/environment, not three independent environments. Later actual asset inspection shows squat/deadlift use one apparent athlete and bench another; keep the shared source together conservatively. At this initial research checkpoint no downloaded-byte hashes/full-motion/timestamp review existed. The subsequent [acquisition report](licensed-media-inspection.md) supersedes those inspection limits for the four selected originals.

WebM is not established here as usable by the native importer. Commons lists QuickTime derivatives for squat/bench; alternatively a future licensed conversion can produce supported MP4/MOV. Pin original and converted hashes, transformation details and actual output presentation timestamps; never assume conversion preserves nominal timestamps or geometry. Conversion and native decoding remain unperformed.

### Additional candidate not selected

[Squats Wikipedia.webm](https://commons.wikimedia.org/wiki/File:Squats_Wikipedia.webm), own work by CRiles23, April 11, 2013: explicit CC BY-SA 3.0, 54 seconds, 960×540, 14.08 MB; [original](https://upload.wikimedia.org/wikipedia/commons/2/21/Squats_Wikipedia.webm). A rendered early preview frame showed an athlete near a rack; it did not establish a tracked barbell target or side view. Do not count it as a qualified barbell clip. Local evaluation is licensed; distributed adaptations require compatible ShareAlike terms as well as attribution. Selection awaits full footage inspection.

Repositories with a code license but no explicit video asset rights remain excluded. No private training clip was requested for upload or uploaded.

License conditions checked against primary [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) pages. Preserve asset licenses separately from code licensing. These licenses do not themselves establish all possible privacy/publicity permissions or imply creator endorsement.

## Minimum useful evaluation and missing coverage

Recommendation, subject to leader acceptance:

1. Start with three qualified clips, one per lift, for acquisition/native-decoding/annotation feasibility only. The Commons trio is a possible starter once full motion, target visibility and supported encoding are inspected; it cannot establish representative accuracy.
2. A small reviewable baseline needs at least nine qualified clips, three per lift, with at least two independent athlete/session groups per lift. Keep each subject/session and its exports in one partition. Separate development from held-out evaluation before threshold tuning.
3. Expand toward 18 clips, six per lift, spanning near-side plate sizes, rack/circular distractors, partial occlusion, lighting, camera motion and rotated/mirrored/VFR media. The number alone is insufficient: coverage and independent groups determine usefulness. Thresholds need resolution/annotation uncertainty and baseline evidence, not an invented universal pass rate.

MyDeadlift can add fixed-side deadlifts, but does not fill squat/bench coverage or broad camera/environment diversity. The Commons trio supplies one common environment and oblique views. Independent side-view squat and bench groups, challenging visibility cases, manual near-side hub references, actual native predictions and device measurements remain missing.

Use the existing [reference manifest](video-evaluation-manifest.md) and [scoring contract](video-scoring.md): source/version/permission record, original and derivative content hashes, source group/partition, upright geometry, exact CMTime presentation values and visibility/identity annotations. Body-pose labels are not ground truth for bar location. Preview inspection contributes no scored observations. Public-license assets can be used in CI only after notice/byte/codec review; private consent to local evaluation must not be treated as redistribution permission.

## Hosting requirements grounded in current service

The [service runbook](data-service-runbook.md) records Node 24 native SQLite and a measured indexed database of **1,343,746,048 bytes** (~1.25 GiB), CSV 826,444,366 bytes and ZIP 170,132,164 bytes. Initial import took 118.13 seconds on this Windows machine with process peak RSS 337,502,208 bytes (~322 MiB). This is not remote import latency or concurrent-serving memory evidence.

The [retention policy](snapshot-retention.md) protects current, rollback, newest snapshots, active leases and recent seven-day use. It is not a fixed disk cap. Seven daily DB versions alone use about 8.8 GiB. Illustrative staging budget: seven DBs + one new DB + one CSV + one ZIP is about **10.94 GiB**, before temporary indexes/sorts, binaries, logs or additional protected versions. Reserving around 20 GiB would be a planning starting point, not a measured peak guarantee; explicit monitoring and retention bounds remain needed.

The service also needs durable scheduling state, background refresh while the web service is idle, reachable HTTPS, and failure monitoring. The implemented wrapper has a **1,200-second hard execution limit**, six-hour successful-check cadence and scheduler polling/retry behavior described in the runbook. No permanent scheduler is installed. A short import completing does not prove recurring freshness.

## At most three current cloud options

| Option | Runtime, disk and scheduling | No-card/no-overage and TLS | Decision |
| --- | --- | --- | --- |
| Render Free | Node web services supported. SQLite writes are lost on restart/redeploy/15-minute idle spin-down; free persistent disks unavailable. Cron is not free and cannot access persistent disks. | Managed TLS supported. Without a payment method, bandwidth overages suspend services and build overages disable builds. | **No fit:** persistence and independent refresh fail, even if no-card suspension protects billing. |
| Koyeb Free | Container runtime: 512 MB RAM, 0.1 vCPU, 2 GB SSD; no persistent Volumes, no Worker Services; idle scale-to-zero after one hour. Two measured DB copies alone exceed available disk before retention. | Official signup requires a credit card; $29 authorization hold and selected-plan charge described. Free-service claim does not remove signup constraints. TLS was not independently checked because decisive constraints already fail. | **No fit:** card requirement, disk, persistence and background-worker constraints. |
| Oracle Always Free | VM can in principle host unchanged Node/SQLite and OS scheduling. Current official A1 allowance: 2 OCPUs/12 GB total; 200 GB combined boot/block storage in home region. Capacity shortages and idle VM reclamation are documented. | Most users need phone/card signup; no charge unless upgraded. No eligible no-card existing tenancy established. Public TLS/reverse proxy and scheduler would require configuration and validation; not already operational. | **No strict no-card fit established:** resource capacity is plausible, signup and operational reliability remain barriers. |

Primary sources checked:

- Render [free service limits](https://render.com/docs/free) and [cron jobs](https://render.com/docs/cronjobs). Cron minimum is $1/month, sufficient to reject strict $0; no paid alternative is recommended.
- Koyeb [instance limits](https://www.koyeb.com/docs/reference/instances) and [pricing FAQ](https://www.koyeb.com/docs/faqs/pricing). Signup-selected Pro charging is explicitly documented; do not initiate a signup/downgrade experiment.
- Oracle [Free Tier signup](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm) and [Always Free resource limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm). Avoid the outdated 4-OCPU/24-GB claim. Idle reclamation considers low usage over seven days; do not manufacture load to defeat that policy.

These findings preserve the existing architecture. A static site, expiring trial, free external SQL database or ephemeral function is not a validated replacement for this SQLite service.

## Existing hardware and next decisions

The existing machine already stores the database, but an approved always-on host, storage capacity, internet availability and reachable HTTPS route are not established. Sleep/offline intervals prevent reliable scheduled checks. An OS scheduler and TLS reverse proxy could preserve the current loopback service, conditional on user-approved availability/access; no scheduler, tunnel, public listener or firewall rule was installed. Existing hardware means no new cloud subscription, not proven zero electricity/network cost.

Leader decisions: approve a bounded asset-acquisition/decoding checkpoint using the explicit licensed sample/trio; select whether an existing always-on hardware path is available under the cost/access constraints. If hardware/access is unavailable, the hosting gate remains blocked rather than silently relaxing the constraints.

Next acquisition/inspection checkpoint can provisionally take 15–25 minutes after leader scope acceptance; native decoding/device accuracy timing depends on Apple execution/device availability and manual annotations. Research has no hard deadline. Full readiness has no reliable ETA until representative media and a hosting/device plan exist; estimate again after those choices and the first actual measurements. No extra CI is required for this research document.
