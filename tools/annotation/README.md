# Offline annotation development tools

Entry point: `offline-via.html`. See [the user guide](../../docs/local-annotation-guide.md), including the pending browser acceptance gate before private use.

`vendor/via-2.0.12.html` is pinned unmodified upstream provenance, not the entry point; it includes the original analytics script. Do not open it with private data. `build_offline.py` reproduces the derivative from those exact reviewed bytes and local panel/shared JSON source. `provenance.json` records upstream and derivative digests and changes. Both HTML files retain the full upstream BSD 2-Clause notice. No upstream download occurs during build.

Public/synthetic frame bundles, media, saved drafts and export reports are ignored artifacts, not repository assets. `prepare_frames.py` accesses only an explicitly named media file under an explicitly named root and already provisioned tooling. `adapt_labels.mjs` verifies the separate authoritative ledger and actual media/images, invokes the existing reference validator and emits development drafts; native scoring is refused until a separate native bundle contract exists.
