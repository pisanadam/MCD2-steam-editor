"""Synthetic save test: localization changes UI, never stored game tokens."""
import importlib.util
import json
import tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright
from test_browser import launch_browser, EDITOR_URL
from test_native_helpers import input_path

ROOT=Path(__file__).resolve().parent
fixture={"SerializeMeta":{"HardFormat":"FCharacterSaveV1","SoftVersion":5,"InternalVersion":1},"CharacterSaveV1":{"MetaData":{"IsOnline":False,"CharacterId":"12345678-1234-1234-1234-123456789abc","Level":7},"Ability":{"Attributes":[{"AttributeName":"Emeralds","CurrentValue":1000}]},"Inventory":{"Entries":[{"ItemData":{"TypeTag":"SW.Item.Sword","RarityTag":"SW.Rarity.Common","Effects":[],"GeneratorData":{"PowerGeneratorValues":{"ItemPower":8}}},"StackCount":1,"EquippedSlot":"None","MerchantItemSold":False}]},"LargeNumber":90071992547409931234}}
text=json.dumps(fixture,separators=(',',':'))
with sync_playwright() as p:
    browser=launch_browser(p)
    page=browser.new_page()
    errors=[]
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.goto(EDITOR_URL)
    assert page.locator('#native-open').inner_text()=='Open game save'
    assert page.locator('#settings-open').inner_text()=='Settings'
    page.evaluate('(text)=>DungeonsNative.read(new TextEncoder().encode(text),"test.sav")',text)
    page.locator('[data-native-tab="inventory"]').click()
    page.locator('[data-inventory-item="0"]').get_by_text('Edit',exact=True).click()
    power_path=['CharacterSaveV1','Inventory','Entries',0,'ItemData','GeneratorData','PowerGeneratorValues','ItemPower']
    power=input_path(page,power_path)
    power.fill('9');power.press('Tab')
    assert json.loads(page.evaluate('DungeonsNative.getText()'))['CharacterSaveV1']['Inventory']['Entries'][0]['ItemData']['GeneratorData']['PowerGeneratorValues']['ItemPower']==9
    page.locator('#native-undo').click()
    assert page.evaluate('DungeonsNative.getText()')==text
    path=['CharacterSaveV1','Inventory','Entries',0,'ItemData','RarityTag']
    field=input_path(page,path)
    assert field.locator('option').all_text_contents()==['Common','Rare','Special','Unique','None']
    values=field.locator('option').evaluate_all('els=>els.map(e=>e.value)')
    page.locator('#settings-open').click()
    page.locator('#settings-language').select_option('tr')
    assert page.locator('#native-open').inner_text()=='Oyun kaydı aç'
    page.locator('#settings-close').click()
    assert input_path(page,path).locator('option').all_text_contents()==['Normal','Nadir','Özel','Benzersiz','Yok']
    assert input_path(page,path).locator('option').evaluate_all('els=>els.map(e=>e.value)')==values
    assert page.evaluate('DungeonsNative.getText()')==text
    page.reload()
    assert page.locator('#native-open').inner_text()=='Oyun kaydı aç'
    page.locator('#settings-open').click()
    page.locator('#settings-language').select_option('en')
    page.locator('#settings-close').click()
    page.reload()
    assert page.locator('#native-open').inner_text()=='Open game save'
    assert not errors,errors
    browser.close()

spec=importlib.util.spec_from_file_location('desktop',ROOT/'desktop.py')
desktop=importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)
with tempfile.TemporaryDirectory() as directory:
    desktop.STATE=Path(directory)
    api=desktop.Api()
    assert api.get_settings()=={'language':'en'}
    assert api.set_language('tr')=={'language':'tr'}
    assert desktop.Api().get_settings()=={'language':'tr'}
    assert 'error' in api.set_language('invalid')
    assert api.get_settings()=={'language':'tr'}
print('PASS: English default, English/Turkish settings, browser/desktop persistence and unchanged save values.')
