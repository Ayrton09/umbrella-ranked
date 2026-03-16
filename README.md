# ☂️ Umbrella Ranked System (CS:GO)

A comprehensive, lightweight, and secure ranking system for Counter-Strike: Global Offensive community servers. Built to be spam-proof, visually clean, and highly customizable. It handles everything from KDR to playtime and weapon-specific statistics.

---

## ✨ Features
* **Full Stat Tracking:** Records Kills, Deaths, KDR, Total Playtime (Hours/Days), and individual Weapon statistics.
* **Native Multi-Language:** Automatically detects and adapts to the player's game language. 
  * *Supported: English, Spanish, Portuguese, Russian, and Chinese.*
* **Dual Database Support:** Works flawlessly with local **SQLite** (standard) or remote **MySQL** (cross-server) setups.
* **Anti-Spam Protection:** Built-in command cooldowns to prevent server lag or chat flooding.
* **Optimized UI:** Uses clean, standardized menus and chat colors that work on all CS:GO clients.

---

## 📥 Installation

1.  **Download** the latest files from the [Releases](https://github.com/Ayrton09/umbrella-ranked/releases) section.
2.  **Drag and drop** the `addons` folder into your server's `csgo/` directory.
    * `umbrella_ranked.smx` goes to `addons/sourcemod/plugins/`
    * `umbrella_ranked.phrases.txt` goes to `addons/sourcemod/translations/`
3.  **Restart** your server or change the map.
4.  The plugin will **auto-generate** its configuration file at `cfg/sourcemod/umbrella_ranked.cfg`.

---

## 🗄️ Database Setup
You **MUST** add an entry named **"ranked_db"** in your `addons/sourcemod/configs/databases.cfg`.

### Option A: SQLite (Local storage - Recommended for single servers)
```hcl
"ranked_db"
{
    "driver"            "sqlite"
    "database"          "umbrella_stats"
}
