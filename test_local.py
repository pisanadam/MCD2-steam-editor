"""Read a backed-up real character and export a small change for live testing."""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL
from test_native_helpers import input_path

source, output = map(Path, sys.argv[1:3])
raw = source.read_bytes()
original = json.loads(raw)
with sync_playwright() as p:
    browser = launch_browser(p)
    page = browser.new_page(viewport={'width':1440,'height':1100})
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto(EDITOR_URL)
    page.evaluate("DungeonsI18n.setLanguage('tr',false)")
    page.locator('#native-file').set_input_files(str(source))
    with page.expect_download() as d:
        page.locator('#native-export').click()
    unchanged = output.with_suffix('.roundtrip')
    d.value.save_as(unchanged)
    assert unchanged.read_bytes() == raw
    attrs = original['CharacterSaveV1']['Ability']['Attributes']
    emerald = next(i for i,a in enumerate(attrs) if a['AttributeName']=='Emeralds')
    field = input_path(page,['CharacterSaveV1','Ability','Attributes',emerald,'CurrentValue'])
    field.fill('838'); field.press('Tab')
    page.locator('[data-native-tab="items"]').click()
    page.locator('#native-select').select_option('22')
    page.screenshot(path=str(output.with_suffix('.before.png')),full_page=True)
    field = input_path(page,['CharacterSaveV1','Inventory','Entries',22,'ItemData','GeneratorData','PowerGeneratorValues','ItemPower'])
    field.fill('6'); field.press('Tab')
    page.screenshot(path=str(output.with_suffix('.after.png')),full_page=True)
    with page.expect_download() as d:
        page.locator('#native-export').click()
    d.value.save_as(output)
    actual = json.loads(output.read_bytes())
    attrs[emerald]['CurrentValue'] = 838
    powers = original['CharacterSaveV1']['Inventory']['Entries'][22]['ItemData']['GeneratorData']['PowerGeneratorValues']
    for name in ['ItemPower','ItemPowerOriginal','ItemPowerMin','ItemPowerMax']:
        powers[name] = 6
    assert actual == original, 'Unexpected fields changed'
    assert not errors, errors
    print('Real save: byte-identical roundtrip, emerald 828 -> 838, equipped Sickles power 5 -> 6; only five numeric fields changed.')
    browser.close()
