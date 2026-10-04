"""Use an installed Chromium browser; BROWSER_PATH can override detection."""
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EDITOR_URL = os.environ.get('EDITOR_URL', (ROOT / 'index.html').as_uri())

def launch_browser(playwright):
    override = os.environ.get('BROWSER_PATH')
    if override:
        return playwright.chromium.launch(executable_path=override, headless=True)
    if os.name == 'nt':
        return playwright.chromium.launch(channel='msedge', headless=True)
    installed = shutil.which('chromium') or shutil.which('chromium-browser')
    return playwright.chromium.launch(executable_path=installed, headless=True)
