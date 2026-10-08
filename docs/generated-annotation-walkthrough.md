# Try labeling with the generated demo

Use this three-frame synthetic exercise to learn the controls. It contains no
real lift or near-side hub truth. It does not establish native tracking accuracy.

## Open the demo

Open [the local annotation page](/C:/codex/powerlifting-app/tools/annotation/offline-via.html)
in a browser that permits local HTML. Choose **Load frame bundle**, then select
[this generated bundle](/C:/codex/powerlifting-app/artifacts/annotation-demo-20261008-recovery/bundle.json).
The corresponding [demo folder](/C:/codex/powerlifting-app/artifacts/annotation-demo-20261008-recovery)
contains the unchanged ledger, frames and example drafts. Keep them together.

This page was previously exercised through loopback HTML serving. Direct local
file behavior remains unverified: the automated browser permits HTTP/HTTPS only
and rejected the file URL. These instructions are an exercise, not a report of
new browser acceptance.

## Mark a visible point

1. On frame1/3, **Zoom in** if useful. The generated cross marks original image
   pixel `(100,150)`; it is a practice target, not a real hub.
2. Click the cross. Drag to correct it or choose **Clear point** and click again.
3. Select **visible**, enter uncertainty radius **2** original pixels, then
   **Mark reviewed**. Point edits mark the frame unreviewed again.
4. Choose **Save draft** before closing or switching bundles. A local JSON
   download is the recovery copy. Keep older drafts until the new one validates.

The earlier actual browser exercise captured this screen:

![Generated example with visible point and original timestamp](/C:/codex/powerlifting-app/artifacts/annotation-demo-20261008-recovery/synthetic-zoom-roundtrip.jpg)

The unchanged first timestamp is `9007199254740993/600`, epoch0. **Next frame**
shows `9007199254740994/600`. Preserve these strings; do not calculate replacement
times from playback or rounded decimal values.

## Change the label to occluded

Choose **Clear point**, then **occluded** and **Mark reviewed**. The label must
have no point or uncertainty. The page refuses a non-visible label with a stale
point. **outside-frame** and **uncertain** follow the same rule. Leave a frame
unreviewed when undecided.

Save another draft. For recovery, load this same bundle, then **Reload saved
draft**. Unsaved edits must be saved first; after saving, reselecting the same
draft works. **Export labels** downloads the strict label envelope for validation.
A draft from a different ledger is refused.

## Verified examples

The saved examples let you compare results without claiming a new browser run:

| Example | Reviewed label | Original point | Other frames |
| --- | --- | --- | --- |
|[Visible draft](/C:/codex/powerlifting-app/artifacts/annotation-demo-20261008-recovery/reviewed-visible-draft.json)|visible, uncertainty2|(100,150), normalized(0.25,0.75)|unreviewed|
|[Occluded draft](/C:/codex/powerlifting-app/artifacts/annotation-demo-20261008-recovery/reviewed-occluded-draft.json)|occluded|none|unreviewed|

On October8 at approximately07:07ET, both examples were rerun through the existing
strict adapter against actual local source/PNG bytes and the unchanged ledger.
Fresh outputs are in
[the walkthrough result folder](/C:/codex/powerlifting-app/artifacts/annotation-walkthrough-20261008).
Each report has1synthetic annotation,0observed annotations,2unreviewed frames,
`development-only` and `nativeParityVerified:false`. The original exact timestamp
survived; visible normalized coordinates and occluded null point/uncertainty were
checked. This is a local adapter check of previous browser exports.

For a new export, follow the explicit command in
[the full local annotation guide](local-annotation-guide.md#validate-and-export-a-development-draft),
substituting the actual new download and a fresh output filename. Native captures
require their own images, unchanged ledger and associated source/prediction bytes;
this generated PyAV demo cannot be renamed into native scoring evidence.

## Gate before private use

Private use remains blocked on an **independent browser request/privacy audit**
and **direct file-URL behavior**. Prior page instrumentation and loopback HTML
GET logs cover only the observed exercise; they do not independently audit the
browser network stack. Browser controls currently expose no request-log surface,
and file URLs are rejected by browser URL policy. The next estimate can be made
when an allowed audit/file-opening surface or human verification result exists;
there is no reliable completion date now. No private footage was used here.
