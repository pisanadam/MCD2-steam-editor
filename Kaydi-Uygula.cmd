@echo off
setlocal
title Minecraft Dungeons II - Duzenlenmis Kaydi Uygula
echo Oyunu tamamen kapatin. Indirilen -duzenlenmis.sav dosyasini secin.
echo Eslesen karakter kaydi, dogrulanmis yedegi alindiktan sonra uygulanir.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kaydi-Uygula.ps1"
echo.
pause
endlocal
