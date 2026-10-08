# Imported-video loss review navigation scope

Scope only, October 8, 2026, 08:01 ET. No implementation or additional CI.

## Concrete evidence

The product brief requires synchronized playback, explicit loss/occlusion handling,
and correction without a fabricated continuation. Existing code supplies:

- `App/VideoAnalysisView.swift:36`: Play/Pause and a whole-video playhead slider;
  line 57 displays only an aggregate decoded-frame/gap count. There is no loss
  episode selection or jump action, so the user must scrub to find abstentions.
- `App/BarAnalysisService.swift:117`: manual loss produces explicit `.lost` samples
  and remains lost until explicit reinitialization. Line 136 counts samples with
  no point; this is a count of abstaining frames, not distinct gap episodes.
- `Packages/LiftingCore/Sources/LiftingCore/VideoTrace.swift:119`: rendering breaks
  on lost/low-confidence samples, time gaps and target changes. It does not invent
  a continuation, but the accumulating path does not identify where to review loss.
- `App/VideoModel.swift:131`: tapping records a manual reference, clearing an
  existing analysis first. Line 149 uses only a manual reference within 0.05s of
  rep start to seed a new full-window manual analysis. A mid-rep annotation does
  not resume an already completed tracker. Existing labels correctly call these
  annotations rather than an automatic correction.

## Recommended bounded slice

Add review navigation for explicit no-target episodes in the currently published
analysis. Keep the existing manual annotation/reanalysis behavior and renderer.

1. Derive consecutive `.lost` sample runs from the existing ordered trace, recording
   first/last sample indices and count. These are observed sample runs, not inferred
   continuous intervals or an assertion about why the target was lost. Do not
   reinterpret low heuristic scores as calibrated probabilities or invent losses
   between decoded timestamps.
2. Display abstaining-frame count separately from the derived episode count. Add
   Previous/Next loss episode actions and the selected episode's observed start
   timestamp/count, enabling review of repeated losses without manually scrubbing
   the entire clip. Disable controls when no analysis/episode exists or processing
   is active; clear navigation selection when analysis/video/rep identity changes.
3. Jump/pause using the selected first sample's existing actual presentation time,
   retaining its rational value/timescale/epoch where available in BarFrameTime.
   Wait for seek completion and reject replaced-player/clip/analysis callbacks
   before publishing the new playhead. A seek failure surfaces an error rather
   than claiming the selected frame is visible. No frame-exact decoder guarantee
   follows from requesting an AVPlayer seek; native visual verification is required.
4. Explain that navigation reviews frames with no accepted target. A manual tap
   remains an annotation and a new manual analysis still starts at the selected
   rep's start; loss review itself must not connect paths or imply reacquisition.
   Expose episode count/selection and actions to accessibility.

Likely files: core VideoTrace helper/tests, VideoModel, VideoAnalysisView, existing
VideoMediaLifecycleTests only if a generated-media seek/lifecycle check is feasible,
and native-validation/status documentation. No detector change, interpolation,
private clip, upload, library/hosting/service or evaluation format change.

## Evidence and timing

Meaningful pure cases: separated and consecutive lost runs, all-lost/no-lost/empty
trace, preserved original sample indices/timestamps, and no grouping across an
accepted point. A generated local movie can exercise navigation seeks/replacement
on Apple without private media; source tests on Windows remain uncompiled/unrun.
Native interaction must review multiple gaps, playback boundaries, rapid jumps,
failed/replaced seek, trim/analysis replacement and VoiceOver. Real bar accuracy,
reacquisition identity and private research readiness remain separate.

Scope checkpoint complete within provisional 5–10 minutes, no hard deadline.
If approved, source/tests checkpoint 20–35 minutes, no hard deadline; uncertainty
is asynchronous AVPlayer seek lifetime and generated test feasibility. Re-estimate
after source review or concrete native failure. Run20 outcome takes priority:
provisional result 15–22 minutes after its 07:59 ET start, build 8/test 10/job 30
minute hard workflow limits. A finished run does not establish real-video accuracy
or release readiness. No further dispatch/retry is proposed here.
