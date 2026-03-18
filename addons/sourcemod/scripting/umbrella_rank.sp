#include <sourcemod>
#include <sdktools>
#include <multicolors>

// =============================================================================
// VARIABLES GLOBALES
// =============================================================================
EngineVersion g_GameEngine;
Database g_hDatabase = null;
char g_szDriver[16];

int g_iKills[MAXPLAYERS + 1];
int g_iDeaths[MAXPLAYERS + 1];
int g_iPlayTime[MAXPLAYERS + 1];
int g_iSessionStart[MAXPLAYERS + 1];

bool g_bDataLoaded[MAXPLAYERS + 1];
bool g_bSaveDirty[MAXPLAYERS + 1];

float g_fLastCmdTime[MAXPLAYERS + 1];

ConVar g_cvDbConfig;
ConVar g_cvMinKills;
ConVar g_cvTop1Sound;
ConVar g_cvRankEnabled;
ConVar g_cvCooldown;
ConVar g_cvAutoSave;

Handle g_hAutoSaveTimer = null;

public Plugin myinfo =
{
    name = "Umbrella Ranked System",
    author = "Ayrton09",
    description = "Ranking System: KDR, Time & Weapons (CS:GO/CS:S)",
    version = "2.4.2",
    url = ""
};

// =============================================================================
// INICIO / FIN
// =============================================================================
public void OnPluginStart()
{
    g_GameEngine = GetEngineVersion();
    if (g_GameEngine != Engine_CSGO && g_GameEngine != Engine_CSS)
    {
        SetFailState("Este plugin solo soporta CS:GO y CS:S.");
    }

    LoadTranslations("umbrella_ranked.phrases.txt");

    g_cvDbConfig    = CreateConVar("sm_rank_db_connection", "ranked_db", "Name of the connection in databases.cfg.");
    g_cvMinKills    = CreateConVar("sm_rank_min_kills", "50", "Minimum kills required for a player to be ranked.", _, true, 0.0);
    g_cvTop1Sound   = CreateConVar("sm_rank_top1_sound", "buttons/bell1.wav", "Sound path for Top #1 join.");
    g_cvRankEnabled = CreateConVar("sm_rank_enabled", "1", "1 = Enabled, 0 = Disabled.", _, true, 0.0, true, 1.0);
    g_cvCooldown    = CreateConVar("sm_rank_cooldown", "3.0", "Seconds to wait between commands.", _, true, 0.0);
    g_cvAutoSave    = CreateConVar("sm_rank_autosave_interval", "120.0", "Seconds between autosaves. 0 = disabled.", _, true, 0.0);

    g_cvAutoSave.AddChangeHook(OnAutoSaveCvarChanged);

    AutoExecConfig(true, "umbrella_ranked");

    RegConsoleCmd("sm_rank", Command_Rank);
    RegConsoleCmd("sm_top", Command_Top);
    RegConsoleCmd("sm_toparmas", Command_WeaponMenu);
    RegConsoleCmd("sm_topweapons", Command_WeaponMenu);
    RegConsoleCmd("sm_toptime", Command_TopTime);

    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    HookEvent("player_death", Event_PlayerDeath);

    StartAutoSaveTimer();
    ConnectDatabase();
}

public void OnConfigsExecuted()
{
    PrecacheTop1Sound();
    StartAutoSaveTimer();
}

public void OnMapStart()
{
    PrecacheTop1Sound();
}

public void OnMapEnd()
{
    SaveAllClientsData(true);
}

public void OnPluginEnd()
{
    SaveAllClientsData(true);
    g_hAutoSaveTimer = null;
}

// =============================================================================
// UTILIDADES Y SISTEMA ANTI-SPAM
// =============================================================================
void ResetClientData(int client)
{
    g_iKills[client] = 0;
    g_iDeaths[client] = 0;
    g_iPlayTime[client] = 0;
    g_iSessionStart[client] = GetTime();

    g_bDataLoaded[client] = false;
    g_bSaveDirty[client] = false;
    g_fLastCmdTime[client] = 0.0;
}

bool CheckCooldown(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return true;
    }

    float currentTime = GetEngineTime();
    float cooldown = g_cvCooldown.FloatValue;
    float elapsed = currentTime - g_fLastCmdTime[client];

    if (elapsed < cooldown)
    {
        CPrintToChat(client, "%t", "Cooldown Message", cooldown - elapsed);
        return false;
    }

    g_fLastCmdTime[client] = currentTime;
    return true;
}

void FormatPlayTime(int client, int totalSeconds, char[] buffer, int maxlen)
{
    int days = totalSeconds / 86400;
    int remaining = totalSeconds % 86400;
    int hours = remaining / 3600;
    int mins = (remaining % 3600) / 60;

    if (days > 0)
    {
        Format(buffer, maxlen, "%T", "Time Format Days", client, days, hours, mins);
    }
    else
    {
        Format(buffer, maxlen, "%T", "Time Format", client, hours, mins);
    }
}

void NormalizeWeaponName(char[] weapon, int maxlen)
{
    if (StrContains(weapon, "weapon_", false) == 0)
    {
        ReplaceString(weapon, maxlen, "weapon_", "");
    }

    if (StrContains(weapon, "knife", false) != -1 || StrContains(weapon, "bayonet", false) != -1)
    {
        strcopy(weapon, maxlen, "Knife");
        return;
    }

    if (g_GameEngine == Engine_CSGO)
    {
        if (StrEqual(weapon, "m4a1_silencer", false))
        {
            strcopy(weapon, maxlen, "M4A1-S");
        }
        else if (StrEqual(weapon, "usp_silencer", false))
        {
            strcopy(weapon, maxlen, "USP-S");
        }
        else if (StrEqual(weapon, "molotov", false) || StrEqual(weapon, "incgrenade", false))
        {
            strcopy(weapon, maxlen, "Molotov/Inc");
        }
    }
}

void UpdateSessionPlayTime(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (g_iSessionStart[client] <= 0)
    {
        g_iSessionStart[client] = GetTime();
        return;
    }

    int now = GetTime();
    int sessionSeconds = now - g_iSessionStart[client];

    if (sessionSeconds > 0 && sessionSeconds < 86400)
    {
        g_iPlayTime[client] += sessionSeconds;
    }

    g_iSessionStart[client] = now;
}

bool GetClientSteam2Safe(int client, char[] auth, int maxlen)
{
    if (client <= 0 || client > MaxClients)
    {
        return false;
    }

    return GetClientAuthId(client, AuthId_Steam2, auth, maxlen);
}

bool IsChatTriggerMatch(const char[] text, const char[] trigger)
{
    if (StrEqual(text, trigger, false))
    {
        return true;
    }

    char prefixed[64];

    Format(prefixed, sizeof(prefixed), "!%s", trigger);
    if (StrEqual(text, prefixed, false))
    {
        return true;
    }

    Format(prefixed, sizeof(prefixed), "/%s", trigger);
    if (StrEqual(text, prefixed, false))
    {
        return true;
    }

    return false;
}

void SanitizePlayerName(char[] name, int maxlen)
{
    TrimString(name);

    if (name[0] == '\0')
    {
        strcopy(name, maxlen, "Unknown");
        return;
    }

    ReplaceString(name, maxlen, "\n", " ");
    ReplaceString(name, maxlen, "\r", " ");
    ReplaceString(name, maxlen, "\t", " ");
}

void PrecacheTop1Sound()
{
    char s[PLATFORM_MAX_PATH];
    g_cvTop1Sound.GetString(s, sizeof(s));

    if (s[0] != '\0')
    {
        PrecacheSound(s, true);
    }
}

// =============================================================================
// BASE DE DATOS Y PERSISTENCIA
// =============================================================================
void ConnectDatabase()
{
    char szDbTarget[64];
    g_cvDbConfig.GetString(szDbTarget, sizeof(szDbTarget));
    Database.Connect(SQL_OnConnect, szDbTarget);
}

public void SQL_OnConnect(Database db, const char[] error, any data)
{
    char szDbTarget[64];
    g_cvDbConfig.GetString(szDbTarget, sizeof(szDbTarget));

    if (db == null)
    {
        LogError("[Umbrella Ranked] No se pudo conectar a '%s': %s", szDbTarget, error);
        LogMessage("[Umbrella Ranked] Intentando fallback a storage-local...");
        Database.Connect(SQL_OnConnectDefault, "storage-local");
        return;
    }

    SetupDatabase(db);
}

public void SQL_OnConnectDefault(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Umbrella Ranked] No se pudo conectar a 'storage-local': %s", error);
        return;
    }

    SetupDatabase(db);
}

void SetupDatabase(Database db)
{
    g_hDatabase = db;
    g_hDatabase.Driver.GetIdentifier(g_szDriver, sizeof(g_szDriver));

    g_hDatabase.Query(SQL_IgnoreError,
        "CREATE TABLE IF NOT EXISTS player_stats (steamid VARCHAR(32) PRIMARY KEY, name VARCHAR(64), kills INT DEFAULT 0, deaths INT DEFAULT 0, playtime INT DEFAULT 0)"
    );

    g_hDatabase.Query(SQL_IgnoreError,
        "CREATE TABLE IF NOT EXISTS weapon_stats (steamid VARCHAR(32), weapon VARCHAR(32), kills INT DEFAULT 0, PRIMARY KEY (steamid, weapon))"
    );

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            LoadClientData(i);
        }
    }
}

public void SQL_IgnoreError(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Umbrella DB Error] %s", error);
    }
}

void LoadClientData(int client)
{
    if (g_hDatabase == null || client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char auth[32];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    char query[256];
    Format(query, sizeof(query), "SELECT kills, deaths, playtime FROM player_stats WHERE steamid = '%s'", auth);
    g_hDatabase.Query(SQL_OnDataLoaded, query, GetClientUserId(client));
}

void SaveClientData(int client, bool force = false, bool allowDisconnected = false)
{
    if (g_hDatabase == null || client <= 0 || client > MaxClients || IsFakeClient(client) || !g_bDataLoaded[client])
    {
        return;
    }

    if (!allowDisconnected && !IsClientInGame(client))
    {
        return;
    }

    if (!force && !g_bSaveDirty[client])
    {
        return;
    }

    char auth[32];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    char name[64], escName[128], query[512];

    if (!GetClientName(client, name, sizeof(name)))
    {
        strcopy(name, sizeof(name), "Unknown");
    }

    SanitizePlayerName(name, sizeof(name));
    g_hDatabase.Escape(name, escName, sizeof(escName));

    UpdateSessionPlayTime(client);

    if (StrEqual(g_szDriver, "sqlite"))
    {
        Format(query, sizeof(query),
            "INSERT OR REPLACE INTO player_stats (steamid, name, kills, deaths, playtime) VALUES ('%s', '%s', %d, %d, %d)",
            auth, escName, g_iKills[client], g_iDeaths[client], g_iPlayTime[client]
        );
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO player_stats (steamid, name, kills, deaths, playtime) VALUES ('%s', '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name='%s', kills=%d, deaths=%d, playtime=%d",
            auth, escName, g_iKills[client], g_iDeaths[client], g_iPlayTime[client],
            escName, g_iKills[client], g_iDeaths[client], g_iPlayTime[client]
        );
    }

    g_hDatabase.Query(SQL_IgnoreError, query);
    g_bSaveDirty[client] = false;
}

void SaveAllClientsData(bool force = false)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && !IsFakeClient(i))
        {
            SaveClientData(i, force, false);
        }
    }
}

void SaveWeaponKill(int client, const char[] rawWeapon)
{
    if (g_hDatabase == null || client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    char auth[32];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    char weapon[32], escWeapon[64], query[512];
    strcopy(weapon, sizeof(weapon), rawWeapon);
    NormalizeWeaponName(weapon, sizeof(weapon));
    g_hDatabase.Escape(weapon, escWeapon, sizeof(escWeapon));

    if (StrEqual(g_szDriver, "sqlite"))
    {
        Format(query, sizeof(query),
            "INSERT INTO weapon_stats (steamid, weapon, kills) VALUES ('%s', '%s', 1) ON CONFLICT(steamid, weapon) DO UPDATE SET kills = kills + 1",
            auth, escWeapon
        );
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO weapon_stats (steamid, weapon, kills) VALUES ('%s', '%s', 1) ON DUPLICATE KEY UPDATE kills = kills + 1",
            auth, escWeapon
        );
    }

    g_hDatabase.Query(SQL_IgnoreError, query);
}

// =============================================================================
// AUTOSAVE
// =============================================================================
void StartAutoSaveTimer()
{
    if (g_hAutoSaveTimer != null)
    {
        delete g_hAutoSaveTimer;
        g_hAutoSaveTimer = null;
    }

    float interval = g_cvAutoSave.FloatValue;
    if (interval <= 0.0)
    {
        return;
    }

    g_hAutoSaveTimer = CreateTimer(interval, Timer_AutoSave, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnAutoSaveCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    StartAutoSaveTimer();
}

public Action Timer_AutoSave(Handle timer, any data)
{
    if (g_hDatabase == null)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && g_bDataLoaded[i])
        {
            UpdateSessionPlayTime(i);
            g_bSaveDirty[i] = true;
            SaveClientData(i, false, false);
        }
    }

    return Plugin_Continue;
}

// =============================================================================
// CONEXIONES Y CARGA DE DATOS
// =============================================================================
public void OnClientPostAdminCheck(int client)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    ResetClientData(client);

    if (g_hDatabase != null)
    {
        LoadClientData(client);
    }
}

public void SQL_OnDataLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error cargando datos de %N: %s", client, error);
        g_bDataLoaded[client] = true;
        return;
    }

    if (results != null && results.FetchRow())
    {
        g_iKills[client] = results.FetchInt(0);
        g_iDeaths[client] = results.FetchInt(1);
        g_iPlayTime[client] = results.FetchInt(2);
    }

    g_bDataLoaded[client] = true;
    g_iSessionStart[client] = GetTime();
    g_bSaveDirty[client] = false;

    if (g_cvRankEnabled.BoolValue && g_iKills[client] >= g_cvMinKills.IntValue)
    {
        CreateTimer(3.0, Timer_CheckWelcome, GetClientUserId(client));
    }
}

public void OnClientDisconnect(int client)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    SaveClientData(client, true, true);
    g_bDataLoaded[client] = false;
    g_bSaveDirty[client] = false;
}

// =============================================================================
// EVENTO DE MUERTE
// =============================================================================
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvRankEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int atk = GetClientOfUserId(event.GetInt("attacker"));
    int vic = GetClientOfUserId(event.GetInt("userid"));

    if (atk > 0 && atk <= MaxClients && atk != vic && !IsFakeClient(atk) && g_bDataLoaded[atk])
    {
        g_iKills[atk]++;
        g_bSaveDirty[atk] = true;

        char weapon[64];
        event.GetString("weapon", weapon, sizeof(weapon));
        SaveWeaponKill(atk, weapon);

        SaveClientData(atk, false, false);
    }

    if (vic > 0 && vic <= MaxClients && !IsFakeClient(vic) && g_bDataLoaded[vic])
    {
        g_iDeaths[vic]++;
        g_bSaveDirty[vic] = true;

        SaveClientData(vic, false, false);
    }

    return Plugin_Continue;
}

// =============================================================================
// COMANDOS DE RANK Y TOPS
// =============================================================================
public Action Command_Rank(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!CheckCooldown(client))
    {
        return Plugin_Handled;
    }

    if (!g_cvRankEnabled.BoolValue)
    {
        CPrintToChat(client, "%t", "Rank Disabled");
        return Plugin_Handled;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    g_bSaveDirty[client] = true;
    SaveClientData(client, false, false);

    char query[512];
    Format(query, sizeof(query),
        "SELECT steamid FROM player_stats WHERE kills >= %d ORDER BY (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) DESC",
        g_cvMinKills.IntValue
    );
    g_hDatabase.Query(SQL_OnRankPos, query, GetClientUserId(client));

    return Plugin_Handled;
}

public void SQL_OnRankPos(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client) || results == null)
    {
        return;
    }

    char auth[32];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    int pos = 1;
    bool found = false;

    while (results.FetchRow())
    {
        char sid[32];
        results.FetchString(0, sid, sizeof(sid));

        if (StrEqual(sid, auth))
        {
            found = true;
            break;
        }

        pos++;
    }

    float kdr = (g_iDeaths[client] > 0) ? float(g_iKills[client]) / float(g_iDeaths[client]) : float(g_iKills[client]);

    char timeStr[32], buffer[256];
    FormatPlayTime(client, g_iPlayTime[client], timeStr, sizeof(timeStr));

    if (found)
    {
        Format(buffer, sizeof(buffer), "%T", "Rank Message", client, pos, g_iKills[client], g_iDeaths[client], kdr, timeStr);
    }
    else
    {
        Format(buffer, sizeof(buffer), "%T", "Not Ranked", client, g_iKills[client], g_iDeaths[client], kdr, timeStr);
    }

    CPrintToChat(client, buffer);
}

public Action Command_Top(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!CheckCooldown(client))
    {
        return Plugin_Handled;
    }

    if (!g_cvRankEnabled.BoolValue)
    {
        CPrintToChat(client, "%t", "Rank Disabled");
        return Plugin_Handled;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    char query[512];
    Format(query, sizeof(query),
        "SELECT name, kills, deaths, (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) AS kdr FROM player_stats WHERE kills >= %d ORDER BY kdr DESC LIMIT 50",
        g_cvMinKills.IntValue
    );
    g_hDatabase.Query(SQL_OnTop, query, GetClientUserId(client));

    return Plugin_Handled;
}

public void SQL_OnTop(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client) || results == null)
    {
        return;
    }

    Menu menu = new Menu(MH);

    char title[64];
    Format(title, sizeof(title), "%T", "Top Title", client);
    menu.SetTitle(title);

    int p = 1;
    while (results.FetchRow())
    {
        char n[64], line[192];
        results.FetchString(0, n, sizeof(n));
        SanitizePlayerName(n, sizeof(n));

        int kills = results.FetchInt(1);
        float kdr = results.FetchFloat(3);

        if (p == 1)
        {
            Format(line, sizeof(line), "%T", "Top Line First", client, n, kills, kdr);
        }
        else
        {
            Format(line, sizeof(line), "%T", "Top Line Rest", client, p, n, kills, kdr);
        }

        menu.AddItem("x", line, ITEMDRAW_DISABLED);
        p++;
    }

    menu.Display(client, 30);
}

public Action Command_TopTime(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!CheckCooldown(client))
    {
        return Plugin_Handled;
    }

    if (!g_cvRankEnabled.BoolValue)
    {
        CPrintToChat(client, "%t", "Rank Disabled");
        return Plugin_Handled;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    g_hDatabase.Query(SQL_OnTopTimeLoaded, "SELECT name, playtime FROM player_stats ORDER BY playtime DESC LIMIT 50", GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnTopTimeLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client) || results == null)
    {
        return;
    }

    Menu menu = new Menu(MH);

    char title[64];
    Format(title, sizeof(title), "%T", "Top Time Title", client);
    menu.SetTitle(title);

    int p = 1;
    while (results.FetchRow())
    {
        char name[64], line[128], timeStr[32];
        results.FetchString(0, name, sizeof(name));
        SanitizePlayerName(name, sizeof(name));
        FormatPlayTime(client, results.FetchInt(1), timeStr, sizeof(timeStr));

        if (p == 1)
        {
            Format(line, sizeof(line), "%T", "Time Line First", client, name, timeStr);
        }
        else
        {
            Format(line, sizeof(line), "%T", "Time Line Rest", client, p, name, timeStr);
        }

        menu.AddItem("x", line, ITEMDRAW_DISABLED);
        p++;
    }

    menu.Display(client, 30);
}

public Action Command_WeaponMenu(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!CheckCooldown(client))
    {
        return Plugin_Handled;
    }

    if (!g_cvRankEnabled.BoolValue)
    {
        CPrintToChat(client, "%t", "Rank Disabled");
        return Plugin_Handled;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    g_hDatabase.Query(SQL_OnLoadWeaponMenu, "SELECT DISTINCT weapon FROM weapon_stats ORDER BY weapon ASC", GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnLoadWeaponMenu(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client) || results == null)
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_WeaponSelect);

    char title[64];
    Format(title, sizeof(title), "%T", "Weapon Menu Title", client);
    menu.SetTitle(title);

    while (results.FetchRow())
    {
        char w[32];
        results.FetchString(0, w, sizeof(w));
        menu.AddItem(w, w);
    }

    menu.Display(client, 30);
}

public int MenuHandler_WeaponSelect(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        if (g_hDatabase == null)
        {
            return 0;
        }

        char weapon[32], escWeapon[64], query[512];
        menu.GetItem(param2, weapon, sizeof(weapon));
        g_hDatabase.Escape(weapon, escWeapon, sizeof(escWeapon));

        Format(query, sizeof(query),
            "SELECT p.name, w.kills FROM weapon_stats w JOIN player_stats p ON w.steamid = p.steamid WHERE w.weapon = '%s' ORDER BY w.kills DESC LIMIT 50",
            escWeapon
        );

        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(param1));
        pack.WriteString(weapon);

        g_hDatabase.Query(SQL_OnTopWeaponLoaded, query, pack);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public void SQL_OnTopWeaponLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int client = GetClientOfUserId(pack.ReadCell());
    char weapon[32];
    pack.ReadString(weapon, sizeof(weapon));
    delete pack;

    if (client == 0 || !IsClientInGame(client) || results == null)
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_TopWeapon);

    char title[64];
    Format(title, sizeof(title), "%T", "Top Weapon Title", client, weapon);
    menu.SetTitle(title);

    int p = 1;
    while (results.FetchRow())
    {
        char n[64], line[128];
        results.FetchString(0, n, sizeof(n));
        SanitizePlayerName(n, sizeof(n));

        int k = results.FetchInt(1);
        if (p == 1)
        {
            Format(line, sizeof(line), "%T", "Weapon Line First", client, n, k);
        }
        else
        {
            Format(line, sizeof(line), "%T", "Weapon Line Rest", client, p, n, k);
        }

        menu.AddItem("x", line, ITEMDRAW_DISABLED);
        p++;
    }

    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int MenuHandler_TopWeapon(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Command_WeaponMenu(param1, 0);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

// =============================================================================
// BIENVENIDA Y SONIDOS
// =============================================================================
public Action Timer_CheckWelcome(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client) || g_hDatabase == null)
    {
        return Plugin_Stop;
    }

    char query[512];
    Format(query, sizeof(query),
        "SELECT steamid FROM player_stats WHERE kills >= %d ORDER BY (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) DESC LIMIT 5",
        g_cvMinKills.IntValue
    );

    g_hDatabase.Query(SQL_OnCheckWelcome, query, GetClientUserId(client));
    return Plugin_Stop;
}

public void SQL_OnCheckWelcome(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client) || results == null)
    {
        return;
    }

    char auth[32];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    int pos = 1;
    bool isTop = false;

    while (results.FetchRow())
    {
        char tsid[32];
        results.FetchString(0, tsid, sizeof(tsid));

        if (StrEqual(tsid, auth))
        {
            isTop = true;
            break;
        }

        pos++;
    }

    if (isTop)
    {
        char name[64], buffer[256];
        GetClientName(client, name, sizeof(name));
        SanitizePlayerName(name, sizeof(name));

        if (pos == 1)
        {
            Format(buffer, sizeof(buffer), "%T", "Top1 Announce", LANG_SERVER, name);
            CPrintToChatAll(buffer);

            char s[PLATFORM_MAX_PATH];
            g_cvTop1Sound.GetString(s, sizeof(s));
            if (s[0] != '\0')
            {
                EmitSoundToAll(s);
            }
        }
        else
        {
            Format(buffer, sizeof(buffer), "%T", "Top5 Announce", LANG_SERVER, pos, name);
            CPrintToChatAll(buffer);
        }
    }
}

// =============================================================================
// LISTENERS DE CHAT
// =============================================================================
public Action Command_Say(int client, const char[] command, int argc)
{
    if (client <= 0 || client > MaxClients)
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (IsChatTriggerMatch(text, "rank"))
    {
        Command_Rank(client, 0);
        return Plugin_Handled;
    }

    if (IsChatTriggerMatch(text, "top"))
    {
        Command_Top(client, 0);
        return Plugin_Handled;
    }

    if (IsChatTriggerMatch(text, "toparmas") || IsChatTriggerMatch(text, "topweapons"))
    {
        Command_WeaponMenu(client, 0);
        return Plugin_Handled;
    }

    if (IsChatTriggerMatch(text, "toptime"))
    {
        Command_TopTime(client, 0);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

// =============================================================================
// HANDLER MENU SIMPLE
// =============================================================================
public int MH(Menu m, MenuAction a, int p1, int p2)
{
    if (a == MenuAction_End)
    {
        delete m;
    }

    return 0;
}