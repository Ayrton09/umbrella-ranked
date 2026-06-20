#include <sourcemod>
#include <sdktools>
#include <multicolors>

// =============================================================================
// VARIABLES GLOBALES
// =============================================================================
#define RANK_DB_CONNECTION "ranked_db"
#define RANK_TOP1_SOUND "buttons/bell1.wav"
#define RANK_MIN_POINTS 0
#define RANK_DB_MAX_RETRIES 3
#define RANK_DB_RETRY_DELAY 5.0
#define RANK_MAX_WEAPON_DELTAS 64
EngineVersion g_GameEngine;
Database g_hDatabase = null;
char g_szDriver[16];

int g_iKills[MAXPLAYERS + 1];
int g_iDeaths[MAXPLAYERS + 1];
int g_iPoints[MAXPLAYERS + 1];
int g_iPlayTime[MAXPLAYERS + 1];
int g_iSessionStart[MAXPLAYERS + 1];
int g_iLastReset[MAXPLAYERS + 1];
int g_iHeadshots[MAXPLAYERS + 1];
int g_iDominations[MAXPLAYERS + 1];
int g_iRevenges[MAXPLAYERS + 1];
int g_iTeamKills[MAXPLAYERS + 1];
int g_iSuicides[MAXPLAYERS + 1];
int g_iBombPlants[MAXPLAYERS + 1];
int g_iBombDefuses[MAXPLAYERS + 1];
int g_iBombExplosions[MAXPLAYERS + 1];
int g_iHostagesRescued[MAXPLAYERS + 1];

int g_iConnectTime[MAXPLAYERS + 1];
int g_iSessionPoints[MAXPLAYERS + 1];
int g_iSessionKills[MAXPLAYERS + 1];
int g_iSessionDeaths[MAXPLAYERS + 1];
int g_iSessionHeadshots[MAXPLAYERS + 1];
int g_iSessionObjectives[MAXPLAYERS + 1];

bool g_bDataLoaded[MAXPLAYERS + 1];
bool g_bSaveDirty[MAXPLAYERS + 1];
int g_iDirtySequence[MAXPLAYERS + 1];
int g_iSaveSequence[MAXPLAYERS + 1];

float g_fLastCmdTime[MAXPLAYERS + 1];
bool g_bResetInProgress[MAXPLAYERS + 1];

ConVar g_cvRankEnabled;
ConVar g_cvMinPlayers;

ConVar g_cvStartPoints;
ConVar g_cvMinKills;
ConVar g_cvCmdCooldown;
ConVar g_cvAutosaveInterval;
ConVar g_cvResetCooldownDays;
ConVar g_cvBareTriggers;

ConVar g_cvKillBase;
ConVar g_cvKillMin;
ConVar g_cvKillMax;
ConVar g_cvDiffStep;
ConVar g_cvDeathMultiplier;
ConVar g_cvHeadshotBonus;
ConVar g_cvDominationBonus;
ConVar g_cvRevengeBonus;
ConVar g_cvKnifeMultiplier;
ConVar g_cvTaserBonus;
ConVar g_cvAssistPoints;
ConVar g_cvTeamkillPenalty;
ConVar g_cvSuicidePenalty;
ConVar g_cvMvpPoints;
ConVar g_cvBombPlant;
ConVar g_cvBombDefuse;
ConVar g_cvBombExplode;
ConVar g_cvHostageRescue;
ConVar g_cvTeamWin;
ConVar g_cvTeamLoss;

Handle g_hAutoSaveTimer = null;

char g_szWeaponDeltaName[MAXPLAYERS + 1][RANK_MAX_WEAPON_DELTAS][32];
int g_iWeaponDeltaKills[MAXPLAYERS + 1][RANK_MAX_WEAPON_DELTAS];
int g_iWeaponDeltaCount[MAXPLAYERS + 1];
bool g_bWeaponFlushInFlight[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "Umbrella Ranked System",
    author = "Ayrton09",
    description = "Ranking System: Points, KDR, Time & Weapons (CS:GO/CS:S)",
    version = "1.4.1",
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

    g_cvRankEnabled = CreateConVar("sm_rank_enabled", "1", "1 = Enabled, 0 = Disabled.", _, true, 0.0, true, 1.0);
    g_cvMinPlayers = CreateConVar("sm_rank_min_players", "2", "Minimum real players required for ranked points to count.", _, true, 0.0);

    g_cvStartPoints = CreateConVar("sm_rank_start_points", "1000", "Points a new player starts with.", _, true, 0.0);
    g_cvMinKills = CreateConVar("sm_rank_min_kills", "1", "Minimum kills required to appear in tops / be ranked.", _, true, 0.0);
    g_cvCmdCooldown = CreateConVar("sm_rank_cmd_cooldown", "3.0", "Cooldown (seconds) between rank commands per player.", _, true, 0.0);
    g_cvAutosaveInterval = CreateConVar("sm_rank_autosave_interval", "120.0", "Interval (seconds) between automatic saves. 0 = disabled.", _, true, 0.0);
    g_cvResetCooldownDays = CreateConVar("sm_rank_reset_cooldown_days", "30", "Days a player must wait between rank resets. 0 = no cooldown.", _, true, 0.0);
    g_cvBareTriggers = CreateConVar("sm_rank_bare_triggers", "1", "1 = chat words like 'rank' or 'top' open the stats without an ! or / prefix. 0 = require ! or /.", _, true, 0.0, true, 1.0);

    g_cvKillBase = CreateConVar("sm_rank_kill_base", "2", "Base points for a kill (before point-difference bonus).", _, true, 0.0);
    g_cvKillMin = CreateConVar("sm_rank_kill_min", "1", "Minimum points a kill can grant (after difference bonus, before other bonuses).", _, true, 0.0);
    g_cvKillMax = CreateConVar("sm_rank_kill_max", "15", "Maximum points a kill can grant (after difference bonus, before other bonuses).", _, true, 0.0);
    g_cvDiffStep = CreateConVar("sm_rank_diff_step", "100", "Point difference per +1 kill bonus (killing higher-ranked players is worth more).", _, true, 1.0);
    g_cvDeathMultiplier = CreateConVar("sm_rank_death_multiplier", "1.0", "Multiplier on the killer's earned points to compute the victim's loss.", _, true, 0.0);
    g_cvHeadshotBonus = CreateConVar("sm_rank_headshot_bonus", "1", "Extra points for a headshot kill.", _, true, 0.0);
    g_cvDominationBonus = CreateConVar("sm_rank_domination_bonus", "2", "Extra points for a domination kill (CS:GO).", _, true, 0.0);
    g_cvRevengeBonus = CreateConVar("sm_rank_revenge_bonus", "1", "Extra points for a revenge kill (CS:GO).", _, true, 0.0);
    g_cvKnifeMultiplier = CreateConVar("sm_rank_knife_multiplier", "2.0", "Multiplier applied to the kill points for a knife kill.", _, true, 0.0);
    g_cvTaserBonus = CreateConVar("sm_rank_taser_bonus", "2", "Extra points for a taser/zeus kill (CS:GO).", _, true, 0.0);
    g_cvAssistPoints = CreateConVar("sm_rank_assist_points", "1", "Points for an assist (CS:GO only).", _, true, 0.0);
    g_cvTeamkillPenalty = CreateConVar("sm_rank_teamkill_penalty", "5", "Points lost for a teamkill.", _, true, 0.0);
    g_cvSuicidePenalty = CreateConVar("sm_rank_suicide_penalty", "3", "Points lost for suicide or world damage.", _, true, 0.0);
    g_cvMvpPoints = CreateConVar("sm_rank_mvp_points", "1", "Points for being the round MVP (CS:GO).", _, true, 0.0);
    g_cvBombPlant = CreateConVar("sm_rank_bomb_plant", "2", "Points for planting the bomb.", _, true, 0.0);
    g_cvBombDefuse = CreateConVar("sm_rank_bomb_defuse", "3", "Points for defusing the bomb.", _, true, 0.0);
    g_cvBombExplode = CreateConVar("sm_rank_bomb_explode", "3", "Points for your planted bomb exploding.", _, true, 0.0);
    g_cvHostageRescue = CreateConVar("sm_rank_hostage_rescue", "3", "Points for rescuing a hostage.", _, true, 0.0);
    g_cvTeamWin = CreateConVar("sm_rank_team_win", "1", "Points for each player on the winning team at round end.", _, true, 0.0);
    g_cvTeamLoss = CreateConVar("sm_rank_team_loss", "1", "Points lost for each player on the losing team at round end.", _, true, 0.0);

    AutoExecConfig(true, "umbrella_ranked");

    RegConsoleCmd("sm_rank", Command_Rank);
    RegConsoleCmd("sm_top", Command_Top);
    RegConsoleCmd("sm_toparmas", Command_WeaponMenu);
    RegConsoleCmd("sm_topweapons", Command_WeaponMenu);
    RegConsoleCmd("sm_toptime", Command_TopTime);
    RegConsoleCmd("sm_session", Command_Session);
    RegConsoleCmd("sm_resetrank", Command_ResetRank);
    RegConsoleCmd("sm_rrank", Command_ResetRank);
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);
    HookEvent("bomb_exploded", Event_BombExploded);
    HookEvent("hostage_rescued", Event_HostageRescued);
    HookEvent("round_end", Event_RoundEnd);
    if (g_GameEngine == Engine_CSGO)
    {
        HookEvent("round_mvp", Event_RoundMVP);
    }

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

    if (g_hAutoSaveTimer != null)
    {
        delete g_hAutoSaveTimer;
        g_hAutoSaveTimer = null;
    }

}

// =============================================================================
// UTILIDADES Y SISTEMA ANTI-SPAM
// =============================================================================
void ClearWeaponDeltas(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    for (int i = 0; i < RANK_MAX_WEAPON_DELTAS; i++)
    {
        g_szWeaponDeltaName[client][i][0] = '\0';
        g_iWeaponDeltaKills[client][i] = 0;
    }

    g_iWeaponDeltaCount[client] = 0;
    g_bWeaponFlushInFlight[client] = false;
}

void ResetClientData(int client)
{
    g_iKills[client] = 0;
    g_iDeaths[client] = 0;
    g_iPoints[client] = g_cvStartPoints.IntValue;
    g_iPlayTime[client] = 0;
    g_iSessionStart[client] = GetTime();
    g_iLastReset[client] = 0;
    g_iHeadshots[client] = 0;
    g_iDominations[client] = 0;
    g_iRevenges[client] = 0;
    g_iTeamKills[client] = 0;
    g_iSuicides[client] = 0;
    g_iBombPlants[client] = 0;
    g_iBombDefuses[client] = 0;
    g_iBombExplosions[client] = 0;
    g_iHostagesRescued[client] = 0;
    g_iConnectTime[client] = GetTime();
    g_iSessionPoints[client] = 0;
    g_iSessionKills[client] = 0;
    g_iSessionDeaths[client] = 0;
    g_iSessionHeadshots[client] = 0;
    g_iSessionObjectives[client] = 0;

    g_bDataLoaded[client] = false;
    g_bSaveDirty[client] = false;
    g_iDirtySequence[client] = 0;
    g_iSaveSequence[client] = 0;
    g_fLastCmdTime[client] = 0.0;
    g_bResetInProgress[client] = false;

    ClearWeaponDeltas(client);
}

void MarkClientDirty(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bSaveDirty[client] = true;
    g_iDirtySequence[client]++;

    if (g_iDirtySequence[client] <= 0)
    {
        g_iDirtySequence[client] = 1;
    }
}

int ClampInt(int value, int minValue, int maxValue)
{
    if (value < minValue)
    {
        return minValue;
    }

    if (value > maxValue)
    {
        return maxValue;
    }

    return value;
}

int ApplyPointDelta(int client, int delta)
{
    if (client <= 0 || client > MaxClients)
    {
        return 0;
    }

    int minPoints = RANK_MIN_POINTS;
    int oldPoints = g_iPoints[client];
    g_iPoints[client] += delta;

    if (g_iPoints[client] < minPoints)
    {
        g_iPoints[client] = minPoints;
    }

    int appliedDelta = g_iPoints[client] - oldPoints;
    g_iSessionPoints[client] += appliedDelta;
    return appliedDelta;
}

bool IsKnifeKill(const char[] weapon)
{
    return (StrContains(weapon, "knife", false) != -1 || StrContains(weapon, "bayonet", false) != -1);
}

bool IsTaserKill(const char[] weapon)
{
    return (StrContains(weapon, "taser", false) != -1 || StrContains(weapon, "zeus", false) != -1);
}

int GetRealPlayerCount()
{
    int count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            count++;
        }
    }

    return count;
}

bool IsRankActive()
{
    return (g_cvRankEnabled.BoolValue && GetRealPlayerCount() >= g_cvMinPlayers.IntValue);
}

bool CheckRankAvailability(int client)
{
    if (!g_cvRankEnabled.BoolValue)
    {
        CPrintToChat(client, "%t", "Rank Disabled");
        return false;
    }

    int currentPlayers = GetRealPlayerCount();
    int minPlayers = g_cvMinPlayers.IntValue;
    if (currentPlayers < minPlayers)
    {
        CPrintToChat(client, "%t", "Rank Not Enough Players", currentPlayers, minPlayers);
        return false;
    }

    return true;
}

int CalculateKillPoints(int attacker, int victim, bool headshot, bool dominated, bool revenge, const char[] weapon)
{
    int diffStep = g_cvDiffStep.IntValue;
    if (diffStep < 1)
    {
        diffStep = 1;
    }

    int diffBonus = (g_iPoints[victim] - g_iPoints[attacker]) / diffStep;
    int points = g_cvKillBase.IntValue + diffBonus;

    points = ClampInt(points, g_cvKillMin.IntValue, g_cvKillMax.IntValue);

    if (headshot)
    {
        points += g_cvHeadshotBonus.IntValue;
    }

    if (dominated)
    {
        points += g_cvDominationBonus.IntValue;
    }

    if (revenge)
    {
        points += g_cvRevengeBonus.IntValue;
    }

    if (IsTaserKill(weapon))
    {
        points += g_cvTaserBonus.IntValue;
    }

    if (IsKnifeKill(weapon))
    {
        points = RoundToCeil(float(points) * g_cvKnifeMultiplier.FloatValue);
    }

    return points;
}

void FormatSignedInt(int value, char[] buffer, int maxlen)
{
    if (value > 0)
    {
        Format(buffer, maxlen, "+%d", value);
        return;
    }

    Format(buffer, maxlen, "%d", value);
}

bool IsValidRankClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && g_bDataLoaded[client] && !g_bResetInProgress[client]);
}

void GetPointRankName(int points, char[] buffer, int maxlen)
{
    if (points >= 5000)
    {
        strcopy(buffer, maxlen, "Challenger");
    }
    else if (points >= 3000)
    {
        strcopy(buffer, maxlen, "Grand Master");
    }
    else if (points >= 2500)
    {
        strcopy(buffer, maxlen, "Master");
    }
    else if (points >= 2000)
    {
        strcopy(buffer, maxlen, "Diamond");
    }
    else if (points >= 1600)
    {
        strcopy(buffer, maxlen, "Platinum");
    }
    else if (points >= 1300)
    {
        strcopy(buffer, maxlen, "Gold");
    }
    else if (points >= 1000)
    {
        strcopy(buffer, maxlen, "Silver");
    }
    else
    {
        strcopy(buffer, maxlen, "Bronze");
    }
}

bool CheckCooldown(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return true;
    }

    float currentTime = GetEngineTime();
    float cooldown = g_cvCmdCooldown.FloatValue;
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
    if (g_cvBareTriggers.BoolValue && StrEqual(text, trigger, false))
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
    ReplaceString(name, maxlen, "{", "(");
    ReplaceString(name, maxlen, "}", ")");
}

void GetSafeClientName(int client, char[] name, int maxlen)
{
    if (!GetClientName(client, name, maxlen))
    {
        strcopy(name, maxlen, "Unknown");
    }

    SanitizePlayerName(name, maxlen);
}

bool IsSameClientAuth(int client, const char[] auth)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    char currentAuth[32];
    if (!GetClientSteam2Safe(client, currentAuth, sizeof(currentAuth)))
    {
        return false;
    }

    return StrEqual(currentAuth, auth);
}

bool EscapeSqlString(Database db, const char[] input, char[] output, int maxlen, const char[] context = "value")
{
    if (db == null)
    {
        return false;
    }

    if (db.Escape(input, output, maxlen))
    {
        return true;
    }

    output[0] = '\0';
    LogError("[Umbrella Ranked] SQL escape failed for %s. Input length: %d, buffer: %d.", context, strlen(input), maxlen);
    return false;
}

void GetTop1SoundPath(char[] sample, int sampleLen, char[] download, int downloadLen)
{
    strcopy(sample, sampleLen, RANK_TOP1_SOUND);
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

    if (g_bWeaponFlushInFlight[client])
    {
        if (showMessages)
        {
            CPrintToChat(client, "%t", "Data Loading");
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

    char auth[32], escAuth[64], deleteQuery[256], saveQuery[8192];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return;
    }

    if (!EscapeSqlString(g_hDatabase, auth, escAuth, sizeof(escAuth), "reset steamid"))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return;
    }
    UpdateSessionPlayTime(client);

    char name[64], escName[128];
    GetSafeClientName(client, name, sizeof(name));
    if (!EscapeSqlString(g_hDatabase, name, escName, sizeof(escName), "reset name"))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return;
    }

    int resetTime = GetTime();
    int startPoints = g_cvStartPoints.IntValue;
    int resetPoints = (g_iPoints[client] < startPoints) ? g_iPoints[client] : startPoints;
    int resetSeq = ++g_iSaveSequence[client];

    if (StrEqual(g_szDriver, "sqlite"))
    {
        Format(saveQuery, sizeof(saveQuery),
            "INSERT INTO player_stats (steamid, name, kills, deaths, points, playtime, last_seen, last_reset, save_seq, headshots, dominations, revenges, teamkills, suicides, bomb_plants, bomb_defuses, bomb_explosions, hostages_rescued) VALUES ('%s', '%s', 0, 0, %d, %d, %d, %d, %d, 0, 0, 0, 0, 0, 0, 0, 0, 0) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, kills = 0, deaths = 0, points = excluded.points, playtime = excluded.playtime, last_seen = excluded.last_seen, last_reset = excluded.last_reset, save_seq = excluded.save_seq, headshots = 0, dominations = 0, revenges = 0, teamkills = 0, suicides = 0, bomb_plants = 0, bomb_defuses = 0, bomb_explosions = 0, hostages_rescued = 0 WHERE excluded.last_seen > player_stats.last_seen OR (excluded.last_seen = player_stats.last_seen AND excluded.save_seq >= player_stats.save_seq)",
            escAuth, escName, resetPoints, g_iPlayTime[client], resetTime, resetTime, resetSeq
        );
    }
    else
    {
        Format(saveQuery, sizeof(saveQuery),
            "INSERT INTO player_stats (steamid, name, kills, deaths, points, playtime, last_seen, last_reset, save_seq, headshots, dominations, revenges, teamkills, suicides, bomb_plants, bomb_defuses, bomb_explosions, hostages_rescued) VALUES ('%s', '%s', 0, 0, %d, %d, %d, %d, %d, 0, 0, 0, 0, 0, 0, 0, 0, 0) ON DUPLICATE KEY UPDATE name=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(name), name), kills=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, kills), deaths=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, deaths), points=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(points), points), playtime=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(playtime), playtime), last_reset=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(last_reset), last_reset), headshots=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, headshots), dominations=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, dominations), revenges=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, revenges), teamkills=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, teamkills), suicides=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, suicides), bomb_plants=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, bomb_plants), bomb_defuses=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, bomb_defuses), bomb_explosions=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, bomb_explosions), hostages_rescued=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), 0, hostages_rescued), save_seq=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(save_seq), save_seq), last_seen=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(last_seen), last_seen)",
            escAuth, escName, resetPoints, g_iPlayTime[client], resetTime, resetTime, resetSeq
        );
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(resetTime);
    pack.WriteCell(resetPoints);
    pack.WriteCell(resetSeq);

    g_bResetInProgress[client] = true;

    Format(deleteQuery, sizeof(deleteQuery), "DELETE FROM weapon_stats WHERE steamid = '%s'", escAuth);

    Transaction txn = SQL_CreateTransaction();
    txn.AddQuery(deleteQuery);
    txn.AddQuery(saveQuery);
    g_hDatabase.Execute(txn, SQL_OnResetTransactionSuccess, SQL_OnResetTransactionFailure, pack);
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
    Database.Connect(SQL_OnConnect, RANK_DB_CONNECTION);
}

public void SQL_OnConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Umbrella Ranked] No se pudo conectar a '%s': %s", RANK_DB_CONNECTION, error);
        return;
    }

    SetupDatabase(db);
}

void SetupDatabase(Database db)
{
    g_hDatabase = db;
    g_hDatabase.Driver.GetIdentifier(g_szDriver, sizeof(g_szDriver));

    RunDatabaseMigrationStep(0);
}

bool IsExpectedSchemaError(const char[] error)
{
    if (error[0] == '\0')
    {
        return false;
    }

    if (StrContains(error, "duplicate", false) != -1 || StrContains(error, "exists", false) != -1 || StrContains(error, "already exists", false) != -1)
    {
        return true;
    }

    return false;
}

void RunDatabaseMigrationStep(int step)
{
    char query[1024];

    switch (step)
    {
        case 0:
        {
            strcopy(query, sizeof(query), "CREATE TABLE IF NOT EXISTS player_stats (steamid VARCHAR(32) PRIMARY KEY, name VARCHAR(64), kills INT DEFAULT 0, deaths INT DEFAULT 0, points INT DEFAULT 1000, playtime INT DEFAULT 0, last_seen INT DEFAULT 0, last_reset INT DEFAULT 0, save_seq INT DEFAULT 0, headshots INT DEFAULT 0, dominations INT DEFAULT 0, revenges INT DEFAULT 0, teamkills INT DEFAULT 0, suicides INT DEFAULT 0, bomb_plants INT DEFAULT 0, bomb_defuses INT DEFAULT 0, bomb_explosions INT DEFAULT 0, hostages_rescued INT DEFAULT 0)");
        }
        case 1:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN points INT DEFAULT 1000");
        }
        case 2:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN last_seen INT DEFAULT 0");
        }
        case 3:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN last_reset INT DEFAULT 0");
        }
        case 4:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN headshots INT DEFAULT 0");
        }
        case 5:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN dominations INT DEFAULT 0");
        }
        case 6:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN revenges INT DEFAULT 0");
        }
        case 7:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN teamkills INT DEFAULT 0");
        }
        case 8:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN suicides INT DEFAULT 0");
        }
        case 9:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN bomb_plants INT DEFAULT 0");
        }
        case 10:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN bomb_defuses INT DEFAULT 0");
        }
        case 11:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN bomb_explosions INT DEFAULT 0");
        }
        case 12:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN hostages_rescued INT DEFAULT 0");
        }
        case 13:
        {
            strcopy(query, sizeof(query), "CREATE TABLE IF NOT EXISTS weapon_stats (steamid VARCHAR(32), weapon VARCHAR(32), kills INT DEFAULT 0, PRIMARY KEY (steamid, weapon))");
        }
        case 14:
        {
            strcopy(query, sizeof(query), "ALTER TABLE player_stats ADD COLUMN save_seq INT DEFAULT 0");
        }
        case 15:
        {
            strcopy(query, sizeof(query), "CREATE INDEX idx_player_rank ON player_stats (points, kills, deaths, playtime, name)");
        }
        case 16:
        {
            strcopy(query, sizeof(query), "CREATE INDEX idx_player_playtime ON player_stats (playtime, name)");
        }
        case 17:
        {
            strcopy(query, sizeof(query), "CREATE INDEX idx_weapon_rank ON weapon_stats (weapon, kills)");
        }
        default:
        {
            FinishDatabaseSetup();
            return;
        }
    }

    g_hDatabase.Query(SQL_OnMigrationStep, query, step);
}

public void SQL_OnMigrationStep(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0' && !IsExpectedSchemaError(error))
    {
        SetFailState("[Umbrella Ranked] Database migration failed on step %d: %s", data, error);
        return;
    }

    RunDatabaseMigrationStep(data + 1);
}

void FinishDatabaseSetup()
{
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
    if (error[0] == '\0')
    {
        return;
    }

    LogError("[Umbrella DB Error] %s", error);
}

DataPack CreateClientSavePack(int userid, const char[] auth, int dirtySequence, const char[] query, int retryCount)
{
    DataPack pack = new DataPack();
    pack.WriteCell(userid);
    pack.WriteString(auth);
    pack.WriteCell(dirtySequence);
    pack.WriteCell(retryCount);
    pack.WriteString(query);
    return pack;
}

void RestoreClientDirtyFromSaveFailure(int client, const char[] auth, int dirtySequence)
{
    if (!IsSameClientAuth(client, auth))
    {
        return;
    }

    g_bSaveDirty[client] = true;
    if (g_iDirtySequence[client] < dirtySequence)
    {
        g_iDirtySequence[client] = dirtySequence;
    }
}

void ScheduleClientSaveRetry(int userid, const char[] auth, int dirtySequence, const char[] query, int retryCount)
{
    DataPack retry = CreateClientSavePack(userid, auth, dirtySequence, query, retryCount);
    CreateTimer(RANK_DB_RETRY_DELAY, Timer_RetryClientSave, retry);
}

public Action Timer_RetryClientSave(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        return Plugin_Stop;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    char auth[32];
    pack.ReadString(auth, sizeof(auth));
    int dirtySequence = pack.ReadCell();
    int retryCount = pack.ReadCell();
    char query[8192];
    pack.ReadString(query, sizeof(query));

    if (g_hDatabase == null)
    {
        int client = GetClientOfUserId(userid);
        RestoreClientDirtyFromSaveFailure(client, auth, dirtySequence);

        delete pack;
        if (retryCount < RANK_DB_MAX_RETRIES)
        {
            ScheduleClientSaveRetry(userid, auth, dirtySequence, query, retryCount + 1);
        }
        else
        {
            LogError("[Umbrella Ranked] Save retry exhausted for %s because database is disconnected.", auth);
        }

        return Plugin_Stop;
    }

    g_hDatabase.Query(SQL_OnClientDataSaved, query, pack);
    return Plugin_Stop;
}

public void SQL_OnClientDataSaved(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        LogError("[Umbrella Ranked] Save callback without context data.");
        return;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    char auth[32];
    pack.ReadString(auth, sizeof(auth));
    int dirtySequence = pack.ReadCell();
    int retryCount = pack.ReadCell();
    char query[8192];
    pack.ReadString(query, sizeof(query));
    delete pack;

    int client = GetClientOfUserId(userid);

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error saving player data for %s: %s", auth, error);
        RestoreClientDirtyFromSaveFailure(client, auth, dirtySequence);

        if (retryCount < RANK_DB_MAX_RETRIES)
        {
            ScheduleClientSaveRetry(userid, auth, dirtySequence, query, retryCount + 1);
        }
        else
        {
            LogError("[Umbrella Ranked] Save retry exhausted for %s.", auth);
        }

        return;
    }

    if (IsSameClientAuth(client, auth) && g_iDirtySequence[client] == dirtySequence)
    {
        g_bSaveDirty[client] = false;
    }
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

    if (!EscapeSqlString(g_hDatabase, auth, escAuth, sizeof(escAuth), "load steamid"))
    {
        return;
    }

    char query[768];
    Format(query, sizeof(query), "SELECT kills, deaths, points, playtime, last_reset, headshots, dominations, revenges, teamkills, suicides, bomb_plants, bomb_defuses, bomb_explosions, hostages_rescued FROM player_stats WHERE steamid = '%s'", escAuth);
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

    if (!EscapeSqlString(g_hDatabase, auth, escAuth, sizeof(escAuth), "save steamid"))
    {
        return;
    }

    char name[64], escName[128], query[8192];
    int lastSeen = GetTime();
    int lastReset = g_iLastReset[client];
    int saveSeq = ++g_iSaveSequence[client];

    GetSafeClientName(client, name, sizeof(name));
    if (!EscapeSqlString(g_hDatabase, name, escName, sizeof(escName), "save name"))
    {
        return;
    }

    UpdateSessionPlayTime(client);
    int dirtySequence = g_iDirtySequence[client];

    if (StrEqual(g_szDriver, "sqlite"))
    {
        Format(query, sizeof(query),
            "INSERT INTO player_stats (steamid, name, kills, deaths, points, playtime, last_seen, last_reset, save_seq, headshots, dominations, revenges, teamkills, suicides, bomb_plants, bomb_defuses, bomb_explosions, hostages_rescued) VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d) ON CONFLICT(steamid) DO UPDATE SET name = excluded.name, kills = excluded.kills, deaths = excluded.deaths, points = excluded.points, playtime = excluded.playtime, last_seen = excluded.last_seen, last_reset = excluded.last_reset, save_seq = excluded.save_seq, headshots = excluded.headshots, dominations = excluded.dominations, revenges = excluded.revenges, teamkills = excluded.teamkills, suicides = excluded.suicides, bomb_plants = excluded.bomb_plants, bomb_defuses = excluded.bomb_defuses, bomb_explosions = excluded.bomb_explosions, hostages_rescued = excluded.hostages_rescued WHERE excluded.last_seen > player_stats.last_seen OR (excluded.last_seen = player_stats.last_seen AND excluded.save_seq >= player_stats.save_seq)",
            escAuth, escName, g_iKills[client], g_iDeaths[client], g_iPoints[client], g_iPlayTime[client], lastSeen, lastReset, saveSeq, g_iHeadshots[client], g_iDominations[client], g_iRevenges[client], g_iTeamKills[client], g_iSuicides[client], g_iBombPlants[client], g_iBombDefuses[client], g_iBombExplosions[client], g_iHostagesRescued[client]
        );
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO player_stats (steamid, name, kills, deaths, points, playtime, last_seen, last_reset, save_seq, headshots, dominations, revenges, teamkills, suicides, bomb_plants, bomb_defuses, bomb_explosions, hostages_rescued) VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE name=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(name), name), kills=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(kills), kills), deaths=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(deaths), deaths), points=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(points), points), playtime=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(playtime), playtime), last_reset=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(last_reset), last_reset), headshots=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(headshots), headshots), dominations=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(dominations), dominations), revenges=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(revenges), revenges), teamkills=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(teamkills), teamkills), suicides=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(suicides), suicides), bomb_plants=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(bomb_plants), bomb_plants), bomb_defuses=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(bomb_defuses), bomb_defuses), bomb_explosions=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(bomb_explosions), bomb_explosions), hostages_rescued=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(hostages_rescued), hostages_rescued), save_seq=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(save_seq), save_seq), last_seen=IF(VALUES(last_seen)>last_seen OR (VALUES(last_seen)=last_seen AND VALUES(save_seq)>=save_seq), VALUES(last_seen), last_seen)",
            escAuth, escName, g_iKills[client], g_iDeaths[client], g_iPoints[client], g_iPlayTime[client], lastSeen, lastReset, saveSeq, g_iHeadshots[client], g_iDominations[client], g_iRevenges[client], g_iTeamKills[client], g_iSuicides[client], g_iBombPlants[client], g_iBombDefuses[client], g_iBombExplosions[client], g_iHostagesRescued[client]
        );
    }

    DataPack pack = CreateClientSavePack(GetClientUserId(client), auth, dirtySequence, query, 0);
    g_hDatabase.Query(SQL_OnClientDataSaved, query, pack);
}

void SaveAllClientsData(bool force = false)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && !IsFakeClient(i) && !g_bResetInProgress[i])
        {
            FlushWeaponStats(i);
            SaveClientData(i, force, true);
        }
    }
}

bool AppendQueryPart(char[] query, int maxlen, const char[] part)
{
    if (strlen(query) + strlen(part) >= maxlen)
    {
        return false;
    }

    StrCat(query, maxlen, part);
    return true;
}

void AddWeaponKillDelta(int client, const char[] rawWeapon)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    char weapon[32];
    strcopy(weapon, sizeof(weapon), rawWeapon);
    NormalizeWeaponName(weapon, sizeof(weapon));

    for (int i = 0; i < g_iWeaponDeltaCount[client]; i++)
    {
        if (StrEqual(g_szWeaponDeltaName[client][i], weapon, false))
        {
            g_iWeaponDeltaKills[client][i]++;
            return;
        }
    }

    if (g_iWeaponDeltaCount[client] >= RANK_MAX_WEAPON_DELTAS)
    {
        FlushWeaponStats(client);

        if (g_iWeaponDeltaCount[client] >= RANK_MAX_WEAPON_DELTAS)
        {
            LogError("[Umbrella Ranked] Weapon delta buffer full for client %d. Dropping weapon stat for '%s'.", client, weapon);
            return;
        }
    }

    int index = g_iWeaponDeltaCount[client]++;
    strcopy(g_szWeaponDeltaName[client][index], sizeof(g_szWeaponDeltaName[][]), weapon);
    g_iWeaponDeltaKills[client][index] = 1;
}

void SubtractWeaponDelta(int client, const char[] weapon, int kills)
{
    if (client <= 0 || client > MaxClients || kills <= 0)
    {
        return;
    }

    for (int i = 0; i < g_iWeaponDeltaCount[client]; i++)
    {
        if (!StrEqual(g_szWeaponDeltaName[client][i], weapon, false))
        {
            continue;
        }

        g_iWeaponDeltaKills[client][i] -= kills;
        if (g_iWeaponDeltaKills[client][i] > 0)
        {
            return;
        }

        int last = g_iWeaponDeltaCount[client] - 1;
        if (i != last)
        {
            strcopy(g_szWeaponDeltaName[client][i], sizeof(g_szWeaponDeltaName[][]), g_szWeaponDeltaName[client][last]);
            g_iWeaponDeltaKills[client][i] = g_iWeaponDeltaKills[client][last];
        }

        g_szWeaponDeltaName[client][last][0] = '\0';
        g_iWeaponDeltaKills[client][last] = 0;
        g_iWeaponDeltaCount[client]--;
        return;
    }
}

DataPack CreateWeaponFlushPack(int userid, const char[][] weapons, const int[] counts, const char[] auth, int weaponCount, const char[] query, int retryCount)
{
    DataPack pack = new DataPack();
    pack.WriteCell(userid);
    pack.WriteString(auth);
    pack.WriteCell(weaponCount);
    pack.WriteCell(retryCount);

    for (int i = 0; i < weaponCount; i++)
    {
        pack.WriteString(weapons[i]);
        pack.WriteCell(counts[i]);
    }

    pack.WriteString(query);
    return pack;
}

void ScheduleWeaponFlushRetry(int userid, const char[][] weapons, const int[] counts, const char[] auth, int weaponCount, const char[] query, int retryCount)
{
    DataPack retry = CreateWeaponFlushPack(userid, weapons, counts, auth, weaponCount, query, retryCount);
    CreateTimer(RANK_DB_RETRY_DELAY, Timer_RetryWeaponFlush, retry);
}

void FlushWeaponStats(int client)
{
    if (g_hDatabase == null || client <= 0 || client > MaxClients || IsFakeClient(client) || g_iWeaponDeltaCount[client] <= 0 || g_bWeaponFlushInFlight[client])
    {
        return;
    }

    char auth[32], escAuth[64];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        return;
    }
    if (!EscapeSqlString(g_hDatabase, auth, escAuth, sizeof(escAuth), "weapon steamid"))
    {
        return;
    }

    char weapons[RANK_MAX_WEAPON_DELTAS][32];
    int counts[RANK_MAX_WEAPON_DELTAS];
    int weaponCount = 0;
    char query[8192], part[160], escWeapon[64];

    strcopy(query, sizeof(query), "INSERT INTO weapon_stats (steamid, weapon, kills) VALUES ");

    for (int i = 0; i < g_iWeaponDeltaCount[client]; i++)
    {
        if (g_iWeaponDeltaKills[client][i] <= 0)
        {
            continue;
        }

        strcopy(weapons[weaponCount], sizeof(weapons[]), g_szWeaponDeltaName[client][i]);
        counts[weaponCount] = g_iWeaponDeltaKills[client][i];

        if (!EscapeSqlString(g_hDatabase, weapons[weaponCount], escWeapon, sizeof(escWeapon), "weapon name"))
        {
            return;
        }
        Format(part, sizeof(part), "%s('%s', '%s', %d)", (weaponCount == 0) ? "" : ", ", escAuth, escWeapon, counts[weaponCount]);
        if (!AppendQueryPart(query, sizeof(query), part))
        {
            LogError("[Umbrella Ranked] Weapon flush query too large for %s.", auth);
            return;
        }

        weaponCount++;
    }

    if (weaponCount <= 0)
    {
        return;
    }

    if (StrEqual(g_szDriver, "sqlite"))
    {
        if (!AppendQueryPart(query, sizeof(query), " ON CONFLICT(steamid, weapon) DO UPDATE SET kills = kills + excluded.kills"))
        {
            LogError("[Umbrella Ranked] Weapon flush query too large for %s.", auth);
            return;
        }
    }
    else
    {
        if (!AppendQueryPart(query, sizeof(query), " ON DUPLICATE KEY UPDATE kills = kills + VALUES(kills)"))
        {
            LogError("[Umbrella Ranked] Weapon flush query too large for %s.", auth);
            return;
        }
    }

    g_bWeaponFlushInFlight[client] = true;

    DataPack pack = CreateWeaponFlushPack(GetClientUserId(client), weapons, counts, auth, weaponCount, query, 0);
    g_hDatabase.Query(SQL_OnWeaponStatsFlushed, query, pack);
}

public Action Timer_RetryWeaponFlush(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        return Plugin_Stop;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    char auth[32];
    pack.ReadString(auth, sizeof(auth));
    int weaponCount = pack.ReadCell();
    int retryCount = pack.ReadCell();

    char weapons[RANK_MAX_WEAPON_DELTAS][32];
    int counts[RANK_MAX_WEAPON_DELTAS];
    for (int i = 0; i < weaponCount; i++)
    {
        pack.ReadString(weapons[i], sizeof(weapons[]));
        counts[i] = pack.ReadCell();
    }

    char query[8192];
    pack.ReadString(query, sizeof(query));

    if (g_hDatabase == null)
    {
        delete pack;

        if (retryCount < RANK_DB_MAX_RETRIES)
        {
            ScheduleWeaponFlushRetry(userid, weapons, counts, auth, weaponCount, query, retryCount + 1);
        }
        else
        {
            int client = GetClientOfUserId(userid);
            if (IsSameClientAuth(client, auth))
            {
                g_bWeaponFlushInFlight[client] = false;
            }

            LogError("[Umbrella Ranked] Weapon flush retry exhausted for %s because database is disconnected.", auth);
        }

        return Plugin_Stop;
    }

    g_hDatabase.Query(SQL_OnWeaponStatsFlushed, query, pack);
    return Plugin_Stop;
}

public void SQL_OnWeaponStatsFlushed(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        LogError("[Umbrella Ranked] Weapon flush callback without context data.");
        return;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    char auth[32];
    pack.ReadString(auth, sizeof(auth));
    int weaponCount = pack.ReadCell();
    int retryCount = pack.ReadCell();

    char weapons[RANK_MAX_WEAPON_DELTAS][32];
    int counts[RANK_MAX_WEAPON_DELTAS];

    for (int i = 0; i < weaponCount; i++)
    {
        pack.ReadString(weapons[i], sizeof(weapons[]));
        counts[i] = pack.ReadCell();
    }

    char query[8192];
    pack.ReadString(query, sizeof(query));
    delete pack;

    int client = GetClientOfUserId(userid);

    if (error[0] != '\0')
    {
        LogError("[Umbrella Ranked] Error saving weapon stats for %s: %s", auth, error);

        if (retryCount < RANK_DB_MAX_RETRIES)
        {
            ScheduleWeaponFlushRetry(userid, weapons, counts, auth, weaponCount, query, retryCount + 1);
            return;
        }

        if (IsSameClientAuth(client, auth))
        {
            g_bWeaponFlushInFlight[client] = false;
        }

        LogError("[Umbrella Ranked] Weapon flush retry exhausted for %s.", auth);
        return;
    }

    if (IsSameClientAuth(client, auth))
    {
        for (int i = 0; i < weaponCount; i++)
        {
            SubtractWeaponDelta(client, weapons[i], counts[i]);
        }

        g_bWeaponFlushInFlight[client] = false;
    }
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

    float interval = g_cvAutosaveInterval.FloatValue;
    if (interval <= 0.0)
    {
        return;
    }

    g_hAutoSaveTimer = CreateTimer(interval, Timer_AutoSave, _, TIMER_REPEAT);
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
            MarkClientDirty(i);
            SaveClientData(i, false, false);
            FlushWeaponStats(i);
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
        g_iPoints[client] = results.FetchInt(2);
        g_iPlayTime[client] = results.FetchInt(3);
        g_iLastReset[client] = results.FetchInt(4);
        g_iHeadshots[client] = results.FetchInt(5);
        g_iDominations[client] = results.FetchInt(6);
        g_iRevenges[client] = results.FetchInt(7);
        g_iTeamKills[client] = results.FetchInt(8);
        g_iSuicides[client] = results.FetchInt(9);
        g_iBombPlants[client] = results.FetchInt(10);
        g_iBombDefuses[client] = results.FetchInt(11);
        g_iBombExplosions[client] = results.FetchInt(12);
        g_iHostagesRescued[client] = results.FetchInt(13);
    }

    g_bDataLoaded[client] = true;
    g_iSessionStart[client] = GetTime();
    g_bSaveDirty[client] = false;

    if (IsRankActive() && g_iKills[client] >= g_cvMinKills.IntValue)
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
        FlushWeaponStats(client);
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
    if (!IsRankActive())
    {
        return Plugin_Continue;
    }

    int atk = GetClientOfUserId(event.GetInt("attacker"));
    int vic = GetClientOfUserId(event.GetInt("userid"));
    bool headshot = event.GetBool("headshot");
    bool csgo = (g_GameEngine == Engine_CSGO);
    bool dominated = (csgo && event.GetInt("dominated") != 0);
    bool revenge = (csgo && event.GetInt("revenge") != 0);
    int assister = csgo ? GetClientOfUserId(event.GetInt("assister")) : 0;

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    bool validAttacker = (atk > 0 && atk <= MaxClients && !IsFakeClient(atk) && g_bDataLoaded[atk] && !g_bResetInProgress[atk]);
    bool validVictim = (vic > 0 && vic <= MaxClients && !IsFakeClient(vic) && g_bDataLoaded[vic] && !g_bResetInProgress[vic]);

    if (!validVictim)
    {
        return Plugin_Continue;
    }

    if (validAttacker && atk != vic)
    {
        bool teamKill = (GetClientTeam(atk) >= 2 && GetClientTeam(atk) == GetClientTeam(vic));

        if (teamKill)
        {
            int penalty = g_cvTeamkillPenalty.IntValue;

            g_iTeamKills[atk]++;
            int appliedPenalty = ApplyPointDelta(atk, -penalty);
            MarkClientDirty(atk);

            g_iDeaths[vic]++;
            g_iSessionDeaths[vic]++;
            MarkClientDirty(vic);

            if (appliedPenalty < 0)
            {
                char victimName[64];
                GetSafeClientName(vic, victimName, sizeof(victimName));
                CPrintToChat(atk, "%t", "Points Teamkill Penalty", -appliedPenalty, victimName, g_iPoints[atk]);
            }

            return Plugin_Continue;
        }

        int points = CalculateKillPoints(atk, vic, headshot, dominated, revenge, weapon);
        int victimLoss = RoundToCeil(float(points) * g_cvDeathMultiplier.FloatValue);

        g_iKills[atk]++;
        g_iSessionKills[atk]++;
        if (headshot)
        {
            g_iHeadshots[atk]++;
            g_iSessionHeadshots[atk]++;
        }
        if (dominated)
        {
            g_iDominations[atk]++;
        }
        if (revenge)
        {
            g_iRevenges[atk]++;
        }
        int appliedGain = ApplyPointDelta(atk, points);
        MarkClientDirty(atk);

        g_iDeaths[vic]++;
        g_iSessionDeaths[vic]++;
        int appliedLoss = ApplyPointDelta(vic, -victimLoss);
        MarkClientDirty(vic);

        AddWeaponKillDelta(atk, weapon);

        if (appliedGain > 0)
        {
            char victimName[64];
            GetSafeClientName(vic, victimName, sizeof(victimName));
            CPrintToChat(atk, "%t", "Points Kill Change", appliedGain, victimName, g_iPoints[atk]);
        }
        if (appliedLoss < 0)
        {
            char attackerName[64];
            GetSafeClientName(atk, attackerName, sizeof(attackerName));
            CPrintToChat(vic, "%t", "Points Death Change", -appliedLoss, attackerName, g_iPoints[vic]);
        }

        bool validAssister = (assister > 0 && assister <= MaxClients && assister != atk && assister != vic && !IsFakeClient(assister) && g_bDataLoaded[assister] && !g_bResetInProgress[assister]);
        if (validAssister && GetClientTeam(assister) != GetClientTeam(vic))
        {
            int appliedAssist = ApplyPointDelta(assister, g_cvAssistPoints.IntValue);
            if (appliedAssist > 0)
            {
                MarkClientDirty(assister);
                char victimAssistName[64];
                GetSafeClientName(vic, victimAssistName, sizeof(victimAssistName));
                CPrintToChat(assister, "%t", "Points Assist", appliedAssist, victimAssistName, g_iPoints[assister]);
            }
        }

        return Plugin_Continue;
    }

    int suicidePenalty = g_cvSuicidePenalty.IntValue;
    g_iDeaths[vic]++;
    g_iSessionDeaths[vic]++;
    g_iSuicides[vic]++;
    int appliedSuicidePenalty = ApplyPointDelta(vic, -suicidePenalty);
    MarkClientDirty(vic);

    if (appliedSuicidePenalty < 0)
    {
        CPrintToChat(vic, "%t", "Points Suicide Penalty", -appliedSuicidePenalty, g_iPoints[vic]);
    }

    return Plugin_Continue;
}

int AwardObjectivePoints(int client, int points)
{
    if (!IsRankActive() || !IsValidRankClient(client))
    {
        return 0;
    }

    int appliedGain = ApplyPointDelta(client, points);
    if (appliedGain <= 0)
    {
        return 0;
    }

    g_iSessionObjectives[client]++;
    MarkClientDirty(client);
    return appliedGain;
}

public Action Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsRankActive() && IsValidRankClient(client))
    {
        g_iBombPlants[client]++;
        int appliedGain = AwardObjectivePoints(client, g_cvBombPlant.IntValue);
        if (appliedGain > 0)
        {
            CPrintToChat(client, "%t", "Objective Bomb Planted", appliedGain, g_iPoints[client]);
        }
    }

    return Plugin_Continue;
}

public Action Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsRankActive() && IsValidRankClient(client))
    {
        g_iBombDefuses[client]++;
        int appliedGain = AwardObjectivePoints(client, g_cvBombDefuse.IntValue);
        if (appliedGain > 0)
        {
            CPrintToChat(client, "%t", "Objective Bomb Defused", appliedGain, g_iPoints[client]);
        }
    }

    return Plugin_Continue;
}

public Action Event_BombExploded(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsRankActive() && IsValidRankClient(client))
    {
        g_iBombExplosions[client]++;
        int appliedGain = AwardObjectivePoints(client, g_cvBombExplode.IntValue);
        if (appliedGain > 0)
        {
            CPrintToChat(client, "%t", "Objective Bomb Exploded", appliedGain, g_iPoints[client]);
        }
    }

    return Plugin_Continue;
}

public Action Event_HostageRescued(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsRankActive() && IsValidRankClient(client))
    {
        g_iHostagesRescued[client]++;
        int appliedGain = AwardObjectivePoints(client, g_cvHostageRescue.IntValue);
        if (appliedGain > 0)
        {
            CPrintToChat(client, "%t", "Objective Hostage Rescued", appliedGain, g_iPoints[client]);
        }
    }

    return Plugin_Continue;
}

public Action Event_RoundMVP(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsRankActive() && IsValidRankClient(client))
    {
        int appliedGain = ApplyPointDelta(client, g_cvMvpPoints.IntValue);
        if (appliedGain > 0)
        {
            MarkClientDirty(client);
            CPrintToChat(client, "%t", "Points MVP", appliedGain, g_iPoints[client]);
        }
    }

    return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRankActive())
    {
        return Plugin_Continue;
    }

    int winner = event.GetInt("winner");
    if (winner != 2 && winner != 3)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidRankClient(i))
        {
            continue;
        }

        int team = GetClientTeam(i);
        if (team == winner)
        {
            ApplyPointDelta(i, g_cvTeamWin.IntValue);
            MarkClientDirty(i);
        }
        else if (team >= 2)
        {
            ApplyPointDelta(i, -g_cvTeamLoss.IntValue);
            MarkClientDirty(i);
        }
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

public void SQL_OnResetTransactionFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        LogError("[Umbrella Ranked] Reset failure callback without context data.");
        return;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client != 0 && IsClientInGame(client))
    {
        g_bResetInProgress[client] = false;
        CPrintToChat(client, "%t", "Reset Rank Error");
    }

    LogError("[Umbrella Ranked] Reset transaction failed for userid %d on query %d/%d: %s", userid, failIndex, numQueries, error);
}

public void SQL_OnResetTransactionSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    if (pack == null)
    {
        LogError("[Umbrella Ranked] Reset success callback without context data.");
        return;
    }

    pack.Reset();

    int userid = pack.ReadCell();
    int resetTime = pack.ReadCell();
    int resetPoints = pack.ReadCell();
    int resetSeq = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    g_bResetInProgress[client] = false;

    g_iKills[client] = 0;
    g_iDeaths[client] = 0;
    g_iPoints[client] = resetPoints;
    g_iLastReset[client] = resetTime;
    g_iSaveSequence[client] = resetSeq;
    g_iHeadshots[client] = 0;
    g_iDominations[client] = 0;
    g_iRevenges[client] = 0;
    g_iTeamKills[client] = 0;
    g_iSuicides[client] = 0;
    g_iBombPlants[client] = 0;
    g_iBombDefuses[client] = 0;
    g_iBombExplosions[client] = 0;
    g_iHostagesRescued[client] = 0;
    g_iSessionPoints[client] = 0;
    g_iSessionKills[client] = 0;
    g_iSessionDeaths[client] = 0;
    g_iSessionHeadshots[client] = 0;
    g_iSessionObjectives[client] = 0;
    g_iSessionStart[client] = GetTime();
    g_bSaveDirty[client] = false;
    g_iDirtySequence[client] = 0;
    ClearWeaponDeltas(client);

    CPrintToChat(client, "%t", "Reset Rank Success");
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

    if (!CheckRankAvailability(client))
    {
        return Plugin_Handled;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    MarkClientDirty(client);
    SaveClientData(client, true, false);

    char auth[32], escAuth[64], query[1024];
    if (!GetClientSteam2Safe(client, auth, sizeof(auth)))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    if (!EscapeSqlString(g_hDatabase, auth, escAuth, sizeof(escAuth), "rank steamid"))
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    Format(query, sizeof(query),
        "SELECT CASE WHEN me.kills >= %d THEN 1 + (SELECT COUNT(*) FROM player_stats other WHERE other.kills >= %d AND (other.points > me.points OR (other.points = me.points AND (other.kills > me.kills OR (other.kills = me.kills AND (other.deaths < me.deaths OR (other.deaths = me.deaths AND (other.playtime > me.playtime OR (other.playtime = me.playtime AND other.name < me.name))))))))) ELSE 0 END AS rank_pos FROM player_stats me WHERE me.steamid = '%s' LIMIT 1",
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

    char timeStr[32], rankName[32], buffer[256];
    FormatPlayTime(client, g_iPlayTime[client], timeStr, sizeof(timeStr));
    GetPointRankName(g_iPoints[client], rankName, sizeof(rankName));

    int pos = 0;
    if (results != null && results.FetchRow())
    {
        pos = results.FetchInt(0);
    }

    if (pos > 0)
    {
        Format(buffer, sizeof(buffer), "%T", "Rank Message", client, pos, rankName, g_iPoints[client], g_iKills[client], g_iDeaths[client], kdr, g_iHeadshots[client], timeStr);
    }
    else
    {
        Format(buffer, sizeof(buffer), "%T", "Not Ranked", client, rankName, g_iPoints[client], g_iKills[client], g_iDeaths[client], kdr, g_iHeadshots[client], timeStr);
    }

    CPrintToChat(client, "%s", buffer);
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

    if (!CheckRankAvailability(client))
    {
        return Plugin_Handled;
    }

    if (g_hDatabase == null || !g_bDataLoaded[client])
    {
        CPrintToChat(client, "%t", "Data Loading");
        return Plugin_Handled;
    }

    char query[512];
    Format(query, sizeof(query),
        "SELECT name, points, kills, deaths, (kills * 1.0 / CASE WHEN deaths = 0 THEN 1 ELSE deaths END) AS kdr FROM player_stats WHERE kills >= %d ORDER BY points DESC, kills DESC, deaths ASC, playtime DESC, name ASC LIMIT 50",
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
        LogError("[Umbrella Ranked] Error cargando top de puntos para %N: %s", client, error);
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

        int points = results.FetchInt(1);
        int kills = results.FetchInt(2);
        float kdr = results.FetchFloat(4);

        if (p == 1)
        {
            Format(entry, sizeof(entry), "%T", "Top Line First", client, n, points, kills, kdr);
        }
        else
        {
            Format(entry, sizeof(entry), "%T", "Top Line Rest", client, p, n, points, kills, kdr);
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

public Action Command_Session(int client, int args)
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

    char pointsDelta[16], timeStr[32], buffer[256];
    FormatSignedInt(g_iSessionPoints[client], pointsDelta, sizeof(pointsDelta));
    FormatPlayTime(client, GetTime() - g_iConnectTime[client], timeStr, sizeof(timeStr));

    float kdr = (g_iSessionDeaths[client] > 0) ? float(g_iSessionKills[client]) / float(g_iSessionDeaths[client]) : float(g_iSessionKills[client]);
    Format(buffer, sizeof(buffer), "%T", "Session Message", client, pointsDelta, g_iSessionKills[client], g_iSessionDeaths[client], kdr, g_iSessionHeadshots[client], g_iSessionObjectives[client], timeStr);
    CPrintToChat(client, "%s", buffer);

    return Plugin_Handled;
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

    if (!CheckRankAvailability(client))
    {
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
        if (!EscapeSqlString(g_hDatabase, weapon, escWeapon, sizeof(escWeapon), "weapon menu"))
        {
            return 0;
        }

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
        "SELECT steamid FROM player_stats WHERE kills >= %d ORDER BY points DESC, kills DESC, deaths ASC, playtime DESC, name ASC LIMIT 5",
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
            CPrintToChatAll("%s", buffer);

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
            CPrintToChatAll("%s", buffer);
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

    if (IsChatTriggerMatch(text, "session"))
    {
        Command_Session(client, 0);
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
