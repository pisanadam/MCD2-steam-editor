# Dungeons II Forge — Steam Save Editor

A local Windows editor for **Minecraft Dungeons II offline Steam characters**. English is the default language. Open **Settings → Language → Türkçe** to switch to Turkish. The desktop app remembers this choice between launches.

## Download and use

[Download the single-file Windows EXE](https://github.com/pisanadam/MCD2-steam-editor/raw/refs/heads/main/download/Dungeons-II-Forge.exe).

1. Close Minecraft Dungeons II and run `Dungeons-II-Forge.exe`.
2. Choose **Find Steam saves** and select your offline character. A verified original backup is created automatically.
3. Edit resources, item power, rarity, quantities or enchantments. Use **Inventory overview** to browse the items in your save.
4. Select **Apply save to game** while the game is closed.
5. Select **Launch game** and load the same offline character to check your changes.

No Python installation or separate CMD files are needed for the EXE. Microsoft Edge WebView2 Runtime is required. The bundled icons and editor work offline; save files are not uploaded.

## Features

- English / Turkish UI, including validation messages and icon pickers.
- Steam save discovery, automatic SHA256-verified backups and guarded application to the matching character.
- Emeralds, echo shards, enchantment points, level, XP and existing merchant attributes.
- Inventory cards with icons, rarity, power, quantity and equipped status; search and equipment/bag/sold filters.
- Item selection with small icons. **Add item** creates a new unequipped copy of an item already present in the loaded save; edit the copy afterward.
- Rarity and equipment slots use named dropdowns; game codes are hidden by default.
- Add or replace a compatible enchantment, choose its verified tier, or remove it while preserving other effects. Talisman tier changes also update their saved effects.
- Item duplication/deletion and undo of the last 20 edits.
- Inline warnings for invalid values; correct invalid fields before exporting or applying the save.
- JSON token patching preserves unknown fields, large 64-bit numbers and original file bytes when no edits are made.

## Save protection

Only plain UTF-8 JSON `FCharacterSaveV1` saves with `IsOnline=false` are supported. Online characters, GVAS and encrypted saves are not supported. Character identity and format metadata are protected. Application is refused if the game is running or the source save changed since opening it. The editor verifies a backup before replacing the target file with the edited bytes.

Steam save folder:

```text
%LOCALAPPDATA%\Dungeons2\Saved\SaveGames\Character<id>.sav
```

Desktop backups and language preference:

```text
%LOCALAPPDATA%\DungeonsForge\Backups
%LOCALAPPDATA%\DungeonsForge\settings.json
```

**Applying a save does not prove every edit works in the game.** Load the character and check the changes. The game can recalculate power or reject unsupported item combinations. An arbitrary high power value does not guarantee unlimited damage.

## Run from source

On Windows with Python 3.12:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python build.py
.venv\Scripts\python desktop.py
```

You can also open `index.html` in a browser to edit a separate save copy. Automatic discovery and direct application are desktop features. The supplied CMD/PowerShell helpers provide a separate manual workflow.

## Build a single-file EXE

```powershell
.venv\Scripts\python -m pip install -r requirements-dev.txt
.\build-exe.ps1 -Python .\.venv\Scripts\python.exe
```

The result is `dist\Dungeons-II-Forge.exe`.

## Tests

```powershell
python test_native.py
python test_icons.py
python test_languages.py
python test_enchantments.py
python test_progression.py
powershell -NoProfile -ExecutionPolicy Bypass -File test_process_detection.ps1
```

Browser tests use installed Edge on Windows. Set `BROWSER_PATH` for another Chromium executable. The native and language tests use synthetic saves. Changing language must not change save tokens or dropdown values.

A previous live test confirmed edited currencies and a copied item in a local Steam character. UI and preservation tests cover the documented scenarios; they do not validate every possible item/enchantment combination or measure combat damage.

## Icons and attribution

The package includes 440 original game images. `assets/icon-manifest.json` records source URLs, sizes and SHA256 hashes. Unmapped IDs never receive substitute artwork. Sources include [Dungeons Tools](https://www.dungeons.tools/) and the community sources recorded in the manifest.

Game images belong to Mojang/Microsoft and their respective rights holders. This is an independent community tool, not an official Mojang, Microsoft or Valve product. No rights to the game artwork are granted by this repository.

## Türkçe

Program ilk açılışta İngilizcedir. **Settings → Language → Türkçe** seçeneğiyle Türkçe yapabilirsiniz; seçim sonraki açılışta korunur. **Steam kaydını bul** ile karakteri açın, düzenleyin, oyun kapalıyken **Kaydı oyuna uygula** düğmesine basın. Önce otomatik yedek alınır. **Envanter görünümü** bütün eşyaları gösterir; **Eşya ekle** mevcut bir eşyadan kuşanılmamış kopya ekler.

Enchantment slot/tier data and the documented save schema were checked against [Tonystukl/MCD2SaveEdit](https://github.com/Tonystukl/MCD2SaveEdit). Its MIT notice is included in `third-party/MCD2SaveEdit-LICENSE.txt`.
