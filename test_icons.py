"""Verify real source icons are complete, rendered offline, and mapped by exact ID."""
import hashlib
import json
from pathlib import Path
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL
ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'assets/icon-manifest.json').read_text(encoding='utf-8'))
assert len(manifest['assets'])==440
for asset in manifest['assets']:
    data=(ROOT/'assets'/asset['file']).read_bytes()
    assert hashlib.sha256(data).hexdigest()==asset['sha256']
for entry in manifest['entries']:
    assert entry['assetId'] in {a['id'] for a in manifest['assets']}

fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1','InternalVersion':0,'SoftVersion':5},'CharacterSaveV1':{'MetaData':{'IsOnline':False,'Level':7},'Ability':{'Attributes':[{'AttributeName':'Emeralds','CurrentValue':55}]},'Inventory':{'Entries':[{'ItemData':{'TypeTag':'SW.Item.Sword','RarityTag':'SW.Rarity.Common','Effects':[{'TypeTag':'SW.Item.Effect.Enchantment','EffectsInThisBatch':[{'TypeTag':'SW.Enchantment.FireAspect','Intensity':0.45,'GeneratorData':{'GeneratorParentTemplate':'SW.Enchantment.FireAspect.II'}}]}]},'StackCount':1,'EquippedSlot':'None'}]}}}
with sync_playwright() as p:
    browser=launch_browser(p)
    context=browser.new_context(viewport={'width':1440,'height':1050})
    page=context.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(EDITOR_URL)
    page.evaluate("DungeonsI18n.setLanguage('tr',false)")
    context.set_offline(True)
    assert page.locator('svg').count()==0, 'No representative drawings in the product'
    total=page.evaluate('''async () => {
      const assets=Object.values(DungeonsGameIcons.assets);
      for(let i=0;i<assets.length;i+=16)await Promise.all(assets.slice(i,i+16).map(async a=>{const img=new Image();img.src=a.dataUrl;await img.decode();if(img.naturalWidth!==a.width||img.naturalHeight!==a.height)throw Error('Image dimensions mismatch')}));
      return assets.length;
    }''')
    assert total==440
    page.locator('[data-view="catalog"]').click()
    assert page.locator('.catalog-card').count()==296
    page.locator('#catalog-search').fill('Sword')
    assert 1<=page.locator('.catalog-card').count()<296
    page.locator('#catalog-search').fill('')
    page.locator('[data-catalog-group="enchantment"]').click()
    assert page.locator('.catalog-card').count()==34
    page.locator('[data-catalog-group="skin"]').click()
    assert page.locator('.catalog-card').count()==28
    page.locator('[data-catalog-group="gear"]').click()
    page.screenshot(path=str(ROOT/'preview-real-icons.png'),full_page=True)
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"Character-test.sav")',json.dumps(fixture))
    page.locator('[data-native-tab="items"]').click()
    image=page.locator('.preview img')
    assert image.count()==1
    sword_id=manifest['entries'][manifest['byTag']['SW.Item.Sword']]['assetId']
    assert image.get_attribute('src')==page.evaluate('(id)=>DungeonsGameIcons.assets[id].dataUrl',sword_id)
    assert page.locator('.effect-portrait img').count()==1
    page.screenshot(path=str(ROOT/'preview-real-save.png'),full_page=True)
    fixture['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['TypeTag']='SW.Item.UnknownFutureItem'
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"Character-test.sav")',json.dumps(fixture))
    page.locator('[data-native-tab="items"]').click()
    assert page.locator('.preview img').count()==0
    assert 'bulunamadı' in page.locator('.preview').inner_text()
    page.set_viewport_size({'width':390,'height':844})
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    assert not errors,errors
    browser.close()
print('PASS: 440 exact-source image hashes and browser decodes, 296 gear/34 enchant/28 skins catalogue, offline rendering, exact Sword/Fire Aspect mapping, unknown IDs use no replacement art, mobile/no JS errors')
