import json

def input_path(page,path):
    encoded=json.dumps(path,separators=(',',':'))
    fields=page.locator('[data-native-path]')
    index=fields.evaluate_all('(els,k)=>els.findIndex(e=>e.dataset.nativePath===k)',encoded)
    assert index>=0, path
    return fields.nth(index)
