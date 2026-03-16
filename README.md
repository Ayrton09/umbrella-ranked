# ☂️ Umbrella Ranked System (CS:GO)

A comprehensive, lightweight, and secure ranking system for Counter-Strike: Global Offensive community servers. Built to be spam-proof, visually clean, and highly customizable. It tracks KDR, total playtime, and individual weapon statistics with multi-language support.

---

## ✨ Features
* **Full Stat Tracking:** Records Kills, Deaths, KDR, Total Playtime (Hours/Days), and individual Weapon statistics.
* **Native Multi-Language:** Automatically detects and adapts to the player's game language (English, Spanish, Portuguese, Russian, Chinese).
* **Dual Database Support:** Works with local **SQLite** (standard) or remote **MySQL** (cross-server) setups.
* **Anti-Spam Protection:** Built-in command cooldowns to prevent server lag or chat flooding.
* **Optimized UI:** Clean, standardized menus and chat colors that work on all CS:GO clients.

---

## 📥 Installation

1.  **Download** the latest files.
2.  **Drag and drop** the `addons` folder into your server's `csgo/` directory.
    * `umbrella_ranked.smx` -> `addons/sourcemod/plugins/`
    * `umbrella_ranked.phrases.txt` -> `addons/sourcemod/translations/`
3.  **Restart** your server or change map. The plugin will **auto-generate** its configuration at `cfg/sourcemod/umbrella_ranked.cfg`.
---

## 🗄️ Database Setup
Add an entry named **"ranked_db"** in your `addons/sourcemod/configs/databases.cfg`.

### Option A: SQLite (Local)
```hcl
"ranked_db"
{
    "driver"            "sqlite"
    "database"          "umbrella_stats"
}

### Option B: MySQL (Remote)
```hcl
"ranked_db"
{
    "driver"            "default"
    "host"              "your-db-host"
    "database"          "your-db-name"
    "user"              "your-user"
    "pass"              "your-password"
    "port"              "3306"
}
