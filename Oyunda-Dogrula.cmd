@echo off
setlocal
title Minecraft Dungeons II - Oyunda Dogrula
echo Once duzenlenmis kaydi Kaydi-Uygula.cmd ile uygulayin ve oyunu kapatin.
echo Bu yardimci Steam'de Minecraft Dungeons II oyununu acar.
echo Karakteri acip kontrol edin, ana menuye kaydedin ve oyunu kapatin.
echo Dosyalar internete yuklenmez. Kayitlar bu yardimciyla degistirilmez.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Oyunda-Dogrula.ps1"
echo.
pause
endlocal
