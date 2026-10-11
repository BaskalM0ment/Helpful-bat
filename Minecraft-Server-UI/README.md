# Minecraft Server UI

A dark Windows control panel for the Fabric Minecraft server manager. It shows live console logs, players detected from join/leave messages, session time, Java RAM usage, and the Playit address.

## Install and run

1. Download this folder from the repository, or clone the repository.
2. Run Start-Minecraft-Server-UI.bat.
3. By default, the UI looks for your server in %USERPROFILE%\Downloads\Minecraft server.
4. It looks for the existing manager script in this order: start-server.bat, server-manager.bat, start.bat, run.bat. If your server folder is elsewhere, use Browse to select it.

The UI launches your existing manager BAT rather than replacing it, so its world-update and Playit startup steps remain in charge. Start the server through this UI if you want the live logs and player list.

## Controls

- Start Server launches the existing manager BAT.
- Stop Server sends the command "stop" to the Minecraft console. If the manager then asks whether to restart, the UI chooses exit.
- Restart sends "stop" and answers "R" at the manager's restart prompt.
- Copy Address copies the editable Playit address.
- Open Folder opens the selected server directory.

The player list is based on join/leave messages seen while this UI is running. It cannot attach to a server console that was already started separately. Stop that server first before starting it from the UI.

## Requirements

- Windows 10 or Windows 11
- Built-in Windows PowerShell 5.1 and Windows Forms
- Your existing Minecraft server manager BAT and server files

No extra PowerShell modules are required.