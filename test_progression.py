"""Talisman tier changes update saved effects, not weapon power."""
import json
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL
from test_native_helpers import input_path

levels=[{'LevelEffects':[{'TypeTag':'SW.Effect.HealthBoost','Intensity':value,'UnknownLarge':90071992547409931234}]} for value in [1.2,1.3,1.4]]
fixture={'SerializeMeta':{'HardFormat':'FCharacterSaveV1'},'CharacterSaveV1':{'MetaData':{'IsOnline':False},'Ability':{'Attributes':[]},'Inventory':{'Entries':[{'ItemData':{'TypeTag':'SW.Item.Talisman.HealthBoost','RarityTag':'SW.Rarity.None','ItemProgression':{'CurrentLevel':0,'CurrentXP':0,'ItemLevels':levels},'GeneratorData':{'PowerGeneratorValues':{'ItemPower':-1,'ItemPowerOriginal':0,'ItemPowerMin':0,'ItemPowerMax':0}},'Effects':[{'TypeTag':'SW.Item.Effect.Upgradable','EffectsInThisBatch':levels[0]['LevelEffects']}]},'StackCount':1,'EquippedSlot':'None'}]}}}
text=json.dumps(fixture,separators=(',',':'))
with sync_playwright() as p:
    browser=launch_browser(p)
    page=browser.new_page()
    page.goto(EDITOR_URL)
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"test.sav")',text)
    page.locator('[data-native-tab="items"]').click()
    assert page.evaluate('DungeonsNative.getBytes().length')>0
    prefix=['CharacterSaveV1','Inventory','Entries',0,'ItemData']
    assert input_path(page,prefix+['GeneratorData','PowerGeneratorValues','ItemPower']).get_attribute('readonly') is not None
    field=input_path(page,prefix+['ItemProgression','CurrentLevel'])
    assert field.locator('option').all_text_contents()==['Tier 1','Tier 2','Tier 3']
    field.select_option('2')
    current=json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']
    assert current['ItemProgression']['CurrentLevel']==2
    assert current['Effects'][0]['EffectsInThisBatch']==levels[2]['LevelEffects']
    assert current['GeneratorData']['PowerGeneratorValues']['ItemPower']==-1
    assert '90071992547409931234' in page.evaluate('DungeonsNative.getText()')
    browser.close()
print('PASS: valid unedited talisman exports, tier selection updates exact effects and preserves special power and large numbers.')
