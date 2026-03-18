# ☂️ Umbrella Ranked System (CS:GO / CS:S)

![Version](https://img.shields.io/badge/version-2.4.2-blue)
![Game](https://img.shields.io/badge/game-CS%3AGO%20%2F%20CS%3AS-orange)
![Platform](https://img.shields.io/badge/platform-SourceMod-green)
![Language](https://img.shields.io/badge/languages-EN%20ES%20PT%20RU%20CH-purple)
![Database](https://img.shields.io/badge/database-MySQL%20%2F%20SQLite-lightgrey)

<img width="1536" height="1024" alt="css" src="https://github.com/user-attachments/assets/6715dfdc-1d65-4413-8c48-e1e4c346f31a" />

| Section | Content |
|--------|--------|
| **Description** | A comprehensive, lightweight, and secure ranking system for Counter-Strike community servers. **This is a ranking system based solely on Kills and Deaths — no points, no complex elo, and no "weird things."** It's designed to be clean, fast, and easy for players to understand. |
| **Features** | ✨ Features<br><br>• Full Stat Tracking (Kills, Deaths, KDR, Playtime, Weapons)<br>• Multi-Language (EN, ES, PT, RU, CH)<br>• SQLite & MySQL support<br>• Anti-Spam system<br>• Autosave system<br>• Fully translation-based (no hardcoded text)<br>• MultiColors chat support<br>• CS:GO & CS:S compatibility |
| **Installation** | 📥 Installation<br><br>1. Download latest release<br>2. Drag `addons` into your server folder<br>• umbrella_ranked.smx → addons/sourcemod/plugins/<br>• umbrella_ranked.phrases.txt → addons/sourcemod/translations/<br>3. Restart server or change map<br>4. Config auto-generated at:<br>`cfg/sourcemod/umbrella_ranked.cfg` |
| **Requirements** | 🧩 Requirements<br><br>MultiColors → https://forums.alliedmods.net/showthread.php?t=247770 |
| **Database Setup** | 🗄️ Database Setup<br><br>Add "ranked_db" in:<br>`addons/sourcemod/configs/databases.cfg`<br><br>MySQL:<br>`"ranked_db" { "driver" "default" "host" "your-db-host" "database" "your-db-name" "user" "your-user" "pass" "your-password" "port" "3306" }`<br><br>SQLite:<br>`"ranked_db" { "driver" "sqlite" "database" "umbrella_stats" }` |
| **CVars** | ⚙️ CVars<br><br>sm_rank_min_kills → 1<br>sm_rank_cooldown → 3.0<br>sm_rank_top1_sound → sound path<br>sm_rank_autosave_interval → 120.0 |
| **Commands** | 💻 Commands<br><br>!rank / /rank → Your stats<br>!top → Top players<br>!toptime → Most active players<br>!topweapons → Weapon rankings |
| **Changelog** | 🔹 v2.4.2<br><br>• Added CS:S support<br>• Fixed MultiColors crash<br>• Fixed autosave timer<br>• Improved data saving<br>• Improved name sanitization<br>• Removed hardcoded text<br>• General improvements |
| **Compatibility** | 💾 Compatibility<br><br>No database changes required<br>Fully backward compatible |
| **Author** | Ayrton09 — SourcePawn / SourceMod (CS:GO / CS:S) |
