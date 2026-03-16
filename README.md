# ☂️ Umbrella Ranked System (CS:GO)

A comprehensive, lightweight, and secure ranking system for Counter-Strike: Global Offensive servers powered by SourceMod. Built to be spam-proof, visually clean, and highly customizable.

## ✨ Key Features
* **All-in-One Tracking:** Records KDR (Kills/Deaths), Total Playtime (Hours/Days), and individual Weapon statistics.
* **Native Multi-Language:** Automatically adapts to the player's game language. Fully translated into English, Spanish, Portuguese, Russian, and Chinese.
* **Dual Database Support:** Works flawlessly out-of-the-box with local SQLite or remote MySQL setups.
* **Anti-Spam Protection:** Configurable command cooldown to prevent malicious players from lagging the server via query spamming.
* **Safe-Save Architecture:** Protected data handling to prevent stat loss during unexpected disconnects or map changes.
* **Clean UI Design:** Uses solid text formatting (`[TOP 1]`, `#2`) instead of unsupported emojis to ensure perfect menu rendering across all CS:GO clients.

## 📥 Installation
1. Download the latest release `.zip` or clone the repository.
2. Drag and drop the `addons` folder into your server's `csgo/` directory.
   * `umbrella_ranked.smx` goes into `addons/sourcemod/plugins/`
   * `umbrella_ranked.phrases.txt` goes into `addons/sourcemod/translations/`
3. Restart the server or change the map. 
4. The plugin will auto-generate its configuration file at `cfg/sourcemod/umbrella_ranked.cfg`.

## 💻 Player Commands
* `!rank` or `/rank`: View your current stats and global leaderboard position.
* `!top`: Opens the Top 50 KDR players menu.
* `!toptime`: Displays the Hall of Fame for the most active players.
* `!toparmas` or `!topweapons`: Opens the weapon selection menu to see the top killers per weapon.

## ⚙️ Configuration (CVARs)
You can tweak the following settings inside `cfg/sourcemod/umbrella_ranked.cfg` without needing to recompile the plugin:
* `sm_rank_min_kills` (Def: 1) - Minimum kills required to appear in the ranking.
* `sm_rank_top1_sound` - Sound path to play when the #1 player joins the server.
* `sm_rank_cooldown` (Def: 3.0) - Cooldown in seconds between commands (Anti-Spam).

---
*Developed by Ayrton09*
