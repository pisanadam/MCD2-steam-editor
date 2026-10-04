"""Custom effect units, icons, validation, replacement and untouched JSON tokens."""
import json
import os
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL
from test_native_helpers import input_path

def effect(tag, value, template):
    return {'TypeTag':tag,'Intensity':value,'Quality':0,'GeneratorData':{'GeneratorParentTemplate':template,'Locked':False},'UnknownLarge':90071992547409931234}

effects=[{'TypeTag':'SW.Item.Effect.Rerollable','EffectsInThisBatch':[effect('SW.Effect.Sharpness',0.1,'SW.EffectTemplate.Sharpness.I'),effect('SW.Effect.CriticalHit',0.05,'SW.EffectTemplate.CriticalHit.I')]},{'TypeTag':'SW.Item.Effect.Enchantment','EffectsInThisBatch':[effect('SW.Enchantment.FireAspect',0.35,'SW.Enchantment.FireAspect.I')]}]
fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1'},'CharacterSaveV1':{'MetaData':{'IsOnline':False},'Ability':{'Attributes':[]},'Inventory':{'Entries':[{'ItemData':{'TypeTag':'SW.Item.Sword','RarityTag':'SW.Rarity.Common','Effects':effects},'StackCount':1,'EquippedSlot':'None'}]}}}
text=json.dumps(fixture,separators=(',',':'))
base=['CharacterSaveV1','Inventory','Entries',0,'ItemData','Effects']
sharp=base+[0,'EffectsInThisBatch',0,'Intensity']
chance=base+[0,'EffectsInThisBatch',1,'Intensity']
fire=base+[1,'EffectsInThisBatch',0,'Intensity']
with sync_playwright() as p:
    browser=launch_browser(p);page=browser.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(EDITOR_URL)
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"fixture.sav")',text)
    page.locator('[data-native-tab="items"]').click()
    assert page.locator('.effect-card img').count()==3
    assert page.locator('.effect-card img').evaluate_all('els=>els.every(e=>e.complete&&e.naturalWidth>0)')
    assert input_path(page,sharp).input_value()=='10'
    assert input_path(page,fire).input_value()=='35'
    assert page.evaluate('DungeonsNative.getText()')==text
    assert bytes(page.evaluate('Array.from(DungeonsNative.getBytes())')).decode()==text
    view=page.locator('[data-effect-view]').nth(0)
    view.select_option('multiplier')
    assert input_path(page,sharp).input_value()=='1.1'
    assert page.evaluate('DungeonsNative.getText()')==text
    field=input_path(page,sharp);field.fill('2.5');field.press('Tab')
    current=page.evaluate('DungeonsNative.getText()')
    assert current==text.replace('"Intensity":0.1','"Intensity":1.5',1)
    page.locator('[data-effect-view]').nth(0).select_option('percent')
    assert input_path(page,sharp).input_value()=='150'
    field=input_path(page,chance);field.fill('101');field.press('Tab')
    assert input_path(page,chance).get_attribute('aria-invalid')=='true'
    assert page.evaluate('DungeonsNative.getText()')==current
    assert page.evaluate('()=>{try{DungeonsNative.getBytes();return false}catch{return true}}')
    field=input_path(page,chance);field.fill('75');field.press('Tab')
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects'][0]['EffectsInThisBatch'][1]['Intensity']==0.75
    field=input_path(page,fire);field.fill('200');field.press('Tab')
    assert input_path(page,fire).input_value()=='200'
    page.locator('[data-effect-view]').nth(2).select_option('multiplier')
    assert input_path(page,fire).input_value()=='2'
    assert '90071992547409931234' in page.evaluate('DungeonsNative.getText()')
    page.locator('[data-effect-pick]').first.click()
    page.locator('[data-effect-choice="SW.Effect.Protection"]').click()
    page.locator('#effect-tier').select_option('SW.EffectTemplate.Protection.III')
    page.locator('#effect-apply').click()
    row=json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects'][0]['EffectsInThisBatch'][0]
    assert row['TypeTag']=='SW.Effect.Protection' and row['Intensity']==-0.2
    assert row['UnknownLarge']==90071992547409931234
    assert input_path(page,sharp).input_value()=='-20'
    field=input_path(page,sharp);field.fill('-101');field.press('Tab')
    assert input_path(page,sharp).get_attribute('aria-invalid')=='true'
    field=input_path(page,sharp);field.fill('-50');field.press('Tab')
    current=page.evaluate('DungeonsNative.getText()')
    page.locator('#settings-open').click()
    page.locator('#settings-language').select_option('tr')
    page.locator('#settings-close').click()
    assert page.locator('[data-effect-pick]').first.inner_text()=='Etkiyi değiştir'
    assert input_path(page,sharp).input_value()=='-50'
    assert page.evaluate('DungeonsNative.getText()')==current
    assert not errors,errors
    if os.environ.get('EFFECT_SCREENSHOT'):
        page.screenshot(path=os.environ['EFFECT_SCREENSHOT'],full_page=True)
    browser.close()
print('PASS: effect/enchantment icons, percentage/bonus multiplier conversion, no-op exact bytes, chance validation, replacement and large token preservation.')
