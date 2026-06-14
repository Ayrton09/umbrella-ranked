# Umbrella Ranked System

![Version](https://img.shields.io/badge/version-1.4.0-blue)
![Game](https://img.shields.io/badge/game-CS%3AGO%20%2F%20CS%3AS-orange)
![Platform](https://img.shields.io/badge/platform-SourceMod-green)
![Author](https://img.shields.io/badge/author-Ayrton09-purple)
![Database](https://img.shields.io/badge/database-MySQL%20%2F%20SQLite-lightgrey)

<img width="1774" height="887" alt="Umbrella Ranked cover" src="assets/umbrella-ranked-cover.png" />

Umbrella Ranked is a SourceMod ranking plugin for CS:GO and Counter-Strike: Source servers.
It tracks points, rank tiers, kills, deaths, KDR, headshots, playtime, objective rewards, weapon stats, and current-session performance.

## Features

- Points-based ranking with visible rank tiers.
- Kill/death point transfer based on the point difference between attacker and victim.
- Bonuses for headshots, dominations, revenges, knife kills, taser kills, and assists.
- Round rewards: MVP, objectives (bomb/hostage), and team win/loss adjustments.
- Penalties for deaths, teamkills, and suicides.
- Fully configurable scoring through ConVars (no recompile needed to tune values).
- Top players, top playtime, weapon leaderboards, and session stats.
- MySQL and SQLite support through SourceMod DBI.
- Batched weapon stat saves and ordered async player saves.
- Compatible with CS:GO and CS:S (CS:GO-only events such as assist/MVP/taser are skipped on CS:S).

## Installation

Copy the compiled plugin and translations into your server:

```text
addons/sourcemod/plugins/umbrella_rank.smx
addons/sourcemod/translations/umbrella_ranked.phrases.txt
```

Then restart the server or change map.
SourceMod will auto-generate:

```text
cfg/sourcemod/umbrella_ranked.cfg
```

The repository also includes the required MultiColors include files for compiling from source.

## Database

Add the `ranked_db` connection in:

```text
addons/sourcemod/configs/databases.cfg
```

MySQL example:

```text
"ranked_db"
{
    "driver"    "default"
    "host"      "your-db-host"
    "database"  "your-db-name"
    "user"      "your-user"
    "pass"      "your-password"
    "port"      "3306"
}
```

SQLite example:

```text
"ranked_db"
{
    "driver"    "sqlite"
    "database"  "umbrella_stats"
}
```

Database tables and indexes are created or migrated automatically by the plugin.

## CVars

All scoring values are configurable. They are written to `cfg/sourcemod/umbrella_ranked.cfg` on first load, so you can tune the system without recompiling.

### General

| CVar | Default | Description |
| --- | ---: | --- |
| `sm_rank_enabled` | `1` | Enables or disables ranked scoring and rank commands. |
| `sm_rank_min_players` | `2` | Minimum real players required for ranked points to count. |
| `sm_rank_start_points` | `1000` | Points a new player starts with. |
| `sm_rank_min_kills` | `1` | Minimum kills required to appear in tops / be ranked. |
| `sm_rank_cmd_cooldown` | `3.0` | Cooldown (seconds) between rank commands per player. |
| `sm_rank_autosave_interval` | `120.0` | Interval (seconds) between automatic saves. `0` = disabled. |
| `sm_rank_reset_cooldown_days` | `30` | Days a player must wait between rank resets. `0` = no cooldown. |

### Kill formula

| CVar | Default | Description |
| --- | ---: | --- |
| `sm_rank_kill_base` | `2` | Base points for a kill (before the point-difference bonus). |
| `sm_rank_kill_min` | `1` | Minimum points a kill can grant (after difference bonus, before other bonuses). |
| `sm_rank_kill_max` | `15` | Maximum points a kill can grant (after difference bonus, before other bonuses). |
| `sm_rank_diff_step` | `100` | Point difference per `+1` kill bonus (killing higher-ranked players is worth more). |
| `sm_rank_death_multiplier` | `1.0` | Multiplier on the killer's earned points to compute the victim's loss. |
| `sm_rank_knife_multiplier` | `2.0` | Multiplier applied to the kill points for a knife kill. |

### Bonuses and penalties

| CVar | Default | Description |
| --- | ---: | --- |
| `sm_rank_headshot_bonus` | `1` | Extra points for a headshot kill. |
| `sm_rank_domination_bonus` | `2` | Extra points for a domination kill (CS:GO). |
| `sm_rank_revenge_bonus` | `1` | Extra points for a revenge kill (CS:GO). |
| `sm_rank_taser_bonus` | `2` | Extra points for a taser/zeus kill (CS:GO). |
| `sm_rank_assist_points` | `1` | Points for an assist (CS:GO only). |
| `sm_rank_teamkill_penalty` | `5` | Points lost for a teamkill. |
| `sm_rank_suicide_penalty` | `3` | Points lost for suicide or world damage. |
| `sm_rank_mvp_points` | `1` | Points for being the round MVP (CS:GO). |
| `sm_rank_bomb_plant` | `2` | Points for planting the bomb. |
| `sm_rank_bomb_defuse` | `3` | Points for defusing the bomb. |
| `sm_rank_bomb_explode` | `3` | Points for your planted bomb exploding. |
| `sm_rank_hostage_rescue` | `3` | Points for rescuing a hostage. |
| `sm_rank_team_win` | `1` | Points for each player on the winning team at round end. |
| `sm_rank_team_loss` | `1` | Points lost for each player on the losing team at round end. |

`!toptime` stays available even when ranked scoring is disabled.
If the minimum player count is not reached, rank commands show the current player count instead of saying the rank is disabled.

## Commands

| Command | Description |
| --- | --- |
| `!rank` | Shows your rank position, points, tier, KDR, headshots, and playtime. |
| `!top` | Shows the top players by points. |
| `!toptime` | Shows the most active players by playtime. |
| `!session` | Shows current-session points, kills, deaths, KDR, headshots, objectives, and time. |
| `!topweapons` / `!toparmas` | Shows weapon leaderboards. |
| `!resetrank` / `!rrank` | Resets combat stats and weapon stats while keeping playtime. Points only return to the start value (`sm_rank_start_points`) if the player is above it. |

## Point System

New players start with `sm_rank_start_points` points (default `1000`).

Kill points are calculated from the point difference between killer and victim:

```text
kill_points = sm_rank_kill_base + ((victim_points - killer_points) / sm_rank_diff_step)
```

With defaults this is `2 + ((victim_points - killer_points) / 100)`.
The result is clamped between `sm_rank_kill_min` (`1`) and `sm_rank_kill_max` (`15`) before bonuses.
This means killing stronger players gives more points, killing weaker players gives fewer points, and dying to a weaker player removes more points.

When you die, you lose the killer's earned kill points multiplied by `sm_rank_death_multiplier` (default `1.0`).

Bonuses and penalties (all configurable, see the CVars section):

| Event | Points | CVar |
| --- | ---: | --- |
| Headshot | `+1` | `sm_rank_headshot_bonus` |
| Domination (CS:GO) | `+2` | `sm_rank_domination_bonus` |
| Revenge (CS:GO) | `+1` | `sm_rank_revenge_bonus` |
| Knife kill | `x2` | `sm_rank_knife_multiplier` |
| Taser kill (CS:GO) | `+2` | `sm_rank_taser_bonus` |
| Assist (CS:GO) | `+1` | `sm_rank_assist_points` |
| Teamkill | `-5` | `sm_rank_teamkill_penalty` |
| Suicide/world damage | `-3` | `sm_rank_suicide_penalty` |
| Round MVP (CS:GO) | `+1` | `sm_rank_mvp_points` |
| Bomb planted | `+2` | `sm_rank_bomb_plant` |
| Bomb defused | `+3` | `sm_rank_bomb_defuse` |
| Bomb exploded | `+3` | `sm_rank_bomb_explode` |
| Hostage rescued | `+3` | `sm_rank_hostage_rescue` |
| Team win (each player) | `+1` | `sm_rank_team_win` |
| Team loss (each player) | `-1` | `sm_rank_team_loss` |

## Rank Tiers

| Tier | Points |
| --- | ---: |
| Bronze | `< 1000` |
| Silver | `1000+` |
| Gold | `1300+` |
| Platinum | `1600+` |
| Diamond | `2000+` |
| Master | `2500+` |
| Grand Master | `3000+` |
| Challenger | `5000+` |
