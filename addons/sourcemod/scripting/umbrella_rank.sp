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
int g_iLastReset[MAXPLAYERS + 1];

bool g_bDataLoaded[MAXPLAYERS + 1];
bool g_bSaveDirty[MAXPLAYERS + 1];

float g_fLastCmdTime[MAXPLAYERS + 1];
bool g_bResetInProgress[MAXPLAYERS + 1];

ConVar g_cvDbConfig;
ConVar g_cvMinKills;
ConVar g_cvTop1Sound;
ConVar g_cvRankEnabled;
ConVar g_cvCooldown;
ConVar g_cvAutoSave;
ConVar g_cvPruneDays;
ConVar g_cvAllowReset;
ConVar g_cvResetCooldownDays;

Handle g_hAutoSaveTimer = null;
Handle g_hPruneTimer = null;

public Plugin myinfo =
{
    name = "Umbrella Ranked System",
    author = "Ayrton09",
    description = "Ranking System: KDR, Time & Weapons (CS:GO/CS:S)",
    version = "2.6.0",
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
    g_cvMinKills    = CreateConVar("sm_rank_min_kills", "1", "Minimum kills required for a player to be ranked.", _, true, 0.0);
    g_cvTop1Sound   = CreateConVar("sm_rank_top1_sound", "buttons/bell1.wav", "Sound path for Top #1 join.");
    g_cvRankEnabled = CreateConVar("sm_rank_enabled", "1", "1 = Enabled, 0 = Disabled.", _, true, 0.0, true, 1.0);
    g_cvCooldown    = CreateConVar("sm_rank_cooldown", "3.0", "Seconds to wait between commands.", _, true, 0.0);
    g_cvAutoSave    = CreateConVar("sm_rank_autosave_interval", "120.0", "Seconds between autosaves. 0 = disabled.", _, true, 0.0);
    g_cvPruneDays   = CreateConVar("sm_rank_prune_days", "0", "Delete stats for players inactive for this many days. 0 = disabled.", _, true, 0.0);
    g_cvAllowReset  = CreateConVar("sm_rank_allow_reset", "1", "Allow players to reset their own rank stats.", _, true, 0.0, true, 1.0);
    g_cvResetCooldownDays = CreateConVar("sm_rank_reset_cooldown_days", "30", "Days a player must wait before using !resetrank again. 0 = no cooldown.", _, true, 0.0);

    g_cvAutoSave.AddChangeHook(OnAutoSaveCvarChanged);
    g_cvPruneDays.AddChangeHook(OnPruneCvarChanged);

    AutoExecConfig(true, "umbrella_ranked");

    RegConsoleCmd("sm_rank", Command_Rank);
    RegConsoleCmd("sm_top", Command_Top);
    RegConsoleCmd("sm_toparmas", Command_WeaponMenu);
    RegConsoleCmd("sm_topweapons", Command_WeaponMenu);
    RegConsoleCmd("sm_toptime", Command_TopTime);
    RegConsoleCmd("sm_resetrank", Command_ResetRank);
    RegConsoleCmd("sm_rrank", Command_ResetRank);
    RegAdminCmd("sm_rank_prunenow", Command_PruneNow, ADMFLAG_ROOT, "Run inactive rank data prune immediately.");

    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    HookEvent("player_death", Event_PlayerDeath);

    StartAutoSaveTimer();
    StartPruneTimer();
    ConnectDatabase();
}

public void OnConfigsExecuted()
{
    PrecacheTop1Sound();
    StartAutoSaveTimer();
    StartPruneTimer();

    if (g_hDatabase != null)
    {
        RunPruneInactivePlayers();
    }
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

    if (g_hAutoSaveTimer != null)
    {
        delete g_hAutoSaveTimer;
        g_hAutoSaveTimer = null;
    }

    if (g_hPruneTimer != null)
    {
        delete g_hPruneTimer;
        g_hPruneTimer = null;
    }

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
    g_iLastReset[client] = 0;

    g_bDataLoaded[client] = false;
    g_bSaveDirty[client] = false;
    g_fLastCmdTime[client] = 0.0;
    g_bResetInProgress[client] = false;
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
            return;
        }
        else if (StrEqual(weapon, "usp_silencer", false))
        {
            strcopy(weapon, maxlen, "USP-S");
            return;
        }
        else if (StrEqual(weapon, "molotov", false) || StrEqual(weapon, "incgrenade", false))
        {
            strcopy(weapon, maxlen, "Molotov/Inc");
            return;
        }
    }

    if (StrEqual(weapon, "hegrenade", false))
    {
        strcopy(weapon, maxlen, "HE Grenade");
    }
    else if (StrEqual(weapon, "flashbang", false))
    {
        strcopy(weapon, maxlen, "Flashbang");
    }
    else if (StrEqual(weapon, "smokegrenade", false))
    {
        strcopy(weapon, maxlen, "Smoke Grenade");
    }
    else if (StrEqual(weapon, "decoy", false))
    {
        strcopy(weapon, maxlen, "Decoy");
    }
    else if (StrEqual(weapon, "inferno", false))
    {
        strcopy(weapon, maxlen, "Fire");
    }
    else if (StrEqual(weapon, "world", false))
    {
        strcopy(weapon, maxlen, "World");
    }
    else if (weapon[0] == '\0')
    {
        strcopy(weapon, maxlen, "Unknown");
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

void GetTop1SoundPath(char[] sample, int sampleLen, char[] download, int downloadLen)
{
    g_cvTop1Sound.GetString(sample, sampleLen);
    TrimString(sample);

    if (sample[0] == '\0')
    {
        download[0] = '\0';
        return;
    }

    if (StrContains(sample, "sound/", false) == 0)
    {
        strcopy(download, downloadLen, sample);

        int dst = 0;
        for (int src = 6; sample[src] != '\0' && dst < sampleLen - 1; src++)
        {
            sample[dst++] = sample[src];
        }
        sample[dst] = '\0';
        return;
    }

    Format(download, downloadLen, "sound/%s", sample);
}


void BuildConnectedSteamExcludeClause(char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    bool first = true;
    int count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

        char auth[32];
        if (!GetClientSteam2Safe(i, auth, sizeof(auth)))
        {
            continue;
        }

        if (first)
        {
            StrCat(buffer, maxlen, " AND steamid NOT IN (");
            first = false;
        }
        else
        {
            StrCat(buffer, maxlen, ",");
        }

        char entry[48];
        Format(entry, sizeof(entry), "'%s'", auth);
        StrCat(buffer, maxlen, entry);
        count++;
    }

    if (count > 0)
    {
        StrCat(buffer, maxlen, ")");
    }
}

bool CanUseResetRank(int client, bool showMessages = true, bool checkCooldown = true)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }

    if (checkCooldown && !CheckCooldown(client))
    {
        return false;
    }

    if (!g_cvAllowReset.BoolValue)
    {
        if (showMessages)
        {
            CPrintToChat(client, "%t", "Reset Rank Disabled");
        }
        return false;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        if (showMessages)
        {
            CPrintToChat(client, "%t", "Data Loading");
        }
        return false;
    }

    if (g_bResetInProgress[client])
    {
        if (showMessages)
        {
            CPrintToChat(client, "%t", "Reset Rank In Progress");
        }
        return false;
    }

    int cooldownDays = g_cvResetCooldownDays.IntValue;
    int now = GetTime();

    if (cooldownDays > 0 && g_iLastReset[client] > 0)
    {
        int nextReset = g_iLastReset[client] + (cooldownDays * 86400);
        if (now < nextReset)
        {
            int remaining = nextReset - now;
            int days = remaining / 86400;
            int hours = (remaining % 86400) / 3600;

            if (showMessages)
            {
                CPrintToChat(client, "%t", "Reset Rank Cooldown", days, hours);
            }
            return false;
        }
    }

    return true;
}

void ShowResetRankConfirmMenu(int client)
{
    Menu menu = new Menu(MenuHandler_ResetRankConfirm);

    char title[128];
    Format(title, sizeof(title), "%T", "Reset Rank Confirm Title", client);
    menu.SetTitle(title);

    char yesText[64], noText[64];
    Format(yesText, sizeof(yesText), "%T", "Reset Rank Confirm Yes", client);
    Format(noText, sizeof(noText), "%T", "Reset Rank Confirm No", client);

    menu.AddItem("yes", yesText);
    menu.AddItem("no", noText);
    menu.ExitButton = true;
    menu.Display(client, 20);
}

void StartResetRankNow(int client)
{
    if (!CanUseResetRank(client, true, false))
    {
        return;
    }

    char auth[32], escAuth[64], query[256];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return;
    }

    g_hDatabase.Escape(auth, escAuth, sizeof(escAuth));
    UpdateSessionPlayTime(client);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(auth);
    char name[64];
    if (!GetClientName(client, name, sizeof(name)))
    {
        strcopy(name, sizeof(name), "Unknown");
    }
    SanitizePlayerName(name, sizeof(name));
    pack.WriteString(name);
    pack.WriteCell(g_iPlayTime[client]);
    pack.WriteCell(GetTime());

    g_bResetInProgress[client] = true;

    Format(query, sizeof(query), "DELETE FROM weapon_stats WHERE steamid = '%s'", escAuth);
    g_hDatabase.Query(SQL_OnResetDeleteWeapons, query, pack);
}

void PrecacheTop1Sound()
{
    char sample[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];
    GetTop1SoundPath(sample, sizeof(sample), download, sizeof(download));

    if (sample[0] == '\0')
    {
        return;
    }

    if (FileExists(download, true))
    {
        AddFileToDownloadsTable(download);
    }

    PrecacheSound(sample, true);
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
        return;
    }

    SetupDatabase(db);
}

void SetupDatabase(Database db)
{
    g_hDatabase = db;
    g_hDatabase.Driver.GetIdentifier(g_szDriver, sizeof(g_szDriver));

    g_hDatabase.Query(SQL_IgnoreError,
        "CREATE TABLE IF NOT EXISTS player_stats (steamid VARCHAR(32) PRIMARY KEY, name VARCHAR(64), kills INT DEFAULT 0, deaths INT DEFAULT 0, playtime INT DEFAULT 0, last_seen INT DEFAULT 0, last_reset INT DEFAULT 0)"
    );

    g_hDatabase.Query(SQL_IgnoreError,
        "ALTER TABLE player_stats ADD COLUMN last_seen INT DEFAULT 0"
    );

    g_hDatabase.Query(SQL_IgnoreError,
        "ALTER TABLE player_stats ADD COLUMN last_reset INT DEFAULT 0"
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

    RunPruneInactivePlayers();
}

public void SQL_IgnoreError(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] == '\0')
    {
        return;
    }

    if ((StrContains(error, "last_seen", false) != -1 || StrContains(error, "last_reset", false) != -1)
        && (StrContains(error, "duplicate", false) != -1 || StrContains(error, "exists", false) != -1 || StrContains(error, "already exists", false) != -1))
    {
        return;
    }

    LogError("[Umbrella DB Error] %s", error);
}

void StartPruneTimer()
{
    if (g_hPruneTimer != null)
    {
        delete g_hPruneTimer;
        g_hPruneTimer = null;
    }

    if (g_cvPruneDays.IntValue <= 0)
    {
        return;
    }

    g_hPruneTimer = CreateTimer(21600.0, Timer_PruneInactivePlayers, _, TIMER_REPEAT);
}

public void OnPruneCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    StartPruneTimer();

    if (g_hDatabase != null)
    {
        RunPruneInactivePlayers();
    }
}

public Action Timer_PruneInactivePlayers(Handle timer, any data)
{
    RunPruneInactivePlayers();
    return Plugin_Continue;
}

void RunPruneInactivePlayers()
{
    if (g_hDatabase == null)
    {
        return;
    }

    int pruneDays = g_cvPruneDays.IntValue;
    if (pruneDays <= 0)
    {
        return;
    }

    int cutoff = GetTime() - (pruneDays * 86400);
    char exclude[2048], query[4096];
    BuildConnectedSteamExcludeClause(exclude, sizeof(exclude));

    Format(query, sizeof(query),
        "DELETE FROM weapon_stats WHERE steamid IN (SELECT steamid FROM player_stats WHERE last_seen > 0 AND last_seen < %d%s)",
        cutoff, exclude
    );
    g_hDatabase.Query(SQL_IgnoreError, query);

    Format(query, sizeof(query),
        "DELETE FROM player_stats WHERE last_seen > 0 AND last_seen < %d%s",
        cutoff, exclude
    );
    g_hDatabase.Query(SQL_IgnoreError, query);
}

void LoadClientData(int client)
{
    if (g_hDatabase == null || client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char auth[32], escAuth[64];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    g_hDatabase.Escape(auth, escAuth, sizeof(escAuth));

    char query[256];
    Format(query, sizeof(query), "SELECT kills, deaths, playtime, last_reset FROM player_stats WHERE steamid = '%s'", escAuth);
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

    char auth[32], escAuth[64];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }

    g_hDatabase.Escape(auth, escAuth, sizeof(escAuth));

    char name[64], escName[128], query[768];
    int lastSeen = GetTime();
    int lastReset = g_iLastReset[client];

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
            "INSERT OR REPLACE INTO player_stats (steamid, name, kills, deaths, playtime, last_seen, last_reset) VALUES ('%s', '%s', %d, %d, %d, %d, %d)",
            escAuth, escName, g_iKills[client], g_iDeaths[client], g_iPlayTime[client], lastSeen, lastReset
        );
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO player_stats (steamid, name, kills, deaths, playtime, last_seen, last_reset) VALUES ('%s', '%s', %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE name='%s', kills=%d, deaths=%d, playtime=%d, last_seen=%d, last_reset=%d",
            escAuth, escName, g_iKills[client], g_iDeaths[client], g_iPlayTime[client], lastSeen, lastReset,
            escName, g_iKills[client], g_iDeaths[client], g_iPlayTime[client], lastSeen, lastReset
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
            SaveClientData(i, force, true);
        }
    }
}

void SaveWeaponKill(int client, const char[] rawWeapon)
{
    if (g_hDatabase == null || client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    char auth[32], escAuth[64];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }
    g_hDatabase.Escape(auth, escAuth, sizeof(escAuth));

    char weapon[32], escWeapon[64], query[512];
    strcopy(weapon, sizeof(weapon), rawWeapon);
    NormalizeWeaponName(weapon, sizeof(weapon));
    g_hDatabase.Escape(weapon, escWeapon, sizeof(escWeapon));

    if (StrEqual(g_szDriver, "sqlite"))
    {
        Format(query, sizeof(query),
            "INSERT INTO weapon_stats (steamid, weapon, kills) VALUES ('%s', '%s', 1) ON CONFLICT(steamid, weapon) DO UPDATE SET kills = kills + 1",
            escAuth, escWeapon
        );
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO weapon_stats (steamid, weapon, kills) VALUES ('%s', '%s', 1) ON DUPLICATE KEY UPDATE kills = kills + 1",
            escAuth, escWeapon
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

    g_hAutoSaveTimer = CreateTimer(interval, Timer_AutoSave, _, TIMER_REPEAT);
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
        if (IsClientInGame(i) && !IsFakeClient(i) && g_bDataLoaded[i] && !g_bResetInProgress[i])
        {
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
        g_bDataLoaded[client] = false;
        return;
    }

    if (results != null && results.FetchRow())
    {
        g_iKills[client] = results.FetchInt(0);
        g_iDeaths[client] = results.FetchInt(1);
        g_iPlayTime[client] = results.FetchInt(2);
        g_iLastReset[client] = results.FetchInt(3);
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

    if (!g_bResetInProgress[client])
    {
        SaveClientData(client, true, true);
    }

    g_bDataLoaded[client] = false;
    g_bSaveDirty[client] = false;
    g_bResetInProgress[client] = false;
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

    if (atk > 0 && atk <= MaxClients && atk != vic && !IsFakeClient(atk) && g_bDataLoaded[atk] && !g_bResetInProgress[atk])
    {
        g_iKills[atk]++;
        g_bSaveDirty[atk] = true;

        char weapon[64];
        event.GetString("weapon", weapon, sizeof(weapon));
        SaveWeaponKill(atk, weapon);
    }

    if (vic > 0 && vic <= MaxClients && !IsFakeClient(vic) && g_bDataLoaded[vic] && !g_bResetInProgress[vic])
    {
        g_iDeaths[vic]++;
        g_bSaveDirty[vic] = true;
    }

    return Plugin_Continue;
}

public Action Command_ResetRank(int client, int args)
{
    if (!CanUseResetRank(client, true))
    {
        return Plugin_Handled;
    }

    ShowResetRankConfirmMenu(client);
    return Plugin_Handled;
}

public int MenuHandler_ResetRankConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "yes"))
        {
            StartResetRankNow(param1);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public void SQL_OnResetDeleteWeapons(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        LogError("[Umbrella Ranked] Reset callback without context data.");
        return;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    char auth[32];
    pack.ReadString(auth, sizeof(auth));
    char name[64];
    pack.ReadString(name, sizeof(name));
    int playtime = pack.ReadCell();
    int resetTime = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);

    if (error[0] != '\0')
    {
        if (client != 0 && IsClientInGame(client))
        {
            g_bResetInProgress[client] = false;
            CPrintToChat(client, "%t", "Reset Rank Error");
        }

        LogError("[Umbrella Ranked] Error resetting weapon stats for userid %d: %s", userid, error);
        return;
    }

    char escAuth[64];
    db.Escape(auth, escAuth, sizeof(escAuth));

    char escName[128], query[1024];
    db.Escape(name, escName, sizeof(escName));

    if (StrEqual(g_szDriver, "sqlite"))
    {
        Format(query, sizeof(query),
            "INSERT INTO player_stats (steamid, name, kills, deaths, playtime, last_seen, last_reset) VALUES ('%s', '%s', 0, 0, %d, %d, %d) ON CONFLICT(steamid) DO UPDATE SET name = '%s', kills = 0, deaths = 0, playtime = %d, last_seen = %d, last_reset = %d",
            escAuth, escName, playtime, resetTime, resetTime, escName, playtime, resetTime, resetTime
        );
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO player_stats (steamid, name, kills, deaths, playtime, last_seen, last_reset) VALUES ('%s', '%s', 0, 0, %d, %d, %d) ON DUPLICATE KEY UPDATE name='%s', kills=0, deaths=0, playtime=%d, last_seen=%d, last_reset=%d",
            escAuth, escName, playtime, resetTime, resetTime, escName, playtime, resetTime, resetTime
        );
    }

    DataPack next = new DataPack();
    next.WriteCell(userid);
    next.WriteCell(resetTime);

    db.Query(SQL_OnResetSavePlayer, query, next);
}

public void SQL_OnResetSavePlayer(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        LogError("[Umbrella Ranked] Reset save callback without context data.");
        return;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    int resetTime = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    g_bResetInProgress[client] = false;

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error saving rank reset for userid %d: %s", userid, error);
        CPrintToChat(client, "%t", "Reset Rank Error");
        return;
    }

    g_iKills[client] = 0;
    g_iDeaths[client] = 0;
    g_iLastReset[client] = resetTime;
    g_iSessionStart[client] = GetTime();
    g_bSaveDirty[client] = false;

    CPrintToChat(client, "%t", "Reset Rank Success");
}


public Action Command_PruneNow(int client, int args)
{
    if (g_hDatabase == null)
    {
        if (client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "%t", "Prune Data Loading");
        }
        else
        {
            ReplyToCommand(client, "%t", "Prune Data Loading");
        }
        return Plugin_Handled;
    }

    RunPruneInactivePlayers();

    if (client > 0 && IsClientInGame(client))
    {
        CPrintToChat(client, "%t", "Prune Started");
    }
    else
    {
        ReplyToCommand(client, "%t", "Prune Started");
    }

    return Plugin_Handled;
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
    SaveClientData(client, true, false);

    char auth[32], escAuth[64], query[1024];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    g_hDatabase.Escape(auth, escAuth, sizeof(escAuth));

    Format(query, sizeof(query),
        "SELECT CASE WHEN me.kills >= %d THEN 1 + (SELECT COUNT(*) FROM player_stats other WHERE other.kills >= %d AND ((other.kills * 1.0 / CASE WHEN other.deaths = 0 THEN 1 ELSE other.deaths END) > (me.kills * 1.0 / CASE WHEN me.deaths = 0 THEN 1 ELSE me.deaths END) OR ((other.kills * 1.0 / CASE WHEN other.deaths = 0 THEN 1 ELSE other.deaths END) = (me.kills * 1.0 / CASE WHEN me.deaths = 0 THEN 1 ELSE me.deaths END) AND (other.kills > me.kills OR (other.kills = me.kills AND (other.playtime > me.playtime OR (other.playtime = me.playtime AND other.name < me.name))))))) ELSE 0 END AS rank_pos FROM player_stats me WHERE me.steamid = '%s' LIMIT 1",
        g_cvMinKills.IntValue, g_cvMinKills.IntValue, escAuth
    );
    g_hDatabase.Query(SQL_OnRankPos, query, GetClientUserId(client));

    return Plugin_Handled;
}

public void SQL_OnRankPos(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error cargando posición de rank para %N: %s", client, error);
        CPrintToChat(client, "%t", "Rank Position Error");
        return;
    }

    float kdr = (g_iDeaths[client] > 0) ? float(g_iKills[client]) / float(g_iDeaths[client]) : float(g_iKills[client]);

    char timeStr[32], buffer[256];
    FormatPlayTime(client, g_iPlayTime[client], timeStr, sizeof(timeStr));

    int pos = 0;
    if (results != null && results.FetchRow())
    {
        pos = results.FetchInt(0);
    }

    if (pos > 0)
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
        "SELECT name, kills, deaths, (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) AS kdr FROM player_stats WHERE kills >= %d ORDER BY kdr DESC, kills DESC, playtime DESC, name ASC LIMIT 50",
        g_cvMinKills.IntValue
    );
    g_hDatabase.Query(SQL_OnTop, query, GetClientUserId(client));

    return Plugin_Handled;
}

public void SQL_OnTop(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error cargando top KDR para %N: %s", client, error);
        CPrintToChat(client, "%t", "Top Load Error");
        return;
    }

    if (results == null)
    {
        return;
    }

    Menu menu = new Menu(MH);

    char title[64];
    Format(title, sizeof(title), "%T", "Top Title", client);
    menu.SetTitle(title);

    int p = 1;
    bool hasRows = false;
    char line[128];
    while (results.FetchRow())
    {
        hasRows = true;

        char n[64], entry[192];
        results.FetchString(0, n, sizeof(n));
        SanitizePlayerName(n, sizeof(n));

        int kills = results.FetchInt(1);
        float kdr = results.FetchFloat(3);

        if (p == 1)
        {
            Format(entry, sizeof(entry), "%T", "Top Line First", client, n, kills, kdr);
        }
        else
        {
            Format(entry, sizeof(entry), "%T", "Top Line Rest", client, p, n, kills, kdr);
        }

        menu.AddItem("x", entry, ITEMDRAW_DISABLED);
        p++;
    }

    if (!hasRows)
    {
        FormatEx(line, sizeof(line), "%T", "No Ranked Players Yet", client);
        menu.AddItem("empty", line, ITEMDRAW_DISABLED);
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

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    g_hDatabase.Query(SQL_OnTopTimeLoaded, "SELECT name, playtime FROM player_stats ORDER BY playtime DESC, name ASC LIMIT 50", GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnTopTimeLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error cargando top de tiempo para %N: %s", client, error);
        CPrintToChat(client, "%t", "Top Time Load Error");
        return;
    }

    if (results == null)
    {
        return;
    }

    Menu menu = new Menu(MH);

    char title[64];
    Format(title, sizeof(title), "%T", "Top Time Title", client);
    menu.SetTitle(title);

    int p = 1;
    bool hasRows = false;
    char line[128];
    while (results.FetchRow())
    {
        hasRows = true;

        char name[64], timeStr[32];
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

    if (!hasRows)
    {
        FormatEx(line, sizeof(line), "%T", "No Playtime Yet", client);
        menu.AddItem("empty", line, ITEMDRAW_DISABLED);
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
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error cargando menú de armas para %N: %s", client, error);
        CPrintToChat(client, "%t", "Weapon Menu Load Error");
        return;
    }

    if (results == null)
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_WeaponSelect);

    char title[64];
    Format(title, sizeof(title), "%T", "Weapon Menu Title", client);
    menu.SetTitle(title);

    bool hasRows = false;
    char line[128];
    while (results.FetchRow())
    {
        hasRows = true;

        char w[32];
        results.FetchString(0, w, sizeof(w));
        menu.AddItem(w, w);
    }

    if (!hasRows)
    {
        FormatEx(line, sizeof(line), "%T", "No Weapons Yet", client);
        menu.AddItem("empty", line, ITEMDRAW_DISABLED);
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
            "SELECT p.name, w.kills FROM weapon_stats w JOIN player_stats p ON w.steamid = p.steamid WHERE w.weapon = '%s' ORDER BY w.kills DESC, p.name ASC LIMIT 50",
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

    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error cargando top del arma '%s' para %N: %s", weapon, client, error);
        CPrintToChat(client, "%t", "Weapon Top Load Error");
        return;
    }

    if (results == null)
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_TopWeapon);

    char title[64];
    Format(title, sizeof(title), "%T", "Top Weapon Title", client, weapon);
    menu.SetTitle(title);

    int p = 1;
    bool hasRows = false;
    char line[128];
    while (results.FetchRow())
    {
        hasRows = true;

        char n[64];
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

    if (!hasRows)
    {
        FormatEx(line, sizeof(line), "%T", "No Weapon Kills Yet", client);
        menu.AddItem("empty", line, ITEMDRAW_DISABLED);
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
        "SELECT steamid FROM player_stats WHERE kills >= %d ORDER BY (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) DESC, kills DESC, playtime DESC, name ASC LIMIT 5",
        g_cvMinKills.IntValue
    );

    g_hDatabase.Query(SQL_OnCheckWelcome, query, GetClientUserId(client));
    return Plugin_Stop;
}

public void SQL_OnCheckWelcome(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error comprobando bienvenida top para %N: %s", client, error);
        return;
    }

    if (results == null)
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

            char sample[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];
            GetTop1SoundPath(sample, sizeof(sample), download, sizeof(download));
            if (sample[0] != '\0')
            {
                EmitSoundToAll(sample);
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

    if (IsChatTriggerMatch(text, "resetrank") || IsChatTriggerMatch(text, "rrank"))
    {
        Command_ResetRank(client, 0);
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
