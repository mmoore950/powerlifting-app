"""Count the five named UI smokes, independently of generated native PNGs."""
import json
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1]).resolve()
manifest_file = root / 'manifest.json'
if manifest_file.stat().st_size > 1024 * 1024:
    raise ValueError('Attachment manifest exceeds 1MiB')
manifest = json.loads(manifest_file.read_text(encoding='utf-8'))
groups = [entry for entry in manifest if entry.get('testIdentifier') ==
          'ToolkitSmokeTests/testMainTabsRenderWithoutConnectedDataOrImportedVideo()']
if len(groups) != 1:
    raise ValueError('Expected exactly one UI smoke attachment group')
attachments = groups[0]['attachments']
expected = ['01-plates', '02-training', '03-attempts',
            '04-competition-disconnected', '05-bar-path-no-video']
for name in expected:
    matches = [entry for entry in attachments if entry.get('suggestedHumanReadableName', '').startswith(name + '_')]
    if len(matches) != 1 or matches[0].get('isAssociatedWithFailure') is not False:
        raise ValueError('Missing/ambiguous/failure UI smoke: ' + name)
    filename = matches[0]['exportedFileName']
    if pathlib.PurePath(filename).name != filename or '/' in filename or '\\' in filename or ':' in filename:
        raise ValueError('Unsafe exported screenshot path')
    image = root / filename
    if image.is_symlink() or not image.is_file() or not 24 <= image.stat().st_size <= 10 * 1024 * 1024:
        raise ValueError('Invalid screenshot file/size')
    with image.open('rb') as source:
        header = source.read(24)
    if header[:8] != b'\x89PNG\r\n\x1a\n' or not all(1 <= value <= 8192 for value in struct.unpack('>II', header[16:24])):
        raise ValueError('Invalid screenshot PNG geometry')
print('Verified exactly five named non-failure UI smoke PNG attachments; generated captures excluded')
