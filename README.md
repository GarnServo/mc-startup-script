# Minecraft Startup Script

A fully-customisable, modular .bat startup script for Minecraft servers, where all variables can be modified on the fly and applied upon server restart.

## Features
1️⃣ Toggleable auto-restart  
2️⃣ Customisable JVM arguments/flags - including optional optimised preset  
3️⃣ Customisable RAM allocation  
4️⃣ Auto-generate+accept EULA  
5️⃣ GUI toggle  
6️⃣ Customisable console title  

## Requirements
- Windows OS
- Java 17

## How to Use
1. Download the script's latest release (ensure it is saved as a '.bat').
2. Place it in your Minecraft server's root directory.
3. Run the script by either double clicking the file, or executing via CMD.
4. Upon first use, the script will run you through the configuration prompts.

To edit configurations:  
JVM arguments = /config/jvm_args.txt  
Script config = /config/StartupScript.conf  

To apply configuration changes while the script is still running (i.e. console is still open), simply restart the Minecraft server.  
No need to restart the script.

## Screenshots

![Configuration Screenshot](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Config.png)

![Console Screenshot](https://raw.githubusercontent.com/GarnServo/mc-startup-script/main/imgs/Console_launch.png)

## Disclaimer
By using this script, you are indicating your agreement to the [Minecraft EULA](https://aka.ms/MinecraftEULA).

## License
[GNU GPLv3](https://choosealicense.com/licenses/gpl-3.0/)
