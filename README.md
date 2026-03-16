☂️ Umbrella Ranked System (CS:GO)

A complete, lightweight, and secure ranking system for Counter-Strike: Global Offensive community servers. This is a ranking system based solely on Kills and Deaths — no points, no complex elo, and no "weird things." It's designed to be clean, fast, and easy for players to understand.

✨ Features

Full Stat Tracking: Records Kills, Deaths, KDR, Total Playtime, and individual Weapon statistics.

Native Multi-Language: Automatically detects and adapts to the player's game language (English, Spanish, Portuguese, Russian, and Chinese).

Dual Database Support: Works flawlessly with local SQLite or remote MySQL setups.

Anti-Spam Protection: Built-in command cooldowns to prevent server lag.

Optimized UI: Clean, standardized menus and chat colors that work on all CS:GO clients.

📥 Installation

Download the latest files and drop the addons folder into your server's csgo/ directory.

umbrella_ranked.smx -> addons/sourcemod/plugins/

umbrella_ranked.phrases.txt -> addons/sourcemod/translations/

Restart your server. The plugin will auto-generate its configuration file at cfg/sourcemod/umbrella_ranked.cfg.

🗄️ Database Setup

You must add an entry named "ranked_db" in your addons/sourcemod/configs/databases.cfg.

MySQL (Remote storage)
"ranked_db"
{
    "driver"            "default"
    "host"              "your-db-host"
    "database"          "your-db-name"
    "user"              "your-user"
    "pass"              "your-password"
    "port"              "3306"
}
SQLite (Local storage)
"ranked_db"
{
    "driver"            "sqlite"
    "database"          "umbrella_stats"
}
⚙️ Configurable CVars

Adjust these settings in cfg/sourcemod/umbrella_ranked.cfg:

CVar	Default	Description
sm_rank_min_kills	1	Minimum kills required to be ranked and saved.
sm_rank_cooldown	3.0	Seconds a player must wait between using commands.
sm_rank_top1_sound	...	Sound path to play when the Top #1 player joins.
