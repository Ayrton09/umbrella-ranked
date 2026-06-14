# Changelog

All notable changes to Umbrella Ranked System are documented in this file.

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
