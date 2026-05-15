# 10 — Win/Loss Conditions and Game Flow

## Victory Conditions

Win conditions are checked by `GameState.check_win_conditions()` after every:
- Town capture completion
- Battle end
- Squad removed from map

The system supports multiple condition types. In V1 the player can select which applies when generating a map (or it defaults to both active simultaneously — win when either is met).

### Condition A — HQ Capture

```gdscript
func check_hq_capture() -> int:
    # Returns winning faction or -1 if no winner yet
    for faction in [Faction.PLAYER, Faction.ENEMY]:
        var enemy_faction = Faction.ENEMY if faction == Faction.PLAYER else Faction.PLAYER
        var enemy_hq = MapManager.get_hq(enemy_faction)
        if GameState.town_ownership[enemy_hq.town_data.town_id] == faction:
            return faction
    return -1
```

### Condition B — All Strongholds

```gdscript
func check_all_strongholds() -> int:
    # A faction wins if it owns ALL towns and castles (not just HQ)
    var all_towns = MapManager.get_towns()
    for faction in [Faction.PLAYER, Faction.ENEMY]:
        var owns_all = all_towns.all(func(t):
            return GameState.town_ownership[t.town_data.town_id] == faction
        )
        if owns_all:
            return faction
    return -1
```

### Checking and Triggering

```gdscript
func check_win_conditions() -> void:
    if phase != Phase.OVERWORLD:
        return
    var winner = -1
    if active_conditions.has("hq_capture"):
        winner = check_hq_capture()
    if winner == -1 and active_conditions.has("all_strongholds"):
        winner = check_all_strongholds()
    if winner != -1:
        trigger_end(winner)

func trigger_end(winning_faction: int) -> void:
    phase = Phase.VICTORY if winning_faction == Faction.PLAYER else Phase.DEFEAT
    get_tree().paused = true
    emit_signal("faction_won", winning_faction)
    # HUD listens and shows VictoryScreen
```

---

## Defeat Conditions

### Player HQ Captured

If `GameState.town_ownership[player_hq_id] == Faction.ENEMY`, the player loses immediately (checked in `check_win_conditions` via the HQ capture check — both factions are checked symmetrically).

### (Future) All Squads Wiped

Not in V1 — if the player loses all squads on the map but still owns towns, they can re-deploy from towns.

---

## Game Flow Diagram

```
[App Start]
     │
     ▼
[Main Menu]  (V1: Skip this, go straight to map generation)
     │
     ▼
[Map Generation]  ─── MapGenerator runs ──► [Map is ready]
     │
     ▼
[Pre-Battle Setup]
  - Player sees map
  - Player's starting squads are placed (hardcoded in V1)
  - AI squads spawned at enemy towns
  - [Start Battle] button
     │
     ▼
[OVERWORLD LOOP] ◄──────────────────────────────────────┐
  - Real-time movement                                   │
  - Player issues move orders                            │
  - AI ticks and issues orders                           │
  - Squads move, capture towns                           │
  - Collision → Battle triggered                         │
     │                                                   │
     ▼                                                   │
[IN_BATTLE]                                             │
  - Overworld paused                                    │
  - BattleResolver runs (instant)                       │
  - BattleScene plays back animation                    │
  - Player clicks Continue                              │
  - BattleResult applied (HP, XP, deaths, retreat)      │
  - Phase returns to OVERWORLD ──────────────────────────┘
     │
     ▼  (win/loss condition met)
[VICTORY or DEFEAT screen]
     │
     ▼
[Play Again → regenerate map] or [Quit]
```

---

## GameState.Phase Enum

```gdscript
enum Phase {
    OVERWORLD,
    IN_BATTLE,
    PAUSED,
    VICTORY,
    DEFEAT
}
```

---

## Pre-Battle Setup (V1 Hardcoded)

Since there's no army builder UI in V1, hardcode the player's starting squads:

```gdscript
# GameState.gd
func create_player_starting_squads() -> Array[SquadData]:
    var squad_a = SquadData.new()
    squad_a.faction = Faction.PLAYER
    # Front row: Knight(L5, leader), Fighter(L3), Fighter(L3)
    # Back row:  Archer(L3), Archer(L3), [empty]
    var knight = UnitRegistry.create_unit("knight", 5)
    knight.is_leader = true; knight.row = 0; knight.col = 0
    var f1 = UnitRegistry.create_unit("fighter", 3)
    f1.row = 0; f1.col = 1
    var f2 = UnitRegistry.create_unit("fighter", 3)
    f2.row = 0; f2.col = 2
    var a1 = UnitRegistry.create_unit("archer", 3)
    a1.row = 1; a1.col = 0
    var a2 = UnitRegistry.create_unit("archer", 3)
    a2.row = 1; a2.col = 1
    squad_a.units = [knight, f1, f2, a1, a2]

    var squad_b = SquadData.new()
    # ... (second squad, mage-focused)
    return [squad_a, squad_b]
```

Both squads start in reserve (not on map). Player deploys them from the player HQ via `TownMenu`.

---

## Play Again

"Play Again" from the victory/defeat screen:
1. Clear all child nodes from `MapManager` and `Squads`.
2. Re-run `MapGenerator` with a new seed.
3. Re-create player and AI squads.
4. Reset `GameState.town_ownership`.
5. Set phase back to `OVERWORLD`.

This allows repeated play without restarting the application.

---

## V2 Game Flow Additions

- Main menu with map size/seed selector
- Save/load game state to disk
- Multiple stages (hand-authored map list with unlock progression)
- Pre-battle army composition screen
- Post-battle debrief with full army status
