# ☂️ Umbrella Ranked System (CS:GO)

A complete, lightweight, and secure ranking system for Counter-Strike: Global Offensive community servers. Built to be spam-proof, visually clean, and highly customizable.

## ✨ Features
* **Comprehensive Stats:** Records Kills, Deaths, KDR, Total Playtime (Hours/Days), and individual Weapon statistics.
* **Native Multi-Language:** Automatically detects and adapts to the player's game language. Supports English, Spanish, Portuguese, Russian, and Chinese.
* **Dual Database Support:** Works flawlessly with local **SQLite** or remote **MySQL** setups.
* **Anti-Spam Protection:** Built-in command cooldown to prevent server lag from malicious usage.
* **Safe-Save:** Data is protected against loss during unexpected disconnects or map changes.

---

## 📥 Installation

1.  Download the latest files.
2.  Drop the `addons` folder into your server's `csgo/` directory.
    * `umbrella_ranked.smx` -> `addons/sourcemod/plugins/`
    * `umbrella_ranked.phrases.txt` -> `addons/sourcemod/translations/`
3.  Restart your server or change the map.
4.  The plugin will auto-generate its configuration file at `cfg/sourcemod/umbrella_ranked.cfg`.

---

## 🗄️ Database Setup
You must add an entry named **"ranked_db"** in your `addons/sourcemod/configs/databases.cfg`.

### Option A: SQLite (Local)
```hcl
"ranked_db"
{
    "driver"            "sqlite"
    "database"          "umbrella_stats"
}
