"""Single-file Windows host for the offline editor; never rewrites JSON tokens."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import uuid
from datetime import datetime

ROOT = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent))
STATE = Path(os.environ['LOCALAPPDATA']) / 'DungeonsForge'
SAVE_ROOT = Path(os.environ['LOCALAPPDATA']) / 'Dungeons2' / 'Saved' / 'SaveGames'
MAX_BYTES = 20 * 1024 * 1024

def read_record(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError('Normal, en fazla 20 MB kayıt dosyası gerekli.')
    raw = path.read_bytes()
    if not raw or len(raw)>MAX_BYTES:
        raise ValueError('Kayıt boyutu 1 bayt ile 20 MB arasında olmalı.')
    doc = json.loads(raw.decode('utf-8-sig'))
    if not isinstance(doc,dict):
        raise ValueError('Karakter kaydı JSON nesnesi olmalı.')
    body = doc.get('CharacterSaveV1', {})
    if not isinstance(body,dict) or not isinstance(doc.get('SerializeMeta'),dict) or not isinstance(body.get('MetaData'),dict) or not isinstance(body.get('Ability'),dict) or not isinstance(body.get('Inventory'),dict):
        raise ValueError('Karakter alanları geçersiz.')
    if doc.get('SerializeMeta',{}).get('HardFormat') != 'FCharacterSaveV1' or body.get('MetaData',{}).get('IsOnline') is not False:
        raise ValueError('Yalnızca çevrimdışı FCharacterSaveV1 kayıtları açılabilir.')
    if not isinstance(body.get('Ability',{}).get('Attributes'),list) or not isinstance(body.get('Inventory',{}).get('Entries'),list):
        raise ValueError('Karakter alanları geçersiz.')
    for entry in body['Ability']['Attributes']:
        if not isinstance(entry,dict) or not isinstance(entry.get('AttributeName'),str) or type(entry.get('CurrentValue')) not in (int,float):
            raise ValueError('Karakter kaynak alanları geçersiz.')
    for entry in body['Inventory']['Entries']:
        if not isinstance(entry,dict) or not isinstance(entry.get('ItemData'),dict) or not isinstance(entry['ItemData'].get('TypeTag'),str):
            raise ValueError('Envanter eşya alanları geçersiz.')
    if not isinstance(body['MetaData'].get('CharacterId'),str) or uuid.UUID(body['MetaData']['CharacterId']).int==0:
        raise ValueError('Geçerli karakter kimliği gerekli.')
    return raw, doc

class Api:
    def __init__(self):
        self._window = None
        self._source = None
        self._loaded_hash = None
        self._lock = threading.Lock()
        self._settings_lock = threading.Lock()

    def get_settings(self):
        try:
            data=json.loads((STATE/'settings.json').read_text(encoding='utf-8'))
            language=data.get('language','en') if isinstance(data,dict) else 'en'
            return {'language':language if language in ('en','tr') else 'en'}
        except (OSError,ValueError):
            return {'language':'en'}

    def set_language(self, language):
        if language not in ('en','tr'):
            return {'error':'Unsupported language.'}
        try:
            with self._settings_lock:
                STATE.mkdir(parents=True,exist_ok=True)
                with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=STATE,prefix='settings-',suffix='.tmp',delete=False) as output:
                    temporary=Path(output.name)
                    json.dump({'language':language},output)
                try:
                    os.replace(temporary,STATE/'settings.json')
                finally:
                    temporary.unlink(missing_ok=True)
            if self._window:
                self._window.set_title('Dungeons II Forge — Steam Kayıt Düzenleyici' if language=='tr' else 'Dungeons II Forge — Steam Save Editor')
            return {'language':language}
        except OSError as error:
            return {'error':str(error)}

    def list_saves(self):
        rows=[]
        for path in SAVE_ROOT.glob('Character*.sav'):
            try:
                raw,doc = read_record(path)
                body=doc['CharacterSaveV1']
                attrs={a['AttributeName']:a['CurrentValue'] for a in body['Ability']['Attributes']}
                rows.append({'path':str(path),'name':path.name,'level':body['MetaData'].get('Level'), 'emeralds':attrs.get('Emeralds',0),'items':len(body['Inventory']['Entries'])})
            except (ValueError,KeyError,OSError,TypeError):
                continue
        return rows

    def open_save(self, path=None):
        if not self._lock.acquire(blocking=False):
            return {'error':'Kayıt işlemi devam ediyor.'}
        try:
            if path is None:
                import webview
                selected=self._window.create_file_dialog(webview.FileDialog.OPEN,directory=str(SAVE_ROOT),file_types=(('Karakter kaydı (*.sav)' if self.get_settings()['language']=='tr' else 'Character save (*.sav)'),))
                if not selected:
                    return {'cancelled':True}
                path=selected[0]
            elif str(Path(path)) not in [row['path'] for row in self.list_saves()]:
                raise ValueError('Steam karakter listesinde bulunan kaydı seçin.')
            source=Path(path).resolve()
            raw,doc=read_record(source)
            character=doc['CharacterSaveV1']['MetaData']['CharacterId']
            target=SAVE_ROOT / ('Character'+character+'.sav')
            backup_dir=STATE/'Backups'/(datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])
            backup_dir.mkdir(parents=True)
            backup=backup_dir/source.name
            backup.write_bytes(raw)
            digest=hashlib.sha256(raw).hexdigest()
            if hashlib.sha256(backup.read_bytes()).hexdigest()!=digest:
                raise ValueError('Yedek doğrulanamadı.')
            (backup_dir/'SHA256.txt').write_text(digest+'  '+source.name+'\n',encoding='utf-8')
            self._source=target if target.exists() else None
            self._loaded_hash=digest
            return {'data':base64.b64encode(raw).decode('ascii'),'name':source.name,'backup':str(backup), 'can_apply':self._source is not None}
        except Exception as error:
            return {'error':str(error)}
        finally:
            self._lock.release()

    def save_file(self, data, name):
        try:
            import webview
            raw=base64.b64decode(data,validate=True)
            if len(raw)>MAX_BYTES:
                raise ValueError('Kayıt en fazla 20 MB olmalı.')
            selected=self._window.create_file_dialog(webview.FileDialog.SAVE,save_filename=Path(name).name,file_types=(('Kayıt dosyası (*.*)' if self.get_settings()['language']=='tr' else 'Save file (*.*)'),))
            if not selected:
                return {'cancelled':True}
            destination=Path(selected[0]).resolve()
            # All game-folder writes must go through the guarded apply path.
            if destination.is_relative_to(SAVE_ROOT.resolve()):
                raise ValueError('Oyun klasörüne yazmak için Kaydı oyuna uygula düğmesini kullanın.')
            destination.write_bytes(raw)
            return {'path':str(destination)}
        except Exception as error:
            return {'error':str(error)}

    def apply_save(self, data):
        if not self._lock.acquire(blocking=False):
            return {'error':'Kayıt işlemi devam ediyor.'}
        try:
            if self._source is None or self._loaded_hash is None:
                raise ValueError('Önce bu bilgisayardaki Steam karakterini açın.')
            if hashlib.sha256(self._source.read_bytes()).hexdigest()!=self._loaded_hash:
                raise ValueError('Oyun kaydı değişti. Güncel kaydı yeniden açın; ilerlemeniz korunuyor.')
            raw=base64.b64decode(data,validate=True)
            if len(raw)>MAX_BYTES:
                raise ValueError('Kayıt en fazla 20 MB olmalı.')
            with tempfile.TemporaryDirectory(prefix='DungeonsForge-') as temp:
                edited=Path(temp)/'Character-duzenlenmis.sav'
                edited.write_bytes(raw)
                ps=Path(os.environ['SYSTEMROOT'])/'System32'/'WindowsPowerShell'/'v1.0'/'powershell.exe'
                result=subprocess.run([str(ps),'-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'Kaydi-Uygula.ps1'),'-EditedPath',str(edited),'-SourcePath',str(self._source),'-ExpectedSourceHash',self._loaded_hash,'-NoUI'],capture_output=True,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
            if result.returncode!=0:
                # Console output can be localized; decode using the Windows OEM page.
                message=(result.stdout+result.stderr).decode('oem',errors='replace').strip()
                raise ValueError(message or 'Kayıt uygulanamadı. Oyunun kapalı olduğunu kontrol edin.')
            if hashlib.sha256(self._source.read_bytes()).hexdigest()!=hashlib.sha256(raw).hexdigest():
                raise ValueError('Uygulanan dosya doğrulanamadı.')
            self._loaded_hash=hashlib.sha256(raw).hexdigest()
            backups=sorted(self._source.parent.glob(self._source.name+'.*.bak'),key=lambda p:p.stat().st_mtime)
            return {'ok':True,'backup':str(backups[-1]) if backups else None,'message':'Kayıt yedek alınarak oyuna uygulandı. Oyunu açıp aynı çevrimdışı karakteri yükleyin.'}
        except Exception as error:
            return {'error':str(error)}
        finally:
            self._lock.release()

    def launch_game(self):
        try:
            os.startfile('steam://rungameid/1912410')
            return {'ok':True}
        except Exception as error:
            return {'error':str(error)}

def main():
    if '--self-test' in sys.argv:
        index=sys.argv.index('--self-test')
        report={'resources':{name:(ROOT/name).is_file() for name in ['index.html','Kaydi-Uygula.ps1','Dogrulama-Ortak.ps1']},'characters':Api().list_saves()}
        Path(sys.argv[index+1]).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        return
    import webview
    api=Api()
    title='Dungeons II Forge — Steam Kayıt Düzenleyici' if api.get_settings()['language']=='tr' else 'Dungeons II Forge — Steam Save Editor'
    api._window=webview.create_window(title,url=(ROOT/'index.html').as_uri(),js_api=api,width=1380,height=920,min_size=(850,620),background_color='#111716')
    webview.start(gui='edgechromium',private_mode=True,icon=str(ROOT/'forge-icon.ico' if (ROOT/'forge-icon.ico').is_file() else ROOT/'assets/app/forge-icon.ico'))

if __name__=='__main__':
    try:
        main()
    except Exception as error:
        import ctypes
        ctypes.windll.user32.MessageBoxW(None,str(error),'Dungeons II Forge açılmadı',0x10)
