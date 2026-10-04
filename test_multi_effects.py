"""Append, target edit/remove and undo must preserve every other saved effect."""
import json
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL

fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1'},'CharacterSaveV1':{'MetaData':{'IsOnline':False},'Ability':{'Attributes':[]},'Inventory':{'Entries':[{'ItemData':{'TypeTag':'SW.Item.Sword','Effects':[]},'StackCount':1,'EquippedSlot':'None','UnknownLarge':90071992547409931234}]}}}
text=json.dumps(fixture,separators=(',',':'))
def effects(page):
    return json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects']
def enchants(page):
    return [e for b in effects(page) if b['TypeTag']=='SW.Item.Effect.Enchantment' for e in b['EffectsInThisBatch']]
def properties(page):
    return [e for b in effects(page) if b['TypeTag']=='SW.Item.Effect.Rerollable' for e in b['EffectsInThisBatch']]
with sync_playwright() as p:
    browser=launch_browser(p);page=browser.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(EDITOR_URL)
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"fixture.sav")',text)
    page.locator('[data-native-tab="items"]').click()
    for tag,tier in [('SW.Enchantment.FireAspect','II'),('SW.Enchantment.Thundering','III')]:
        page.locator('#native-enchant').click()
        page.locator(f'[data-enchantment-tag="{tag}"]').click()
        page.locator('#enchantment-tier').select_option(tier)
        page.locator('#enchantment-apply').click()
    assert [e['TypeTag'] for e in enchants(page)]==['SW.Enchantment.FireAspect','SW.Enchantment.Thundering']
    thunder=enchants(page)[1].copy()
    for tag in ['SW.Effect.Sharpness','SW.Effect.Protection']:
        page.locator('#native-effect-add').click()
        page.locator(f'[data-effect-choice="{tag}"]').click()
        page.locator('#effect-apply').click()
    assert len(enchants(page))==2 and len(properties(page))==2
    assert page.locator('.effect-card').count()==4
    page.locator('[data-enchantment-edit]').first.click()
    page.locator('[data-enchantment-tag="SW.Enchantment.FireAspect"]').click()
    page.locator('#enchantment-tier').select_option('III')
    page.locator('#enchantment-apply').click()
    assert len(enchants(page))==2 and enchants(page)[0]['Intensity']==0.5
    assert enchants(page)[1]==thunder
    before=page.evaluate('DungeonsNative.getText()')
    page.locator('.effect-card').filter(has=page.locator('[data-enchantment-edit]')).first.locator('[data-effect-remove]').click()
    assert enchants(page)==[thunder] and len(properties(page))==2
    page.locator('#native-undo').click()
    assert page.evaluate('DungeonsNative.getText()')==before
    page.locator('.effect-card').filter(has=page.locator('[data-effect-pick]')).first.locator('[data-effect-remove]').click()
    assert len(properties(page))==1 and len(enchants(page))==2
    page.locator('#native-unenchant').click()
    assert not enchants(page) and len(properties(page))==1
    page.locator('[data-effect-remove]').click()
    assert effects(page)==[]
    assert '90071992547409931234' in page.evaluate('DungeonsNative.getText()')
    assert page.evaluate('DungeonsNative.getBytes().length')>0
    # Existing batches and unknown fields are preserved byte for byte on append.
    batch={'TypeTag':'SW.Item.Effect.Enchantment','EffectsInThisBatch':[thunder],'UnknownBatch':90071992547409931235}
    fixture['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects']=[batch]
    text=json.dumps(fixture,separators=(',',':'))
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"fixture.sav")',text)
    page.locator('[data-native-tab="items"]').click()
    page.locator('#native-enchant').click()
    page.locator('[data-enchantment-tag="SW.Enchantment.FireAspect"]').click()
    page.locator('#enchantment-apply').click()
    assert effects(page)[0]['UnknownBatch']==90071992547409931235
    assert enchants(page)[0]==thunder and len(enchants(page))==2
    page.locator('#native-undo').click()
    assert page.evaluate('DungeonsNative.getText()')==text
    assert not errors,errors
    browser.close()
print('PASS: multiple enchantments/properties, individual edit/remove, clear, empty batches, exact undo and large token preservation.')
