# ☂️ Umbrella Ranked System (CS:GO / CS:S)

| Section | Content |
|--------|--------|
| **Description** | A comprehensive, lightweight, and secure ranking system for Counter-Strike community servers. **This is a ranking system based solely on Kills and Deaths — no points, no complex elo, and no "weird things."** It's designed to be clean, fast, and easy for players to understand. |
| **Features** | ✨ **Features**<br><br>• **Full Stat Tracking:** Kills, Deaths, KDR, Total Playtime, Weapon stats<br>• **Native Multi-Language:** EN / ES / PT / RU / CH (auto-detected)<br>• **Dual Database Support:** SQLite & MySQL<br>• **Anti-Spam Protection:** Command cooldowns<br>• **Autosave System:** Prevents data loss on crashes<br>• **Fully Translation-Based:** No hardcoded text<br>• **Colored Chat:** Uses MultiColors<br>• **Cross-Game Support:** CS:GO & CS:S |
| **Installation** | 📥 **Installation**<br><br>1. Download latest files<br>2. Drag `addons` into your server folder<br>• `umbrella_ranked.smx` → `addons/sourcemod/plugins/`<br>• `umbrella_ranked.phrases.txt` → `addons/sourcemod/translations/`<br>3. Restart server or change map<br>4. Config auto-generated at:<br>`cfg/sourcemod/umbrella_ranked.cfg` |
| **Requirements** | 🧩 **Requirements**<br><br>• MultiColors → https://forums.alliedmods.net/showthread.php?t=247770 |
| **Database Setup** | 🗄️ **Database Setup**<br><br>Add `"ranked_db"` in:<br>`addons/sourcemod/configs/databases.cfg`<br><br>**MySQL**<br>```"ranked_db" { "driver" "default" "host" "your-db-host" "database" "your-db-name" "user" "your-user" "pass" "your-password" "port" "3306" }```<br><br>**SQLite**<br>```"ranked_db" { "driver" "sqlite" "database" "umbrella_stats" }``` |
| **CVars** | ⚙️ **Configurable CVars**<br><br>`sm_rank_min_kills` → 1 → Minimum kills required<br>`sm_rank_cooldown` → 3.0 → Command delay<br>`sm_rank_top1_sound` → Top #1 sound<br>`sm_rank_autosave_interval` → 120.0 → Autosave interval |
| **Commands** | 💻 **Player Commands**<br><br>• !rank / /rank → Your stats & position<br>• !top → Top 50 players<br>• !toptime → Most active players<br>• !topweapons → Weapon rankings |
| **Changelog** | 🔹 **v2.4.2**<br><br>• Added CS:S support<br>• Fixed MultiColors crash<br>• Fixed autosave timer issue<br>• Improved data saving reliability<br>• Improved name sanitization<br>• Removed hardcoded text<br>• General stability improvements |
| **Compatibility** | 💾 **Compatibility**<br><br>• No database changes required<br>• Fully backward compatible |
| **Author / Platform** | 👤 **Author:** Ayrton09<br>🛠 **Platform:** SourcePawn / SourceMod (CS:GO / CS:S) |
