<div align="center">

  # `Minecraft Startup Script`
![GitHub Release](https://img.shields.io/github/v/release/GarnServo/mc-startup-script?style=for-the-badge&logo=github&labelColor=1a1a1a&color=EB5B27) &nbsp; ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/GarnServo/mc-startup-script/total?style=for-the-badge&logo=GitHub&labelColor=1a1a1a&color=EB5B27)


### A lightweight Windows launcher for Minecraft servers, with guided setup, automatic Java selection, crash recovery, Discord status updates, and safe self-updates.

</div>

## Features
1️⃣ Guided setup to ensure the server has all it needs  
2️⃣ Toggleable auto-restart   
3️⃣ Customisable JVM flags (+ RAM allocation + GUI)   
4️⃣ (Optional) Calculated JVM flags based on hardware, Java version, and RAM allocation  
5️⃣ Auto-generate EULA  
6️⃣ Automatic Java detection/selection  
7️⃣ Discord webhook integration  
8️⃣ Auto-updates with latest version from GitHub  

## Requirements
- Windows OS
- Windows PowerShell 5.1
- Java 8 or newer, depending on the Minecraft version

## How to Use
1. Download the script's [latest `START.BAT` release](https://github.com/GarnServo/mc-startup-script/releases/latest) (ensure it is saved as a '.bat').
2. Place it in your Minecraft server's root directory.
3. Run the script by either double clicking the file, or executing via CMD.
4. Upon first use, the script will automatically download `core.ps1` and run you through the configuration prompts.

The first run creates `config/StartupScript.json`. It can be edited directly for advanced options such as custom JVM flags or webhook text.

Older v1 installations using `config/StartupScript.conf` are imported automatically when v2 starts. The original file is left untouched as a backup.

To apply configuration changes while the script is still running (i.e. console is still open), simply restart the Minecraft server.  
No need to restart the script.

## Screenshots

<details>
  <summary>📸 Click to view screenshots</summary>

  #### Full Setup Wizard 
  ![Screenshot of the setup wizard](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Setup-Wizard.png)
  #### EULA Acceptance
  ![Screenshot of the EULA acceptance dialogue](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/EULA.png)
  #### Server Start-up
  ![Screenshot of the server startup text](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Server-Start.png)
  #### Server Stop
  ![Screenshot of the server stop text](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Server-Stop.png)
</details>



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

## License
[GNU GPLv3](https://choosealicense.com/licenses/gpl-3.0/)
