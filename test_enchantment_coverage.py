"""Every compatible standard enchantment is visible, even without preset intensity."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL

root=Path(__file__).resolve().parent
rules=json.loads((root/'assets/enchantment-rules.json').read_text(encoding='utf-8'))['rules']
catalog=json.loads((root/'assets/icon-manifest.json').read_text(encoding='utf-8'))['entries']
gears=[e for e in catalog if e['kind']=='gear' and e.get('nativeFields',{}).get('slot')]
other={'TypeTag':'SW.Item.Effect.Rerollable','EffectsInThisBatch':[{'TypeTag':'SW.Effect.Looting','Intensity':0.2,'UnknownLarge':90071992547409931234}]}
fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1'},'CharacterSaveV1':{'MetaData':{'IsOnline':False},'Ability':{'Attributes':[]},'Inventory':{'Entries':[{'ItemData':{'TypeTag':'SW.Item.Sword','Effects':[other]},'StackCount':1,'EquippedSlot':'None'}]}}}
missing=0
with sync_playwright() as p:
    browser=launch_browser(p);page=browser.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto(EDITOR_URL)
    for rule in rules:
        gear=next(e for e in gears if e['nativeFields']['slot'] in rule['slots'])
        fixture['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['TypeTag']=gear['tag']
        text=json.dumps(fixture,separators=(',',':'))
        page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"fixture.sav")',text)
        page.locator('[data-native-tab="items"]').click()
        page.locator('#native-enchant').click()
        compatible=[r['tag'] for r in rules if gear['nativeFields']['slot'] in r['slots']]
        actual=page.locator('[data-enchantment-tag]').evaluate_all('els=>els.map(e=>e.dataset.enchantmentTag)')
        assert set(actual)==set(compatible),(gear['tag'],actual,compatible)
        button=page.locator(f'[data-enchantment-tag="{rule["tag"]}"]')
        assert button.locator('img').count()==1,rule['tag']
        button.click()
        assert page.locator('#enchantment-tier option').evaluate_all('els=>els.map(e=>e.value)')==[t['tier'] for t in rule['tiers']]
        for tier in rule['tiers']:
            page.locator('#enchantment-tier').select_option(tier['tier'])
            amount=page.locator('#enchantment-intensity')
            if tier['value'] is None:
                missing+=1
                assert amount.input_value()==''
                assert page.locator('#enchantment-apply').is_disabled()
                assert page.evaluate('DungeonsNative.getText()')==text
                amount.fill('invalid')
                assert amount.get_attribute('aria-invalid')=='true'
                assert page.locator('#enchantment-apply').is_disabled()
                amount.fill('Infinity')
                assert page.locator('#enchantment-apply').is_disabled()
            else:
                assert float(amount.input_value())==tier['value']
            amount.fill('0.75')
            assert page.locator('#enchantment-apply').is_enabled()
        page.locator('#enchantment-apply').click()
        current=page.evaluate('DungeonsNative.getText()')
        effects=json.loads(current)['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['Effects']
        enchant=effects[1]['EffectsInThisBatch'][0]
        assert effects[0]==other and enchant['TypeTag']==rule['tag']
        assert enchant['Intensity']==0.75
        assert enchant['GeneratorData']['GeneratorParentTemplate']==rule['tag']+'.'+rule['tiers'][-1]['tier']
        assert '90071992547409931234' in current
    assert not errors,errors
    browser.close()
print(f'PASS: all {len(rules)} standard enchantments, slot filtering, every tier, {missing} missing-value tiers requiring explicit input, custom values and original token preservation.')
