<div align="center">

  # `Minecraft Startup Script`
![GitHub Release](https://img.shields.io/github/v/release/GarnServo/mc-startup-script?style=for-the-badge&logo=github&labelColor=1a1a1a&color=EB5B27)

### A lightweight Windows launcher for Minecraft servers, with guided setup, automatic Java selection, crash recovery, Discord status updates, and safe self-updates.

</div>

## Features
1️⃣ Toggleable auto-restart  
2️⃣ Customisable JVM arguments/flags - including optional optimised preset  
3️⃣ Customisable RAM allocation  
4️⃣ Auto-generate+accept EULA  
5️⃣ GUI toggle  
6️⃣ Customisable console title  
7️⃣ Discord webhook integration  
8️⃣ Auto-updates with latest version from GitHub

## Requirements
- Windows OS
- Windows PowerShell 5.1
- Java 8 or newer, depending on the Minecraft version

## How to Use
1. Download the script's [latest release](https://github.com/GarnServo/mc-startup-script/releases/latest) (ensure it is saved as a '.bat').
2. Place it in your Minecraft server's root directory.
3. Run the script by either double clicking the file, or executing via CMD.
4. Upon first use, the script will run you through the configuration prompts.

The first run creates `config/StartupScript.json`. It can be edited directly for advanced options such as custom JVM flags or webhook text.

Older v1 installations using `config/StartupScript.conf` are imported automatically when v2 starts. The original file is left untouched as a backup.

To apply configuration changes while the script is still running (i.e. console is still open), simply restart the Minecraft server.  
No need to restart the script.

## Screenshots

![Configuration Screenshot](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Config.png)

![Console Screenshot](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Console_launch.png)

## Functionality
### First Launch/Initial Setup
- [X] Prompts user for server .jar filename. Checks if the file exists.
- [X] Prompts user to allocate initial and maximum RAM for the server. Checks if entry is a valid value. 
- [X] Queries user whether the server should auto-restart or not.
- [X] Queries user whether server should use pre-configured JVM arguments. Regardless of result, will generate file for flag storage.
- [X] Queries user whether to launch with GUI.
- [X] Queries user whether to use Discord webhooks. If yes, user inputs webhook URL.
- [X] Lets user confirm choices. If confirmed, continue to normal startup. If rejected, will restart initial configuration.
- [X] Stores configuration in `/config/StartupScript.json`.
- [X] Generates auto-accepted EULA.
### Normal Startup
- [X] Checks for updates to this script.
- [X] Checks for config folder, config file, and sets restart counter. If config is missing, reverts back to initial setup.
- [X] Checks for EULA, if non-existent, creates accepted eula.txt.
- [X] Reads the JSON configuration and validates the selected Java runtime.
- [X] Displays configuration to user and initialises the server.
- [X] Uses built-in JVM defaults, with an optional `jvmFlags` override in the JSON configuration.
- [X] Checks auto-restart config to decide launch path.
#### Auto-Restart Enabled
- [X] Launches server, changes console title to the configurable title + restart count, and (if configured) sends Discord message.
- [X] Upon crash or restart, increments the restart counter, reloads configuration + JVM flags, and (if configured) sends Discord message.
#### Auto-Restart Disabled
- [X] Launches server and changes console title to the configurable title, and (if configured) sends Discord message.
- [X] Upon crash or restart, prompts user whether to restart or exit, and (if configured) sends Discord message.  

### Planned
- [ ] Improve text formatting
- [ ] Update server .jar to latest, within Minecraft version.  
_e.g. paper 1.20.4 build 460 > paper 1.20.4 > build 461_

## Disclaimer
By using this script, you are indicating your agreement to the [Minecraft EULA](https://aka.ms/MinecraftEULA).

## License
[GNU GPLv3](https://choosealicense.com/licenses/gpl-3.0/)
