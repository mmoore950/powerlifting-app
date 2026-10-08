"""Clearly synthetic images for coordinate/PTS browser verification, never real labels."""
import base64
import hashlib
import json
import pathlib
import sys
from PIL import Image, ImageDraw

root = pathlib.Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=False)
(root / 'frames').mkdir()
media = b'Clearly synthetic UI fixture, not real lifting media\n'
(root / 'synthetic.bin').write_bytes(media)
clip = dict(id='synthetic-ui-demo', sourceGroup='synthetic-ui-demo', sha256=hashlib.sha256(media).hexdigest(),
            localPath='synthetic.bin', split='development', synthetic=True, permissionEvidence='Generated synthetic UI test fixture',
            lift='synthetic', targetID='near-side-hub', uprightWidth=400, uprightHeight=200)
frames, images = [], {}
for i in range(3):
    image = Image.new('RGB', (400, 200), '#eeeeee')
    d = ImageDraw.Draw(image)
    d.text((12, 12), 'SYNTHETIC TEST - no real lift/reference', fill='black')
    d.line((90, 150, 110, 150), fill='red', width=1)
    d.line((100, 140, 100, 160), fill='red', width=1)
    d.text((115, 145), 'pixel (100,150)', fill='black')
    ident = 'frame-' + str(i).zfill(6)
    filename = ident + '.png'
    image.save(root / 'frames' / filename)
    data = (root / 'frames' / filename).read_bytes()
    frames.append(dict(id=ident, filename=filename, sha256=hashlib.sha256(data).hexdigest(),
                       timestamp={'value': str(9007199254740993+i), 'timescale': 600, 'epoch': 0}))
    images[ident] = 'data:image/png;base64,' + base64.b64encode(data).decode()
ledger = dict(schemaVersion=1, purpose='development-only', nativeParityVerified=False,
              decoder=dict(name='PyAV', version='synthetic fixture; not decoder evidence', transform='synthetic raster', aperture='synthetic', scale='none'),
              clip=clip, frames=frames)
data = (json.dumps(ledger, indent=2)+'\n').encode()
(root / 'ledger.json').write_bytes(data)
(root / 'bundle.json').write_text(json.dumps(dict(ledger=ledger, ledgerText=data.decode(), ledgerSha256=hashlib.sha256(data).hexdigest(), images=images)), encoding='utf-8')
print(root / 'bundle.json')
