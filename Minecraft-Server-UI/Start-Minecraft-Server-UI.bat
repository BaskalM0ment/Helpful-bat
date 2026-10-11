@echo off
setlocal
title Minecraft Server Control Panel
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Minecraft-Server-UI.ps1"
if errorlevel 1 (
    echo.
    echo Minecraft Server UI exited with an error.
    pause
)
endlocal