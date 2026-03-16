# ☂️ Umbrella Ranked System (CS:GO)

A comprehensive, lightweight, and secure ranking system for Counter-Strike: Global Offensive community servers. **This is a ranking system based solely on Kills and Deaths — no points, no complex elo, and no "weird things."** It's designed to be clean, fast, and easy for players to understand.

---

## ✨ Features
* **Full Stat Tracking:** Records Kills, Deaths, KDR, Total Playtime (Hours/Days), and individual Weapon statistics.
* **Native Multi-Language:** Automatically detects and adapts to the player's game language (English, Spanish, Portuguese, Russian, and Chinese).
* **Dual Database Support:** Works flawlessly with local SQLite or remote MySQL setups.
* **Anti-Spam Protection:** Built-in command cooldowns to prevent server lag or chat flooding.

---

## 📥 Installation
1. **Download** the latest files from the repository.
2. **Drag and drop** the `addons` folder into your server's `csgo/` directory.
   * `umbrella_ranked.smx` -> `addons/sourcemod/plugins/`
   * `umbrella_ranked.phrases.txt` -> `addons/sourcemod/translations/`
3. **Restart** your server or change the map. 
4. The plugin will **auto-generate** its configuration file at `cfg/sourcemod/umbrella_ranked.cfg`.

---

## 🗄️ Database Setup
You must add an entry named **"ranked_db"** in your `addons/sourcemod/configs/databases.cfg`.

### MySQL (Remote storage)
```
"ranked_db"
{
"driver"            "default"
"host"              "your-db-host"
"database"          "your-db-name"
"user"              "your-user"
"pass"              "your-password"
"port"              "3306"
}
```

### SQLite (Local storage)
```
"ranked_db"
{
"driver"            "sqlite"
"database"          "umbrella_stats"
}

## ⚙️ Configurable CVars
Adjust these settings in `cfg/sourcemod/umbrella_ranked.cfg`:

| CVar | Default | Description |
| :--- | :--- | :--- |
| `sm_rank_min_kills` | 1 | Minimum kills required to be ranked and saved. |
| `sm_rank_cooldown` | 3.0 | Seconds a player must wait between using commands. |
| `sm_rank_top1_sound` | ... | Sound path to play when the Top #1 player joins. |

---

## 💻 Player Commands
* **!rank** or **/rank**: View your personal stats and global leaderboard position.
* **!top**: Opens the Top 50 KDR leaderboard.
* **!toptime**: Displays the "Hall of Fame" for the most active players.
* **!topweapons**: Shows rankings for each individual weapon.

---

**Author:** Ayrton09
**Platform:** SourcePawn / SourceMod (CS:GO)
