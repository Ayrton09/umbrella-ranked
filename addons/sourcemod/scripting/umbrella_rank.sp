#include <sourcemod>
#include <sdktools>

// =============================================================================
// VARIABLES GLOBALES
// =============================================================================
Database g_hDatabase = null;
char g_szDriver[16];
int g_iKills[MAXPLAYERS + 1];
int g_iDeaths[MAXPLAYERS + 1];
int g_iPlayTime[MAXPLAYERS + 1];
int g_iSessionStart[MAXPLAYERS + 1];
bool g_bDataLoaded[MAXPLAYERS + 1]; 
float g_fLastCmdTime[MAXPLAYERS + 1]; // Temporizador anti-spam

ConVar g_cvDbConfig, g_cvMinKills, g_cvTop1Sound, g_cvRankEnabled, g_cvCooldown;

public Plugin myinfo = {
    name = "Umbrella Ranked System",
    author = "Ayrton09",
    description = "Sistema integral de estadísticas: KDR, Tiempo y Armas",
    version = "2.1.9",
    url = ""
};

public void OnPluginStart() {
    // Archivo de traducciones
    LoadTranslations("umbrella_ranked.phrases.txt");

    g_cvDbConfig = CreateConVar("sm_rank_db_connection", "ranked_db", "Nombre en databases.cfg");
    g_cvMinKills = CreateConVar("sm_rank_min_kills", "1", "Bajas minimas para el rank");
    g_cvTop1Sound = CreateConVar("sm_rank_top1_sound", "buttons/bell1.wav", "Sonido para el Top 1");
    g_cvRankEnabled = CreateConVar("sm_rank_enabled", "1", "1 = Activado, 0 = Desactivado");
    g_cvCooldown = CreateConVar("sm_rank_cooldown", "3.0", "Tiempo en segundos de espera entre comandos");
    
    AutoExecConfig(true, "umbrella_ranked");

    RegConsoleCmd("sm_rank", Command_Rank);
    RegConsoleCmd("sm_top", Command_Top);
    RegConsoleCmd("sm_toparmas", Command_WeaponMenu);
    RegConsoleCmd("sm_topweapons", Command_WeaponMenu);
    RegConsoleCmd("sm_toptime", Command_TopTime);
    
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");
    HookEvent("player_death", Event_PlayerDeath);

    char szDbTarget[32];
    g_cvDbConfig.GetString(szDbTarget, sizeof(szDbTarget));
    Database.Connect(SQL_OnConnect, szDbTarget);
}

// =============================================================================
// SISTEMA ANTI-SPAM
// =============================================================================
bool CheckCooldown(int client) {
    if (client == 0) return true; 
    float currentTime = GetEngineTime();
    float cooldown = g_cvCooldown.FloatValue;
    
    if (currentTime - g_fLastCmdTime[client] < cooldown) {
        float remaining = cooldown - (currentTime - g_fLastCmdTime[client]);
        CPrintToChat(client, "%t", "Cooldown Message", remaining);
        return false;
    }
    
    g_fLastCmdTime[client] = currentTime;
    return true;
}

// =============================================================================
// UTILIDADES (TIEMPO Y NORMALIZACIÓN)
// =============================================================================
void FormatPlayTime(int client, int totalSeconds, char[] buffer, int maxlen) {
    int days = totalSeconds / 86400;
    int remaining = totalSeconds % 86400;
    int hours = remaining / 3600;
    int mins = (remaining % 3600) / 60;
    if (days > 0) Format(buffer, maxlen, "%T", "Time Format Days", client, days, hours, mins);
    else Format(buffer, maxlen, "%T", "Time Format", client, hours, mins);
}

void NormalizeWeaponName(char[] weapon, int maxlen) {
    if (StrContains(weapon, "knife", false) != -1 || StrContains(weapon, "bayonet", false) != -1) strcopy(weapon, maxlen, "Knife");
    else if (StrEqual(weapon, "m4a1")) strcopy(weapon, maxlen, "M4A4");
    else if (StrEqual(weapon, "m4a1_silencer")) strcopy(weapon, maxlen, "M4A1-S");
    else if (StrEqual(weapon, "mp5sd")) strcopy(weapon, maxlen, "MP5-SD");
    else if (StrEqual(weapon, "mp7")) strcopy(weapon, maxlen, "MP7");
    else if (StrEqual(weapon, "molotov") || StrEqual(weapon, "incgrenade")) strcopy(weapon, maxlen, "Molotov/Inc");
    else if (StrEqual(weapon, "usp_silencer")) strcopy(weapon, maxlen, "USP-S");
    else if (StrEqual(weapon, "hkp2000")) strcopy(weapon, maxlen, "P2000");
    else if (StrContains(weapon, "weapon_") == 0) ReplaceString(weapon, maxlen, "weapon_", "");
}

void CPrintToChat(int client, const char[] szMessage, any ...) {
    char szBuffer[256];
    VFormat(szBuffer, sizeof(szBuffer), szMessage, 3);
    ReplaceString(szBuffer, sizeof(szBuffer), "{default}", "\x01");
    ReplaceString(szBuffer, sizeof(szBuffer), "{red}", "\x02");
    ReplaceString(szBuffer, sizeof(szBuffer), "{lightred}", "\x0F");
    ReplaceString(szBuffer, sizeof(szBuffer), "{green}", "\x04");
    ReplaceString(szBuffer, sizeof(szBuffer), "{lime}", "\x06");
    ReplaceString(szBuffer, sizeof(szBuffer), "{olive}", "\x05");
    ReplaceString(szBuffer, sizeof(szBuffer), "{blue}", "\x0C");
    ReplaceString(szBuffer, sizeof(szBuffer), "{orange}", "\x10");
    ReplaceString(szBuffer, sizeof(szBuffer), "{grey}", "\x08");

    if (client == 0) PrintToChatAll("\x01%s", szBuffer);
    else if (IsClientInGame(client)) PrintToChat(client, "\x01%s", szBuffer);
}

// =============================================================================
// BASE DE DATOS Y GUARDADO
// =============================================================================
public void SQL_OnConnect(Database db, const char[] error, any data) {
    if (db == null) { Database.Connect(SQL_OnConnectDefault, "storage-local"); return; }
    SetupDatabase(db);
}

public void SQL_OnConnectDefault(Database db, const char[] error, any data) { if (db != null) SetupDatabase(db); }

void SetupDatabase(Database db) {
    g_hDatabase = db;
    g_hDatabase.Driver.GetIdentifier(g_szDriver, sizeof(g_szDriver));
    g_hDatabase.Query(SQL_IgnoreError, "CREATE TABLE IF NOT EXISTS player_stats (steamid VARCHAR(32) PRIMARY KEY, name VARCHAR(64), kills INT DEFAULT 0, deaths INT DEFAULT 0, playtime INT DEFAULT 0)");
    g_hDatabase.Query(SQL_IgnoreError, "CREATE TABLE IF NOT EXISTS weapon_stats (steamid VARCHAR(32), weapon VARCHAR(32), kills INT DEFAULT 0, PRIMARY KEY (steamid, weapon))");
}

public void SQL_IgnoreError(Database db, DBResultSet results, const char[] error, any data) { }

void SaveClientData(int client) {
    if (g_hDatabase == null || !IsClientInGame(client) || IsFakeClient(client) || !g_bDataLoaded[client]) return;
    char auth[32], name[64], esc[128], query[512];
    if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth))) {
        GetClientName(client, name, sizeof(name)); g_hDatabase.Escape(name, esc, sizeof(esc));
        int currentTime = GetTime();
        if (g_iSessionStart[client] > 0) {
            int sessionSeconds = currentTime - g_iSessionStart[client];
            if (sessionSeconds > 0 && sessionSeconds < 86400) g_iPlayTime[client] += sessionSeconds;
        }
        g_iSessionStart[client] = currentTime;
        if (StrEqual(g_szDriver, "sqlite")) Format(query, sizeof(query), "INSERT OR REPLACE INTO player_stats VALUES ('%s', '%s', %d, %d, %d)", auth, esc, g_iKills[client], g_iDeaths[client], g_iPlayTime[client]);
        else Format(query, sizeof(query), "INSERT INTO player_stats (steamid, name, kills, deaths, playtime) VALUES ('%s', '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name='%s', kills=%d, deaths=%d, playtime=%d", auth, esc, g_iKills[client], g_iDeaths[client], g_iPlayTime[client], esc, g_iKills[client], g_iDeaths[client], g_iPlayTime[client]);
        g_hDatabase.Query(SQL_IgnoreError, query);
    }
}

// =============================================================================
// SESIÓN Y CONEXIONES
// =============================================================================
public void OnClientPostAdminCheck(int client) {
    if (IsFakeClient(client)) return;
    g_bDataLoaded[client] = false; 
    g_iKills[client] = 0; g_iDeaths[client] = 0; g_iPlayTime[client] = 0;
    g_fLastCmdTime[client] = 0.0; 
    g_iSessionStart[client] = GetTime();
    if (g_hDatabase != null) {
        char auth[32]; GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
        char query[256]; Format(query, sizeof(query), "SELECT kills, deaths, playtime FROM player_stats WHERE steamid = '%s'", auth);
        g_hDatabase.Query(SQL_OnDataLoaded, query, GetClientUserId(client));
    }
}

public void SQL_OnDataLoaded(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (client != 0 && results != null && results.FetchRow()) {
        g_iKills[client] = results.FetchInt(0); g_iDeaths[client] = results.FetchInt(1);
        g_iPlayTime[client] = results.FetchInt(2); g_bDataLoaded[client] = true;
        if (g_cvRankEnabled.BoolValue && g_iKills[client] >= g_cvMinKills.IntValue) CreateTimer(3.0, Timer_CheckWelcome, GetClientUserId(client));
    } else if (client != 0) g_bDataLoaded[client] = true;
}

public void OnClientDisconnect(int client) { if (IsClientInGame(client) && !IsFakeClient(client)) SaveClientData(client); }

// =============================================================================
// COMANDOS DE MENÚS Y TOPS
// =============================================================================
public Action Command_TopTime(int client, int args) {
    if (!CheckCooldown(client)) return Plugin_Handled; 
    if (client == 0 || g_hDatabase == null) return Plugin_Handled;
    SaveClientData(client);
    g_hDatabase.Query(SQL_OnTopTimeLoaded, "SELECT name, playtime FROM player_stats ORDER BY playtime DESC LIMIT 50", GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnTopTimeLoaded(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (client == 0 || results == null || results.RowCount == 0) return;
    Menu menu = new Menu(MH); char title[64]; Format(title, sizeof(title), "%T", "Top Time Title", client);
    menu.SetTitle(title); int p = 1;
    while (results.FetchRow()) {
        char name[64], line[128], timeStr[32]; results.FetchString(0, name, sizeof(name));
        FormatPlayTime(client, results.FetchInt(1), timeStr, sizeof(timeStr));
        if (p == 1) Format(line, sizeof(line), "%T", "Time Line First", client, name, timeStr);
        else Format(line, sizeof(line), "%T", "Time Line Rest", client, p, name, timeStr);
        menu.AddItem("", line); p++;
    }
    menu.Display(client, 30);
}

public Action Command_Top(int client, int args) {
    if (!CheckCooldown(client)) return Plugin_Handled; 
    if (!g_cvRankEnabled.BoolValue) { CPrintToChat(client, "%t", "Rank Disabled"); return Plugin_Handled; }
    if (client == 0 || g_hDatabase == null) return Plugin_Handled;
    char query[512]; Format(query, sizeof(query), "SELECT name, kills, deaths, (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) AS kdr FROM player_stats WHERE kills >= %d ORDER BY kdr DESC LIMIT 50", g_cvMinKills.IntValue);
    g_hDatabase.Query(SQL_OnTop, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnTop(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (client == 0 || results == null || results.RowCount == 0) return;
    Menu menu = new Menu(MH); char title[64]; Format(title, sizeof(title), "%T", "Top Title", client);
    menu.SetTitle(title); int p = 1;
    while (results.FetchRow()) {
        char n[64], line[128]; results.FetchString(0, n, sizeof(n));
        Format(line, sizeof(line), "#%d %s | %.2f", p++, n, results.FetchFloat(3));
        menu.AddItem("", line);
    }
    menu.Display(client, 30);
}

public Action Command_WeaponMenu(int client, int args) {
    if (!CheckCooldown(client)) return Plugin_Handled; 
    if (!g_cvRankEnabled.BoolValue) { CPrintToChat(client, "%t", "Rank Disabled"); return Plugin_Handled; }
    if (client == 0 || g_hDatabase == null) return Plugin_Handled;
    g_hDatabase.Query(SQL_OnLoadWeaponMenu, "SELECT DISTINCT weapon FROM weapon_stats ORDER BY weapon ASC", GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnLoadWeaponMenu(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (client == 0 || results == null) return;
    Menu menu = new Menu(MenuHandler_WeaponSelect); char title[64]; Format(title, sizeof(title), "%T", "Weapon Menu Title", client);
    menu.SetTitle(title);
    while (results.FetchRow()) {
        char weapon[32]; results.FetchString(0, weapon, sizeof(weapon));
        menu.AddItem(weapon, weapon);
    }
    menu.Display(client, 30);
}

public int MenuHandler_WeaponSelect(Menu menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select) {
        char weapon[32]; menu.GetItem(param2, weapon, sizeof(weapon));
        char query[512]; Format(query, sizeof(query), "SELECT p.name, w.kills FROM weapon_stats w JOIN player_stats p ON w.steamid = p.steamid WHERE w.weapon = '%s' ORDER BY w.kills DESC LIMIT 50", weapon);
        DataPack pack = new DataPack(); pack.WriteCell(GetClientUserId(param1)); pack.WriteString(weapon);
        g_hDatabase.Query(SQL_OnTopWeaponLoaded, query, pack);
    } else if (action == MenuAction_End) delete menu;
    return 0;
}

public void SQL_OnTopWeaponLoaded(Database db, DBResultSet results, const char[] error, any data) {
    DataPack pack = view_as<DataPack>(data); pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char weapon[32]; pack.ReadString(weapon, sizeof(weapon)); delete pack;
    if (client == 0 || results == null) return;
    Menu menu = new Menu(MenuHandler_TopWeapon); char title[64]; Format(title, sizeof(title), "%T", "Top Weapon Title", client, weapon);
    menu.SetTitle(title); int p = 1;
    while (results.FetchRow()) {
        char name[64], line[128]; results.FetchString(0, name, sizeof(name));
        int kills = results.FetchInt(1);
        if (p == 1) Format(line, sizeof(line), "%T", "Weapon Line First", client, name, kills);
        else Format(line, sizeof(line), "%T", "Weapon Line Rest", client, p, name, kills);
        menu.AddItem("", line); p++;
    }
    menu.ExitBackButton = true; menu.Display(client, 30);
}

public int MenuHandler_TopWeapon(Menu menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) Command_WeaponMenu(param1, 0);
    else if (action == MenuAction_End) delete menu;
    return 0;
}

// =============================================================================
// RANK INDIVIDUAL Y EVENTOS DE JUEGO
// =============================================================================
public Action Command_Rank(int client, int args) {
    if (!CheckCooldown(client)) return Plugin_Handled; 
    if (!g_cvRankEnabled.BoolValue) { CPrintToChat(client, "%t", "Rank Disabled"); return Plugin_Handled; }
    if (client == 0 || g_hDatabase == null) return Plugin_Handled;
    SaveClientData(client);
    char query[512]; Format(query, sizeof(query), "SELECT steamid FROM player_stats WHERE kills >= %d ORDER BY (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) DESC", g_cvMinKills.IntValue);
    g_hDatabase.Query(SQL_OnRankPos, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnRankPos(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (client == 0 || results == null) return;
    char auth[32]; GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    int pos = 1; bool found = false;
    while (results.FetchRow()) {
        char sid[32]; results.FetchString(0, sid, sizeof(sid));
        if (StrEqual(sid, auth)) { found = true; break; }
        pos++;
    }
    float kdr = (g_iDeaths[client] > 0) ? float(g_iKills[client]) / float(g_iDeaths[client]) : float(g_iKills[client]);
    char timeStr[32], buffer[256]; FormatPlayTime(client, g_iPlayTime[client], timeStr, sizeof(timeStr));
    if (found) Format(buffer, sizeof(buffer), "%T", "Rank Message", client, pos, g_iKills[client], g_iDeaths[client], kdr, timeStr);
    else Format(buffer, sizeof(buffer), "%T", "Not Ranked", client, g_iKills[client], g_iDeaths[client], kdr, timeStr);
    CPrintToChat(client, buffer);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvRankEnabled.BoolValue) return Plugin_Continue;
    int atk = GetClientOfUserId(event.GetInt("attacker"));
    int vic = GetClientOfUserId(event.GetInt("userid"));
    char weapon[32]; event.GetString("weapon", weapon, sizeof(weapon));
    if (atk > 0 && atk <= MaxClients && !IsFakeClient(atk) && atk != vic) {
        g_iKills[atk]++; SaveClientData(atk);
        NormalizeWeaponName(weapon, sizeof(weapon));
        char auth[32], query[512];
        if (GetClientAuthId(atk, AuthId_Steam2, auth, sizeof(auth))) {
            if (StrEqual(g_szDriver, "sqlite")) Format(query, sizeof(query), "INSERT INTO weapon_stats VALUES ('%s', '%s', 1) ON CONFLICT(steamid, weapon) DO UPDATE SET kills = kills + 1", auth, weapon);
            else Format(query, sizeof(query), "INSERT INTO weapon_stats VALUES ('%s', '%s', 1) ON DUPLICATE KEY UPDATE kills = kills + 1", auth, weapon);
            g_hDatabase.Query(SQL_IgnoreError, query);
        }
    }
    if (vic > 0 && vic <= MaxClients && !IsFakeClient(vic)) { g_iDeaths[vic]++; SaveClientData(vic); }
    return Plugin_Continue;
}

// =============================================================================
// BIENVENIDA Y COMANDOS DE CHAT
// =============================================================================
public void OnConfigsExecuted() {
    char s[128]; g_cvTop1Sound.GetString(s, sizeof(s)); 
    if (s[0] != '\0') PrecacheSound(s);
}

public Action Timer_CheckWelcome(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client != 0 && IsClientInGame(client)) CheckIfTop5(client);
    return Plugin_Stop;
}

void CheckIfTop5(int client) {
    char query[512]; Format(query, sizeof(query), "SELECT steamid FROM player_stats WHERE kills >= %d ORDER BY (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) DESC LIMIT 5", g_cvMinKills.IntValue);
    g_hDatabase.Query(SQL_OnCheckWelcome, query, GetClientUserId(client));
}

public void SQL_OnCheckWelcome(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client) || results == null) return;
    char auth[32]; GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    int pos = 1; bool isTop = false;
    while (results.FetchRow()) {
        char tsid[32]; results.FetchString(0, tsid, sizeof(tsid));
        if (StrEqual(tsid, auth)) { isTop = true; break; }
        pos++;
    }
    if (isTop) {
        char name[64], buffer[256]; GetClientName(client, name, sizeof(name));
        if (pos == 1) {
            Format(buffer, sizeof(buffer), "%T", "Top1 Announce", LANG_SERVER, name);
            CPrintToChat(0, buffer);
            char s[128]; g_cvTop1Sound.GetString(s, sizeof(s)); 
            if (s[0] != '\0') EmitSoundToAll(s);
        } else {
            Format(buffer, sizeof(buffer), "%T", "Top5 Announce", LANG_SERVER, name, pos);
            CPrintToChat(0, buffer);
        }
    }
}

public Action Command_Say(int client, const char[] command, int argc) {
    if (client == 0) return Plugin_Continue;
    char text[192]; GetCmdArgString(text, sizeof(text)); StripQuotes(text); TrimString(text);
    if (StrEqual(text, "rank", false)) { Command_Rank(client, 0); return Plugin_Handled; }
    if (StrEqual(text, "top", false)) { Command_Top(client, 0); return Plugin_Handled; }
    if (StrEqual(text, "toparmas", false) || StrEqual(text, "topweapons", false)) { Command_WeaponMenu(client, 0); return Plugin_Handled; }
    if (StrEqual(text, "toptime", false)) { Command_TopTime(client, 0); return Plugin_Handled; }
    return Plugin_Continue;
}

public int MH(Menu m, MenuAction a, int p1, int p2) { if (a == MenuAction_End) delete m; return 0; }
