#Requires -Version 5.1
param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$Source = $PSScriptRoot
& $Python (Join-Path $Source 'build.py')
if ($LASTEXITCODE -ne 0) { throw 'HTML build failed.' }
& $Python -m PyInstaller --noconfirm --onefile --windowed --name Dungeons-II-Forge --icon (Join-Path $Source 'assets/app/forge-icon.ico') --add-data ((Join-Path $Source 'assets/app/forge-icon.ico') + ';.') --distpath (Join-Path $Source 'dist') --workpath (Join-Path $Source 'build') --specpath (Join-Path $Source 'build') --add-data ((Join-Path $Source 'index.html') + ';.') --add-data ((Join-Path $Source 'Kaydi-Uygula.ps1') + ';.') --add-data ((Join-Path $Source 'Dogrulama-Ortak.ps1') + ';.') --collect-data webview --hidden-import webview.platforms.edgechromium --hidden-import webview.platforms.winforms (Join-Path $Source 'desktop.py')
if ($LASTEXITCODE -ne 0) { throw 'Executable build failed.' }
