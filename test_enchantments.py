"""Enchantment creation must preserve other effects and large JSON numbers."""
import json
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL

effect={'TypeTag':'SW.Item.Effect.Rerollable','EffectsInThisBatch':[{'TypeTag':'SW.Effect.Looting','Intensity':0.2,'Quality':0,'EnchantmentPointsInvested':0,'GeneratorData':{'GeneratorParentTemplate':'SW.EffectTemplate.Looting.I','Locked':False},'UnknownLarge':90071992547409931234}]}
fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1'},'CharacterSaveV1':{'MetaData':{'IsOnline':False},'Ability':{'Attributes':[]},'Inventory':{'Entries':[{'ItemData':{'TypeTag':'SW.Item.Sword','RarityTag':'SW.Rarity.Common','Effects':[effect]},'StackCount':1,'EquippedSlot':'None'}]}}}
text=json.dumps(fixture,separators=(',',':'))
with sync_playwright() as p:
    browser=launch_browser(p)
    page=browser.new_page()
    errors=[]
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.goto(EDITOR_URL)
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"test.sav")',text)
    page.locator('[data-native-tab="items"]').click()
    page.locator('#native-enchant').click()
    assert page.locator('#enchantment-picker [data-enchantment-tag="SW.Enchantment.SoulInfusedPotion"]').count()==0
    page.locator('[data-enchantment-tag="SW.Enchantment.FireAspect"]').click()
    page.locator('#enchantment-tier').select_option('II')
    page.locator('#enchantment-apply').click()
    current=page.evaluate('DungeonsNative.getText()')
    rows=json.loads(current)['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects']
    assert rows[0]==effect
    assert rows[1]['TypeTag']=='SW.Item.Effect.Enchantment'
    enchant=rows[1]['EffectsInThisBatch'][0]
    assert enchant['TypeTag']=='SW.Enchantment.FireAspect'
    assert enchant['GeneratorData']['GeneratorParentTemplate']=='SW.Enchantment.FireAspect.II'
    rule=page.evaluate('DungeonsGameIcons.enchantmentRules.find(r=>r.tag==="SW.Enchantment.FireAspect")')
    assert enchant['Intensity']==next(t['value'] for t in rule['tiers'] if t['tier']=='II')
    assert '90071992547409931234' in current
    rows[1]['EffectsInThisBatch'][0]['UnknownLarge']=90071992547409931235
    fixture['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects']=rows
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"test.sav")',json.dumps(fixture,separators=(',',':')))
    page.locator('[data-native-tab="items"]').click()
    page.locator('#native-enchant').click()
    page.locator('[data-enchantment-tag="SW.Enchantment.FireAspect"]').click()
    page.locator('#enchantment-tier').select_option('III')
    page.locator('#enchantment-apply').click()
    current=page.evaluate('DungeonsNative.getText()')
    assert '90071992547409931235' in current
    assert len(json.loads(current)['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects'])==2
    page.locator('#native-unenchant').click()
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects']==[effect]
    assert not errors,errors
    browser.close()
print('PASS: compatible enchantment picker, correct tier/intensity, replacement/removal and exact preservation of other effects and large numbers.')
