"""Reproduce the pinned VIA 2 derivative without fetching any upstream resources."""
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
PIN = 'a225d22d89fd5b901769670fb94d4e117543d748c1c2dd8cf2fa7a4777f08322'
source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'vendor' / 'via-2.0.12.html'
raw = source.read_bytes()
if hashlib.sha256(raw).hexdigest() != PIN:
    raise ValueError('Upstream source hash does not match reviewed VIA 2.0.12')
html = raw.decode('utf-8')
html, n = re.subn(r'<script type="text/javascript">\s*\(function\(i,s,o,g,r,a,m\).*?</script>', '', html, flags=re.S)
if n != 1:
    raise ValueError('Expected exactly one pinned analytics block')
# Remove remote import/project load/search-path implementations, not merely their UI.
disabled = ['project_file_add_url_with_input','project_file_add_url_input_done','project_file_add_url',
            'project_file_add_abs_path_with_input','project_file_add_abs_path_input_done',
            'project_open','project_open_parse_json_file','project_open_select_project_file','_via_file_resolve','_via_file_resolve_all_to_default_filepath',
            'sel_local_images','sel_local_data_file']
removed = []
for name in disabled:
    pattern = r'^function ' + re.escape(name) + r'\([^\n]*\) \{.*?^\}'
    replacement = 'function ' + name + '() { throw Error("Use the local frame bundle and draft controls"); }'
    html, count = re.subn(pattern, replacement, html, flags=re.M | re.S)
    if count:
        removed.append(name)
html = re.sub(r'href\s*=\s*([\'"])(?:https?:|mailto:|//).*?\1', 'href="#"', html, flags=re.I)
# Use the visible navigation/clear/save controls; upstream keyboard shortcuts can
# invoke hidden import dialogs or mutate reviewed labels outside the wrapper.
html, keyboard_count = re.subn(r'^function _via_init_keyboard_handlers\(\) \{.*?^\}',
    'function _via_init_keyboard_handlers() { /* Visible local controls own keyboard interaction. */ }', html, flags=re.M | re.S)
if keyboard_count != 1:
    raise ValueError('Expected pinned keyboard initialization')
csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none'"
html = html.replace('<head>', '<head>\n<meta http-equiv="Content-Security-Policy" content="' + csp + '">', 1)
html = html.replace('<title>VGG Image Annotator</title>', '<title>Offline hub annotation · development</title>', 1)
panel = (ROOT / 'offline_panel.html').read_text(encoding='utf-8')
html = html.replace('<div class="top_panel" id="ui_top_panel">', '<div class="top_panel" id="ui_top_panel">\n' + panel, 1)
strict_json = (ROOT / 'strict_json.mjs').read_text(encoding='utf-8').replace('export function parseStrictJSON', 'function parseStrictJSON')
native_contract = (ROOT / 'native_contract.mjs').read_text(encoding='utf-8').replace('export function validateNativeContract', 'function validateNativeContract')
html = html.replace('</body>', '<script>\n' + strict_json + '\n' + native_contract + '\n' + (ROOT / 'offline_panel.js').read_text(encoding='utf-8') + '\n</script>\n</body>', 1)
output = ('\n'.join(line.rstrip() for line in html.splitlines())+'\n').encode('utf-8')
(ROOT / 'offline-via.html').write_bytes(output)
(ROOT / 'provenance.json').write_text(json.dumps(dict(upstreamVersion='2.0.12',
    upstreamURL='https://www.robots.ox.ac.uk/~vgg/software/via/via.html', upstreamSHA256=PIN,
    derivativeSHA256=hashlib.sha256(output).hexdigest(), disabledFunctions=removed,
    changes=['Removed Google Analytics script', 'Removed remote import/project-load/search-path implementations',
             'Neutralized remote links', 'Disabled upstream shortcuts to hidden dialogs', 'Removed inherited trailing whitespace', 'Added restrictive CSP', 'Added explicit local frame/draft labeling controls', 'Added shared native producer contract validation'],
    license='BSD-2-Clause; full upstream notice retained in both HTML files'), indent=2)+'\n', encoding='utf-8')
print('Offline derivative SHA256', hashlib.sha256(output).hexdigest())
