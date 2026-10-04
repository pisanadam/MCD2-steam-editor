"""Assemble a standalone no-network HTML with the exact downloaded icon bytes."""
import base64
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'assets/icon-manifest.json').read_text(encoding='utf-8'))
assets={}
for asset in manifest['assets']:
    path=ROOT/'assets'/asset['file']
    data=path.read_bytes()
    assert hashlib.sha256(data).hexdigest()==asset['sha256'],path
    assets[asset['id']]={'dataUrl':'data:'+asset['mimeType']+';base64,'+base64.b64encode(data).decode(),'width':asset['width'],'height':asset['height']}
rules=json.loads((ROOT/'assets/enchantment-rules.json').read_text(encoding='utf-8'))
bundle={**manifest,'assets':assets,'enchantmentRules':rules['rules']}
script='<script>window.DungeonsGameIcons='+json.dumps(bundle,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')+';</script>'
html=(ROOT/'index.template.html').read_text(encoding='utf-8')
html=html.replace('<!--GAME_ICONS_EMBED-->',script)
translations=json.loads((ROOT/'locales/en.json').read_text(encoding='utf-8'))
i18n='<script>window.DungeonsTranslations='+json.dumps(translations,ensure_ascii=False).replace('<','\\u003c')+';\n'+(ROOT/'i18n.js').read_text(encoding='utf-8')+'\n</script>'
html=html.replace('<!--I18N_CODE_EMBED-->',i18n)
html=html.replace('<!--NATIVE_CODE_EMBED-->','<script>\n'+(ROOT/'native.js').read_text(encoding='utf-8')+'\n</script>')
html=html.replace('<!--CATALOGUE_CODE_EMBED-->','<script>\n'+(ROOT/'catalogue.js').read_text(encoding='utf-8')+'\n</script>')
html=html.replace('<!--DESKTOP_CODE_EMBED-->','<script>\n'+(ROOT/'desktop.js').read_text(encoding='utf-8')+'\n</script>')
(ROOT/'index.html').write_text(html,encoding='utf-8')
print(f'Built index.html: {len(assets)} original icon assets, {len(html.encode())} bytes')
