# Umbrella Ranked System

![Version](https://img.shields.io/badge/version-3.0.0-blue)
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
- Bonuses for headshots, dominations, revenges, knife kills, and objectives.
- Penalties for deaths, teamkills, and suicides.
- Top players, top playtime, weapon leaderboards, and session stats.
- MySQL and SQLite support through SourceMod DBI.
- Batched weapon stat saves and ordered async player saves.
- Compatible with CS:GO and CS:S.

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

Only two CVars are exposed:

| CVar | Default | Description |
| --- | ---: | --- |
| `sm_rank_enabled` | `1` | Enables or disables ranked scoring and rank commands. |
| `sm_rank_min_players` | `2` | Minimum real players required for ranked points to count. |

`!toptime` stays available even when ranked scoring is disabled.

## Commands

| Command | Description |
| --- | --- |
| `!rank` | Shows your rank position, points, tier, KDR, headshots, and playtime. |
| `!top` | Shows the top players by points. |
| `!toptime` | Shows the most active players by playtime. |
| `!session` | Shows current-session points, kills, deaths, KDR, headshots, objectives, and time. |
| `!topweapons` / `!toparmas` | Shows weapon leaderboards. |
| `!resetrank` / `!rrank` | Resets combat stats and weapon stats while keeping playtime. Points only return to 1000 if the player is above 1000. |

## Point System

New players start with `1000` points.

Kill points are calculated from the point difference:

```text
kill_points = 2 + ((victim_points - killer_points) / 100)
```

The result is clamped between `1` and `15` before bonuses.
This means killing stronger players gives more points, killing weaker players gives fewer points, and dying to a weaker player removes more points.

Bonuses and penalties:

| Event | Points |
| --- | ---: |
| Headshot | `+1` |
| Domination | `+2` |
| Revenge | `+1` |
| Knife kill | `x2` |
| Teamkill | `-3` |
| Suicide/world damage | `-2` |
| Bomb planted | `+3` |
| Bomb defused | `+5` |
| Bomb exploded | `+4` |
| Hostage rescued | `+2` |

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
