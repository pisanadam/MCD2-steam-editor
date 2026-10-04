import json
from pathlib import Path
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL
from test_native_helpers import input_path

out = Path(__file__).resolve().parents[2] / 'outputs' / '1000-Zumrut-Testi'
source = next((out/'Once').glob('Character*.sav'))
original = json.loads(source.read_bytes())
attributes = original['CharacterSaveV1']['Ability']['Attributes']
index = next(i for i,a in enumerate(attributes) if a['AttributeName']=='Emeralds')
before = attributes[index]['CurrentValue']
with sync_playwright() as p:
    browser = launch_browser(p)
    page = browser.new_page()
    page.goto(EDITOR_URL)
    page.evaluate("DungeonsI18n.setLanguage('tr',false)")
    page.locator('#native-file').set_input_files(str(source))
    for name,value in {'Emeralds':1000,'SpringStone':10,'EnchantmentPoints':8,'VillageMerchantRefreshCharges':1,'EnchantsmithUpgradeLevel':2,'OldBlacksmithUpgradeLevel':2}.items():
        i = next(i for i,a in enumerate(attributes) if a['AttributeName']==name)
        field = input_path(page,['CharacterSaveV1','Ability','Attributes',i,'CurrentValue'])
        field.fill(str(value)); field.press('Tab')
        attributes[i]['CurrentValue'] = value
    page.locator('[data-native-tab="items"]').click()
    page.locator('#native-select').select_option('0')
    page.locator('#native-clone').click()
    entries = original['CharacterSaveV1']['Inventory']['Entries']
    import copy
    added = copy.deepcopy(entries[0])
    added['EquippedSlot'] = 'None'
    added['ItemData']['TargetSlotOverride'] = 'None'
    powers = added['ItemData']['GeneratorData']['PowerGeneratorValues']
    for name in ['ItemPower','ItemPowerOriginal','ItemPowerMin','ItemPowerMax']:
        powers[name] = 9
    field = input_path(page,['CharacterSaveV1','Inventory','Entries',len(entries),'ItemData','GeneratorData','PowerGeneratorValues','ItemPower'])
    field.fill('9'); field.press('Tab')
    entries.append(added)
    target = out / source.name.replace('.sav','-1000.sav')
    with page.expect_download() as d:
        page.locator('#native-export').click()
    d.value.save_as(target)
    assert json.loads(target.read_bytes()) == original
    page.screenshot(path=str(out/'Duzenleyici-1000.png'),full_page=True)
    print(f'Emeralds {before} -> 1000, SpringStone 10, EnchantmentPoints 8, refresh charges 1, smith levels 2; one new unequipped Sword power 9; {target}')
    browser.close()
