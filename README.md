# ☂️ Umbrella Ranked System (CS:GO / CS:S)

![Version](https://img.shields.io/badge/version-2.4.2-blue)
![Game](https://img.shields.io/badge/game-CS%3AGO%20%2F%20CS%3AS-orange)
![Platform](https://img.shields.io/badge/platform-SourceMod-green)
![Language](https://img.shields.io/badge/languages-EN%20ES%20PT%20RU%20CH-purple)
![Database](https://img.shields.io/badge/database-MySQL%20%2F%20SQLite-lightgrey)

<img width="1536" height="1024" alt="css" src="https://github.com/user-attachments/assets/6715dfdc-1d65-4413-8c48-e1e4c346f31a" />

A comprehensive, lightweight, and secure ranking system for Counter-Strike community servers.

---

## ✨ Features
- Kills, Deaths, KDR, Playtime, Weapon stats  
- Multi-language (EN / ES / PT / RU / CH)  
- SQLite & MySQL support  
- Anti-spam system  
- Autosave system  
- MultiColors chat  
- CS:GO & CS:S compatible  

---

## 📥 Installation

<details>
<summary>Click to expand</summary>

1. Download the latest files  
2. Place files:
   - `addons/sourcemod/plugins/umbrella_ranked.smx`
   - `addons/sourcemod/translations/umbrella_ranked.phrases.txt`
3. Restart server or change map  
4. Config auto-generated at: `cfg/sourcemod/umbrella_ranked.cfg`

</details>

---

## 🗄️ Database Setup

<details>
<summary>Click to expand</summary>

Add `"ranked_db"` in: `addons/sourcemod/configs/databases.cfg`

### MySQL

```cfg
"ranked_db"
{
    "driver"    "default"
    "host"      "your-db-host"
    "database"  "your-db-name"
    "user"      "your-user"
    "pass"      "your-password"
    "port"      "3306"
}

SQLite
"ranked_db"
{
    "driver"    "sqlite"
    "database"  "umbrella_stats"
}
</details>
⚙️ CVars
<details> <summary>Click to expand</summary>
CVar	Default	Description
sm_rank_min_kills	1	Minimum kills required
sm_rank_cooldown	3.0	Command delay
sm_rank_top1_sound	...	Top #1 sound
sm_rank_autosave_interval	120.0	Autosave interval
</details>
💻 Commands
<details> <summary>Click to expand</summary>

!rank → Your stats

!top → Top players

!toptime → Most active players

!topweapons → Weapon rankings

</details>

👤 Author

Ayrton09
SourcePawn / SourceMod (CS:GO / CS:S)




