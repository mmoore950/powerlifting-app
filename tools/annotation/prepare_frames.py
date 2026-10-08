"""Explicit-file, bounded development frame export. No native parity claim."""
import argparse
import base64
import hashlib
import json
import pathlib
import sys
import time
from fractions import Fraction

MAX_FRAMES = 450
MAX_BYTES = 32 * 1024 * 1024


def file_digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def exact_timestamp(pts, time_base):
    t = Fraction(pts) * time_base
    if not -(2**63) <= t.numerator < 2**63 or not 0 < t.denominator <= 2147483647:
        raise ValueError('Decoded PTS cannot be represented by the reference contract')
    return {'value': str(t.numerator), 'timescale': t.denominator, 'epoch': 0}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['asset-root', 'media', 'output', 'tooling', 'clip-id', 'source-group', 'permission-evidence']:
        p.add_argument('--' + name, required=True)
    p.add_argument('--lift', required=True, choices=['squat', 'bench', 'deadlift'])
    p.add_argument('--split', choices=['training', 'development', 'holdout'], default='development')
    p.add_argument('--every', type=int, default=15, help='Keep every Nth actual decoded frame; never synthesize time')
    p.add_argument('--max-frames', type=int, default=60)
    args = p.parse_args()
    if args.every < 1 or not 1 <= args.max_frames <= MAX_FRAMES:
        p.error('Invalid sampling/count bound')
    root = pathlib.Path(args.asset_root).resolve(strict=True)
    media = pathlib.Path(args.media).resolve(strict=True)
    if media.stat().st_size > 512 * 1024 * 1024:
        p.error('Media exceeds the initial 512 MiB per-clip limit; explicitly prepare a shorter local excerpt')
    relative = media.relative_to(root).as_posix()
    output = pathlib.Path(args.output).resolve()
    if output.exists():
        p.error('Output already exists; use a fresh directory to preserve earlier drafts')
    sys.path.insert(0, str(pathlib.Path(args.tooling).resolve(strict=True)))
    import av
    source_hash = file_digest(media)
    clip = dict(id=args.clip_id, sourceGroup=args.source_group, sha256=source_hash,
                localPath=relative, split=args.split, synthetic=False,
                permissionEvidence=args.permission_evidence, lift=args.lift,
                targetID='near-side-hub')
    output.mkdir(parents=True)
    (output / 'frames').mkdir()
    frames, images, total, previous, dimensions = [], {}, 0, None, None
    started = time.monotonic()
    # Explicitly limited to development, because stream rotation, clean aperture,
    # AVAssetImageGenerator scaling/sample selection have not been verified here.
    with av.open(str(media)) as container:
        stream = container.streams.video[0]
        sample_aspect_ratio = stream.sample_aspect_ratio
        if sample_aspect_ratio not in (None, Fraction(0, 1), Fraction(1, 1)):
            raise ValueError('Non-square display pixels need an authoritative native frame export')
        for ordinal, frame in enumerate(container.decode(stream)):
            if ordinal >= 27000 or time.monotonic() - started > 120:
                raise ValueError('Decode preparation exceeded 27,000 frames / 120 seconds; use a shorter excerpt')
            if frame.rotation != 0:
                raise ValueError('Rotated display metadata needs an authoritative native frame export')
            if ordinal % args.every:
                continue
            if frame.pts is None or frame.time_base is None:
                raise ValueError('Missing actual decoded PTS')
            timestamp = exact_timestamp(frame.pts, frame.time_base)
            presentation_time = Fraction(int(timestamp['value']), timestamp['timescale'])
            if previous is not None and presentation_time <= previous:
                raise ValueError('Duplicate/unordered decoded PTS')
            previous = presentation_time
            image = frame.to_image()
            if dimensions is None:
                dimensions = image.size
            if image.size != dimensions or max(image.size) > 8192:
                raise ValueError('Changing/unsupported decoded geometry')
            frame_id = 'frame-' + str(len(frames)).zfill(6)
            filename = frame_id + '.png'
            image.save(output / 'frames' / filename)
            data = (output / 'frames' / filename).read_bytes()
            total += len(data)
            if total > MAX_BYTES:
                raise ValueError('Frame payload exceeds 32 MiB; use sparser sampling')
            frames.append(dict(id=frame_id, filename=filename, sha256=hashlib.sha256(data).hexdigest(), timestamp=timestamp))
            images[frame_id] = 'data:image/png;base64,' + base64.b64encode(data).decode('ascii')
            if len(frames) == args.max_frames:
                break
    if not frames:
        raise ValueError('No decoded frames')
    if file_digest(media) != source_hash:
        raise ValueError('Media changed during preparation')
    clip.update(uprightWidth=dimensions[0], uprightHeight=dimensions[1])
    ledger = dict(schemaVersion=1, purpose='development-only', nativeParityVerified=False,
                  decoder={'name': 'PyAV', 'version': av.__version__, 'transform': 'decoded raster; no preferred-track transform',
                           'aperture': 'decoder raster; native clean aperture unverified', 'scale': 'none',
                           'sampleAspectRatio': str(sample_aspect_ratio) if sample_aspect_ratio else 'unspecified', 'observedRotation': 0},
                  clip=clip, frames=frames)
    ledger_bytes = (json.dumps(ledger, ensure_ascii=True, indent=2) + '\n').encode()
    (output / 'ledger.json').write_bytes(ledger_bytes)
    bundle = dict(ledger=ledger, ledgerText=ledger_bytes.decode(), ledgerSha256=hashlib.sha256(ledger_bytes).hexdigest(), images=images)
    (output / 'bundle.json').write_text(json.dumps(bundle, ensure_ascii=True), encoding='utf-8')
    print(json.dumps({'output': str(output), 'frames': len(frames), 'imageBytes': total,
                      'purpose': 'development-only', 'nativeParityVerified': False}))


if __name__ == '__main__':
    main()
