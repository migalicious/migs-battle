# V2-06 — Multi-Faction System

## Overview

V1 has exactly two factions: PLAYER and ENEMY. V2 supports up to 4 factions on a single map, each with their own squads, HQ, and AI behavior. Factions can be HOSTILE, NEUTRAL, or ALLIED toward each other.

This is the largest structural change in V2. The existing PLAYER/ENEMY dichotomy is preserved — the player is always Faction 0. Enemy factions are 1, 2, 3.

---

## TerrainDefs Changes

```gdscript
# In TerrainDefs.gd — extend Faction enum
enum Faction {
    NEUTRAL = -1,
    PLAYER  = 0,
    ENEMY_A = 1,
    ENEMY_B = 2,
    ENEMY_C = 3
}

# Faction display names (for UI)
const FACTION_NAMES: Dictionary = {
    -1: "Neutral",
    0:  "Player",
    1:  "Vanguard",   # Default names for enemy factions
    2:  "Iron Pact",
    3:  "Shadow Order"
}

const FACTION_COLORS: Dictionary = {
    -1: Color(0.55, 0.55, 0.55),
    0:  Color(0.20, 0.40, 0.90),
    1:  Color(0.90, 0.20, 0.20),
    2:  Color(0.85, 0.55, 0.10),
    3:  Color(0.55, 0.10, 0.70)
}
```

---

## Faction Relations

### GameState Changes

```gdscript
# Add to GameState.gd
var active_factions: Array[int] = [0, 1]   # Which factions exist on this map
var faction_relations: Dictionary = {}      # Key: sorted pair string "0_1", value: Relation

enum Relation { HOSTILE, NEUTRAL, ALLIED }

func get_relation(f_a: int, f_b: int) -> Relation:
    if f_a == f_b:
        return Relation.ALLIED   # Same faction is always allied with itself
    var key := _relation_key(f_a, f_b)
    return faction_relations.get(key, Relation.HOSTILE)

func set_relation(f_a: int, f_b: int, relation: Relation) -> void:
    faction_relations[_relation_key(f_a, f_b)] = relation
    faction_relation_changed.emit(f_a, f_b, relation)

func are_hostile(f_a: int, f_b: int) -> bool:
    return get_relation(f_a, f_b) == Relation.HOSTILE

func _relation_key(f_a: int, f_b: int) -> String:
    return "%d_%d" % [mini(f_a, f_b), maxi(f_a, f_b)]

signal faction_relation_changed(f_a: int, f_b: int, new_relation: Relation)
```

### Default Relations

At map start, set by `MapConfigScreen` (V2) or hardcoded in V2:

- For a 2-faction map (default): `PLAYER` vs `ENEMY_A` → HOSTILE. All others don't exist.
- For a 3-faction map: `PLAYER` vs `ENEMY_A` → HOSTILE, `PLAYER` vs `ENEMY_B` → HOSTILE, `ENEMY_A` vs `ENEMY_B` → HOSTILE (three-way war).
- For a 4-faction map with one ally: `PLAYER` vs `ENEMY_A` → HOSTILE, `PLAYER` vs `ENEMY_B` → ALLIED (you and ENEMY_B cooperate against ENEMY_A), `ENEMY_B` vs `ENEMY_A` → HOSTILE.

### Relation Presets (map config option)

| Preset | Description |
|--------|-------------|
| Two Factions (V1 mode) | Player vs Enemy A |
| Three-Way War | Player vs A vs B, all hostile |
| Alliance | Player + B allied, vs A |
| Free-for-All | Player vs A vs B vs C, all hostile |

---

## Battle Triggering Changes

In `Squad._on_area_entered()`, replace the binary faction check:

```gdscript
# V1:
if other.faction != faction

# V2:
if GameState.are_hostile(self.faction, other.faction)
```

Same change in `SquadController._on_squads_collided()` — already delegates to `BattleManager` which just checks `squad_a.faction != squad_b.faction`. Update:

```gdscript
# In BattleManager.on_squads_collided():
if not GameState.are_hostile(sq_a.faction, sq_b.faction):
    return   # Allied or neutral factions don't fight
```

---

## Town Capture by Non-Player Factions

Town capture already works faction-agnostically (it stores `faction` as an int). The only change needed is visual:

In `TownNode._faction_color()`:
```gdscript
func _faction_color(f: int) -> Color:
    return TerrainDefs.FACTION_COLORS.get(f, Color.WHITE)
```

---

## Map Generation for Multi-Faction

`MapGenerator` needs to place one HQ per active faction. Update `MapParams`:

```gdscript
# In MapParams.gd
@export var active_factions: Array[int] = [0, 1]   # Which factions are on this map
```

In `MapGenerator._place_towns()`, replace the hardcoded PLAYER/ENEMY HQ placement with a loop:

```gdscript
# HQ placement regions for up to 4 factions (quadrants)
const HQ_REGIONS: Dictionary = {
    0: [0.0,   0.333, 0.667, 1.0  ],   # Player: bottom-left
    1: [0.667, 1.0,   0.0,   0.333],   # Enemy A: top-right
    2: [0.667, 1.0,   0.667, 1.0  ],   # Enemy B: bottom-right
    3: [0.0,   0.333, 0.0,   0.333],   # Enemy C: top-left
}

for faction in params.active_factions:
    var region: Array = HQ_REGIONS.get(faction, [0.4, 0.6, 0.4, 0.6])
    var x0 := int(params.width  * region[0])
    var x1 := int(params.width  * region[1])
    var z0 := int(params.height * region[2])
    var z1 := int(params.height * region[3])
    var hq_pos := _find_in_region(grid, params, x0, x1, z0, z1, placed, 0)
    if hq_pos != Vector2i(-1, -1):
        var hq_id := "%d_hq" % faction
        towns.append({
            "town_id": hq_id,
            "town_type": TerrainDefs.TownType.HQ,
            "faction": faction,
            "grid_x": hq_pos.x,
            "grid_z": hq_pos.y
        })
        placed.append(hq_pos)
```

Update `MapManager.get_hq(faction)` — already uses `town_data.starting_faction == faction`, so it works as-is.

---

## Multi-Faction AI

Each active enemy faction gets its own `AIFaction` node. `AIFaction` needs to know which faction it controls.

### AIFaction Changes

```gdscript
# In AIFaction.gd — add:
@export var controlled_faction: int = TerrainDefs.Faction.ENEMY_A

func _initial_spawn() -> void:
    var spawn_points := _map_manager.get_towns_by_faction(controlled_faction)
    # ... rest unchanged, substitute controlled_faction for TerrainDefs.Faction.ENEMY everywhere

func _assign_objective(squad: Squad) -> Dictionary:
    # Defend OWN HQ
    if _own_hq_under_threat():
        return {type: "defend", target: _map_manager.get_hq(controlled_faction)}
    # Recapture OWN lost towns
    var lost := _find_recently_lost_town(controlled_faction)
    # etc.
```

### Cooperative AI (Allied Factions)

When two non-player factions are ALLIED:
- They don't target each other's towns.
- They may send squads to assist each other when under threat.

```gdscript
# In AIFaction._assign_objective():
# Check if an allied faction's HQ is under threat and we have idle squads
for faction in GameState.active_factions:
    if faction == controlled_faction:
        continue
    if GameState.get_relation(controlled_faction, faction) == GameState.Relation.ALLIED:
        if _faction_hq_under_threat(faction):
            var allied_hq := _map_manager.get_hq(faction)
            if allied_hq:
                return {type: "assist_ally", target: allied_hq}
```

---

## Win Condition Changes

Multi-faction win conditions need updating in `GameState`:

```gdscript
func _check_hq_capture() -> int:
    # Player wins if they capture ALL enemy HQs
    var all_enemy_hqs_captured := true
    for faction in active_factions:
        if faction == TerrainDefs.Faction.PLAYER:
            continue
        if GameState.get_relation(TerrainDefs.Faction.PLAYER, faction) == Relation.ALLIED:
            continue   # Allied faction HQs don't count as targets
        var hq := _get_map_manager().get_hq(faction)
        if not hq:
            continue
        var hq_owner: int = town_ownership.get(hq.town_data.town_id, hq.town_data.starting_faction)
        if hq_owner != TerrainDefs.Faction.PLAYER:
            all_enemy_hqs_captured = false
    if all_enemy_hqs_captured:
        return TerrainDefs.Faction.PLAYER

    # Player loses if their OWN HQ is captured by any hostile faction
    var player_hq := _get_map_manager().get_hq(TerrainDefs.Faction.PLAYER)
    if player_hq:
        var player_hq_owner: int = town_ownership.get(
            player_hq.town_data.town_id, player_hq.town_data.starting_faction)
        if player_hq_owner != TerrainDefs.Faction.PLAYER:
            return player_hq_owner   # Whoever captured player HQ wins

    return -1
```

---

## GameState Squad Tracking

V1 uses `player_squads: Array` and `enemy_squads: Array`. V2 needs per-faction tracking:

```gdscript
# Replace in GameState.gd:
var player_squads: Array = []   # Keep for convenience (faction 0 only)
var enemy_squads: Array = []    # Keep for convenience (all non-player)
var faction_squads: Dictionary = {}   # faction_id -> Array[Squad]

func get_squads_by_faction(faction: int) -> Array:
    return faction_squads.get(faction, [])

func register_squad(sq: Squad) -> void:
    if not faction_squads.has(sq.faction):
        faction_squads[sq.faction] = []
    faction_squads[sq.faction].append(sq)
    # Maintain old arrays for backward compat
    if sq.faction == TerrainDefs.Faction.PLAYER:
        player_squads.append(sq)
    else:
        enemy_squads.append(sq)
```

Update `SquadController.wire_squad()` and `AIFaction._initial_spawn()` to call `GameState.register_squad(sq)`.

---

## Main Scene Changes

For multi-faction maps, instantiate one `AIFaction` node per enemy faction:

```gdscript
# In Main.tscn / a new GameSetupManager:
for faction in GameState.active_factions:
    if faction == TerrainDefs.Faction.PLAYER:
        continue
    var ai := AIFactionScene.instantiate()
    ai.controlled_faction = faction
    add_child(ai)
```

---

## Relation Change Events (Future Hook)

`faction_relation_changed` is already defined. In V3 this can trigger:
- A dialog box announcing a betrayal or alliance shift
- Town color changes on newly-allied towns
- AI squads that were moving toward an ally's HQ to turn back

For V2, just define the signal and stub the connection.
