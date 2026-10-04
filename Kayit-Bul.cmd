@echo off
setlocal
title Minecraft Dungeons II - Kayit Bulucu
echo Minecraft Dungeons II Steam kayitlari yerel olarak aranacak.
echo Oyun kayitlarinin orijinalleri degistirilmez. Internet yuklemesi yapilmaz.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kayit-Bul.ps1"
echo.
pause
endlocal
