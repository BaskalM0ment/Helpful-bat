@echo off
setlocal
title Minecraft Server Control Panel
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Minecraft-Server-UI.ps1"
if errorlevel 1 (
    powershell.exe -NoLogo -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Minecraft Server UI exited with an error. Check that Windows PowerShell and Windows Forms are available.', 'Minecraft Server UI', 'OK', 'Error')"
)
endlocal