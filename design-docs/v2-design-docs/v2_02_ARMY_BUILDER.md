# V2-02 — Army Builder

## Overview

Currently the player's starting squads are hardcoded in `SquadController._build_player_squad()`. V2 adds a pre-battle army builder screen where the player configures their squads before the map starts. This is one of the highest-impact features — it gives the player strategic identity and replayability.

The army builder appears **after** the map is generated (so the player can see what they're getting into) but **before** squads are placed on the map.

---

## Game Flow Change

**V1 flow**:
```
TitleScreen → Main.tscn (map generates immediately, hardcoded squads spawn)
```

**V2 flow**:
```
TitleScreen → MapConfigScreen → [map generates] → ArmyBuilderScreen → Main.tscn (squads from builder)
```

The `MapConfigScreen` is covered in `v2_07_MAP_CONFIG_AND_SEED_UI.md`. This document covers `ArmyBuilderScreen`.

---

## Army Pool

The player has a **roster** of available units — a fixed pool of individuals they own. This pool starts with a set of units based on difficulty/scenario and grows as units gain XP and promote.

For V2, the starting pool is defined in a new `ScenarioData` resource (see below). It replaces the hardcoded `_build_player_squad()` calls.

### ScenarioData Resource

```gdscript
class_name ScenarioData
extends Resource

@export var scenario_name: String = "Tutorial"
@export var starting_units: Array[Dictionary] = []
# Each dict: {"class_id": String, "unit_name": String, "level": int}

@export var max_squads: int = 3        # Max squads player can field simultaneously
@export var max_reserve_squads: int = 5  # Max squads in reserve (total pool / 6 slots each)
```

**V2 starter scenario** (hardcoded `ScenarioData` resource, replaces `_build_player_squad()`):
```
Starting units (18 total — enough to fill 3 squads of 6):
  Roland       Knight      Lv.5  (leader candidate)
  Gawain       Knight      Lv.4  (leader candidate)
  Sylvia       Archer      Lv.4  (leader candidate)
  Elara        Mage        Lv.4  (leader candidate)
  Marcus       Cavalry     Lv.4  (leader candidate)
  Bors         Fighter     Lv.3
  Aldric       Fighter     Lv.3
  Tristan      Archer      Lv.3
  Isolde       Archer      Lv.3
  Cedric       Fighter     Lv.2
  Petra        Fighter     Lv.2
  Lyra         Mage        Lv.3
  Dara         Fighter     Lv.2
  Finn         Fighter     Lv.2
  Wren         Archer      Lv.2
  Cael         Fighter     Lv.2
  Mira         Fighter     Lv.2
  Oryn         Mage        Lv.2
```

---

## Army Builder Scene

**Scene**: `scenes/ui/ArmyBuilderScreen.tscn`
**Script**: `scripts/ui/ArmyBuilderScreen.gd`

This is a full-screen `CanvasLayer` or `Control` scene.

### Layout

```
┌───────────────────────────────────────────────────────────┐
│  ARMY BUILDER                              [Start Battle] │
├──────────────────────────┬────────────────────────────────┤
│  SQUADS (left panel)     │  ROSTER (right panel)          │
│                          │                                │
│  [Squad 1 ▼]             │  All unassigned units          │
│  ┌──────┬──────┬──────┐  │  listed as clickable rows:     │
│  │      │      │      │  │                                │
│  │ F-0  │ F-1  │ F-2  │  │  [Roland  Knight L5  ★ ]      │
│  │      │      │      │  │  [Gawain  Knight L4  ★ ]      │
│  ├──────┼──────┼──────┤  │  [Sylvia  Archer L4  ★ ]      │
│  │      │      │      │  │  [Bors    Fighter L3    ]      │
│  │ B-0  │ B-1  │ B-2  │  │  [Aldric  Fighter L3    ]      │
│  │      │      │      │  │  ...                           │
│  └──────┴──────┴──────┘  │                                │
│                          │  Click unit → click slot       │
│  [+ New Squad]           │  to assign                     │
│  [Squad 2 ▼]             │                                │
│  ...                     │                                │
│                          │                                │
│  Max squads: 3           │  Drag-drop (V3) / click-to-    │
│  Reserve slots: 5        │  assign (V2)                   │
└──────────────────────────┴────────────────────────────────┘
```

---

## Interaction Model (Click-to-Assign)

1. Player clicks a unit in the **Roster** panel → unit is "selected" (highlight border).
2. Player clicks an empty slot in the **Squad grid** → unit is placed there.
3. Player can click an occupied slot to **remove** the unit back to the roster.
4. Player can click a **different squad tab** to switch which squad they're configuring.
5. **Leader designation**: First unit placed in a squad that `can_lead = true` is automatically the leader. Player can click a non-leader `can_lead` unit and click a "Set as Leader" button that appears.
6. Validation: "Start Battle" is disabled if no squad has a valid leader.

---

## Squad Tab Management

- Up to `ScenarioData.max_squads` squads can be configured (default 3).
- Player clicks "[+ New Squad]" to add another squad tab (up to the max).
- Each tab shows the squad's grid (6 slots, 3×2). Empty slots are valid.
- Squads with 0 units cannot be deployed (greyed out in tab).
- The first squad is always deployed at game start; others go to reserve.

---

## Validation Rules

| Rule | Error message |
|------|--------------|
| No squad has a leader | "Squad [N] has no leader. Assign a unit with leadership." |
| Squad has units but no leader-capable unit | Same as above |
| More than `max_reserve_squads` squads configured | Disable "+ New Squad" button |
| Zero squads configured | Disable "Start Battle" |

Show validation errors as a small red label below the Start button, not a popup.

---

## ArmyBuilderScreen Script Outline

```gdscript
class_name ArmyBuilderScreen
extends Control

signal army_ready(squads: Array[SquadData])

var _scenario: ScenarioData = null
var _all_units: Array[UnitData] = []    # Full roster
var _unassigned: Array[UnitData] = []   # Not in any squad
var _squads: Array[SquadData] = []      # Configured squads
var _selected_unit: UnitData = null     # Waiting to be placed
var _active_squad_idx: int = 0

func setup(scenario: ScenarioData) -> void:
    _scenario = scenario
    _all_units = _build_unit_pool(scenario)
    _unassigned = _all_units.duplicate()
    _squads = []
    _add_squad()   # Start with one empty squad

func _build_unit_pool(scenario: ScenarioData) -> Array[UnitData]:
    var pool: Array[UnitData] = []
    for entry in scenario.starting_units:
        var unit := UnitRegistry.create_unit(entry["class_id"], entry["level"])
        unit.unit_name = entry["unit_name"]
        pool.append(unit)
    return pool

func _on_start_pressed() -> void:
    if not _validate():
        return
    army_ready.emit(_squads)

func _validate() -> bool:
    for sq in _squads:
        if sq.units.is_empty():
            continue
        if not sq.get_leader():
            _show_error("A squad has no leader!")
            return false
    return true
```

---

## Integration with Main.tscn

`ArmyBuilderScreen` is instantiated by the `TitleScreen` (or a new `GameSetupManager` node) after map generation. When `army_ready` fires, the receiving scene:

1. Stores the `Array[SquadData]` in `GameState.configured_squads` (new field).
2. Transitions to `Main.tscn`.
3. `SquadController._spawn_player_squads()` reads from `GameState.configured_squads` instead of calling `_build_player_squad()`.

### GameState change:
```gdscript
# Add to GameState.gd
var configured_squads: Array[SquadData] = []
```

### SquadController change:
```gdscript
func _spawn_player_squads() -> void:
    var hq := _map_manager.get_hq(TerrainDefs.Faction.PLAYER)
    var base_pos := hq.global_position if hq else Vector3.ZERO

    var squads := GameState.configured_squads
    if squads.is_empty():
        squads = [_build_player_squad(0)]   # Fallback for testing

    # Spawn first squad on map, rest go to reserve
    for i in range(squads.size()):
        var data: SquadData = squads[i]
        data.faction = TerrainDefs.Faction.PLAYER
        if i == 0:
            var sq: Squad = _SQUAD_SCENE.instantiate()
            add_child(sq)
            sq.global_position = Vector3(base_pos.x, 0.5, base_pos.z + 2.5)
            sq.setup(data)
            wire_squad(sq)
            GameState.player_squads.append(sq)
        else:
            GameState.reserve_squads.append(data)
```

---

## Unit Info Tooltip

When the player hovers a unit in the roster, show a tooltip (or side panel update) with:
- Class name, level, HP, STR, AGI, INT, DEF, RES
- Front/back attacks
- Promotion path

Reuse `UnitDetailPopup` logic — it's already written. Just call `_popup.show_unit(unit)` on hover.
