# Changelog

All notable changes to Umbrella Ranked System are documented in this file.

## [1.5.0]

### Fixed
- The database connection is retried every 30 seconds if it fails at startup, instead of leaving the plugin without a database until the next reload.
- Failed player data loads are retried (up to 3 times, 5 seconds apart), instead of leaving the player unranked and unsaved for the whole session.
- Saves and weapon stat flushes are blocked while a rank reset is in progress. Previously `!rank` could force a save mid-reset and the reset could be silently skipped in the database while weapon stats were already deleted.
- Weapon stat batches are no longer retried after a query error. The additive upsert is not idempotent, so a retry could double-count kills when the database reported an error for a query that was actually applied. A failed batch now loses at most the kills accumulated since the previous flush and is logged.
- Weapon kills accumulated while a previous flush was still in flight are no longer lost when the player disconnects.
- Players already connected when the plugin loads get their session data initialized (`!session` showed a playtime measured from 1970).
- The top-5 welcome announcement can no longer fire twice for the same player when two data loads race during connect.
- SQLite index creation uses `CREATE INDEX IF NOT EXISTS` instead of relying on matching the error message text.

### Changed
- Rank commands used from the server console print an "in-game only" notice instead of doing nothing.
- The periodic autosave force-saves players directly instead of artificially marking them dirty first.
- The five rank commands share one precondition gate (in-game check, cooldown, availability, data loaded) instead of five hand-maintained copies.
- Removed the dirty-flag save bookkeeping: every save path already forces a write, so the flag no longer influenced behavior.

## [1.4.1]

### Added
- `sm_rank_bare_triggers` ConVar (default `1`): chat words like `rank` or `top` open the stats without an `!`/`/` prefix. Set to `0` to require a prefix.

### Changed
- Chat triggers respond to plain words again by default (e.g. `top`, `rank`), now toggleable via the ConVar above. The `!` and `/` prefixes always work.

## [1.4.0]

### Added
- **Taser/Zeus kill bonus** (`+2`, additive, CS:GO only).
- **Assist points** (`+1`, awarded to the rival-team assister, CS:GO only).
- **Round MVP reward** (`+1`, CS:GO only).
- **Team win reward** (`+1` to each player on the winning team at round end).
- **Team loss penalty** (`-1` to each player on the losing team at round end).
- **Full ConVar configuration**: every scoring value and timing is now exposed as a ConVar (27 total), written to `cfg/sourcemod/umbrella_ranked.cfg`. Values can be tuned without recompiling.
- New translation phrases `Points Assist` and `Points MVP` in all five languages (en/es/pt/ru/chi).

### Changed
- Adjusted point values: teamkill `-3 → -5`, suicide/world `-2 → -3`, bomb planted `+3 → +2`, bomb defused `+5 → +3`, bomb exploded `+4 → +3`, hostage rescued `+2 → +3`.
- Autosave interval is now configurable (`sm_rank_autosave_interval`, `0` disables it) and applies the value loaded from the config.
- Plugin version `3.0.0 → 1.4.0`.

> The kill formula is unchanged: point-difference scaling (clamped 1–15), headshot (+1), domination (+2), revenge (+1), knife multiplier (x2.0), and the victim losing the killer's earned points.

### Fixed
- Chat triggers (`rank`, `top`, `session`, etc.) no longer swallow normal chat messages — they only respond to the `!` and `/` prefixes.
- Increased the weapon-stats flush buffer (`4096 → 8192`) to prevent data loss when a player accumulates many distinct weapons.
- CS:GO-only `player_death` event keys (`dominated`, `revenge`, `assister`) are now read only on CS:GO.
- Added a divide-by-zero guard for `sm_rank_diff_step`.

### Defaults
All ConVar defaults match the previous behavior, so upgrading changes nothing until the config is edited.
