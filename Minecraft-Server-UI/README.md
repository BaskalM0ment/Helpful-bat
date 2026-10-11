# Minecraft Server UI

A clean, fixed-size Windows control panel for the Fabric Minecraft server manager. The interface uses a pure-black background, minimal controls, and high-contrast status colors.

## Install and run

1. Download this folder from the repository, or clone the repository.
2. Run Start-Minecraft-Server-UI.bat.
3. The app window is set to 1200 × 850 pixels and cannot be resized or maximized.
4. By default, the UI looks for your server in %USERPROFILE%\Downloads\Minecraft server.
5. It looks for the existing manager script in this order: start-server.bat, server-manager.bat, start.bat, run.bat, or minecraft-server.bat. If your server folder is elsewhere, use Browse to select it.

The UI launches your existing manager BAT rather than replacing it, so its world-update and Playit startup steps remain in charge. The launcher hides the extra PowerShell console, leaving the control panel as the main window.

## Features

- Live server console logs with error and status highlighting
- Connected player list based on join/leave messages captured by the UI
- Session uptime and Java RAM usage
- Start, stop, and restart controls
- Editable Playit address with a copy button
- Browse for the server folder and open it in Explorer
- Fixed 1200 × 850 app window, with resizing and maximization disabled
- Built-in Windows PowerShell 5.1 and Windows Forms; no extra modules required

The player list is based on log messages seen while this UI is running. It cannot attach to a server console that was already started separately. Stop that server first before starting it from the UI.