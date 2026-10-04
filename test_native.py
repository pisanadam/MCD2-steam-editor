"""Synthetic fixtures; does not assert live-game compatibility."""
import json
import tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL, ROOT

# Format derived from community code; no real player identifiers.
entry = {'ItemData':{'TypeTag':'SW.Item.Sword','RarityTag':'SW.Rarity.Common','GeneratorData':{'PowerGeneratorValues':{'ItemPower':2,'ItemPowerOriginal':2,'ItemPowerMin':1,'ItemPowerMax':3}},'Effects':[{'TypeTag':'SW.Item.Effect.Enchantment','EffectsInThisBatch':[{'TypeTag':'SW.Enchantment.FireAspect','Intensity':0.45,'Quality':0,'GeneratorData':{'GeneratorParentTemplate':'SW.Enchantment.FireAspect.II'}}]}],'TargetSlotOverride':'None'},'StackCount':1,'EquippedSlot':'SW.ItemSlot.Equipment.MeleeWeapon','Unknown':90071992547409931234}
fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1','SoftVersion':5},'CharacterSaveV1':{'MetaData':{'IsOnline':False,'Level':7,'GameDataUpdated':639263000000000000},'Ability':{'Attributes':[{'AttributeName':'Emeralds','CurrentValue':55},{'AttributeName':'Level','CurrentValue':7},{'AttributeName':'XP','CurrentValue':845.5}]},'Inventory':{'Entries':[entry]},'Cosmetics':{'Skin':'SW.Skin.Ranger'},'UnknownNumber':90071992547409931234}}
text=json.dumps(fixture,separators=(',',':'),ensure_ascii=False)

def input_path(page,path):
    encoded=json.dumps(path,separators=(',',':'))
    fields=page.locator('[data-native-path]')
    index=fields.evaluate_all('(els,k)=>els.findIndex(e=>e.dataset.nativePath===k)',encoded)
    assert index>=0, path
    return fields.nth(index)

with sync_playwright() as p,tempfile.TemporaryDirectory() as tmp:
    browser=launch_browser(p)
    page=browser.new_page(viewport={'width':1440,'height':1100})
    errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(EDITOR_URL)
    page.evaluate("DungeonsI18n.setLanguage('tr',false)")
    f=Path(tmp)/'Character-test.sav'; f.write_text(text,encoding='utf-8')
    page.locator('#native-file').set_input_files(str(f))
    assert page.locator('#native-view').is_visible()
    with page.expect_download() as d: page.locator('#native-export').click()
    out=Path(tmp)/'out.sav';d.value.save_as(out)
    assert out.read_bytes()==f.read_bytes(), 'Unedited round trip must preserve every byte'
    inp=input_path(page,['CharacterSaveV1','Ability','Attributes',0,'CurrentValue']);inp.fill('100000');inp.press('Tab')
    assert page.evaluate('DungeonsNative.getText()')==text, 'Reject emeralds beyond current official cap'
    inp=input_path(page,['CharacterSaveV1','Ability','Attributes',0,'CurrentValue']);inp.fill('9999');inp.press('Tab')
    current=page.evaluate('DungeonsNative.getText()')
    assert current==text.replace('"CurrentValue":55','"CurrentValue":9999'), 'Only emerald token changed'
    page.locator('#native-undo').click()
    assert page.evaluate('DungeonsNative.getText()')==text
    inp=input_path(page,['CharacterSaveV1','Ability','Attributes',1,'CurrentValue']);inp.fill('10');inp.press('Tab')
    updated=json.loads(page.evaluate('DungeonsNative.getText()'))
    assert updated['CharacterSaveV1']['MetaData']['Level']==10
    assert updated['CharacterSaveV1']['UnknownNumber']==90071992547409931234
    inp=input_path(page,['CharacterSaveV1','MetaData','Level']);inp.fill('-1');inp.press('Tab')
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['MetaData']['Level']==10
    inp.fill('10');inp.press('Tab')
    page.locator('[data-native-tab="items"]').click()
    count=input_path(page,['CharacterSaveV1','Inventory','Entries',0,'StackCount']);count.fill('0');count.press('Tab')
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['StackCount']==1
    count.fill('1');count.press('Tab')
    power=input_path(page,['CharacterSaveV1','Inventory','Entries',0,'ItemData','GeneratorData','PowerGeneratorValues','ItemPower']);power.fill('8');power.press('Tab')
    updated=json.loads(page.evaluate('DungeonsNative.getText()'))
    values=updated['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['GeneratorData']['PowerGeneratorValues']
    assert set(values.values())=={8}
    enchant_path=['CharacterSaveV1','Inventory','Entries',0,'ItemData','Effects',0,'EffectsInThisBatch',0,'GeneratorData','GeneratorParentTemplate']
    inp=input_path(page,enchant_path);inp.select_option('SW.Enchantment.FireAspect.III')
    assert 'SW.Enchantment.FireAspect.III' in page.evaluate('DungeonsNative.getText()')
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects'][0]['EffectsInThisBatch'][0]['Intensity']==0.5
    page.locator('#native-clone').click()
    updated=json.loads(page.evaluate('DungeonsNative.getText()'))
    entries=updated['CharacterSaveV1']['Inventory']['Entries']
    assert len(entries)==2 and entries[1]['EquippedSlot']=='None'
    assert entries[0]['Unknown']==entries[1]['Unknown']==90071992547409931234
    page.locator('#native-delete').click()
    assert len(json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'])==1
    with page.expect_download() as d:page.locator('#native-backup').click()
    backup=Path(tmp)/'backup';d.value.save_as(backup)
    assert backup.read_bytes()==f.read_bytes()
    prior=page.evaluate('DungeonsNative.getText()')
    online=Path(tmp)/'online.sav';online.write_text(text.replace('"IsOnline":false','"IsOnline":true'),encoding='utf-8')
    page.locator('#native-file').set_input_files(str(online))
    page.wait_for_function("document.querySelector('#toast').textContent.includes('IsOnline=false')")
    assert page.evaluate('DungeonsNative.getText()')==prior
    missing=Path(tmp)/'missing.sav';malformed=json.loads(text);del malformed['CharacterSaveV1']['Ability']['Attributes'][0]['CurrentValue'];missing.write_text(json.dumps(malformed))
    page.locator('#native-file').set_input_files(str(missing))
    page.wait_for_function("document.querySelector('#toast').textContent.includes('attributes')")
    assert page.evaluate('DungeonsNative.getText()')==prior
    bad=Path(tmp)/'binary.sav';bad.write_bytes(b'GVAS\x00\xff\x12')
    page.locator('#native-file').set_input_files(str(bad))
    page.wait_for_function("document.querySelector('#toast').textContent.includes('Kayıt açılamadı')")
    assert page.evaluate('DungeonsNative.getText()')==prior
    bom=Path(tmp)/'bom.sav';bom.write_bytes(b'\xef\xbb\xbf'+text.encode())
    page.locator('#native-file').set_input_files(str(bom))
    with page.expect_download() as d:page.locator('#native-export').click()
    d.value.save_as(out);assert out.read_bytes()==bom.read_bytes()
    page.locator('[data-native-tab="items"]').click()
    page.locator('#native-delete').click()
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries']==[]
    page.locator('#native-undo').click()
    page.set_viewport_size({'width':390,'height':844})
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    assert not errors,errors
    page.screenshot(path=str(ROOT/'preview-native.png'),full_page=True)
    browser.close()
    print('PASS: native exact bytes, 64-bit token preservation, scalar edits, level/power consistency, enchant fields, copy/delete/undo, original backup, online/binary rejection, BOM, empty inventory, mobile')
