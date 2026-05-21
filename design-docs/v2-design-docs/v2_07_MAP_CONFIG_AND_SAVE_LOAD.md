# V2-07 — Map Config, Seed UI, and Save/Load

## Map Configuration Screen

### Scene
`scenes/ui/MapConfigScreen.tscn` / `scripts/ui/MapConfigScreen.gd`

This screen appears after clicking "New Game" on the title screen, before map generation and the army builder. The player configures:

- **Map Size**: Small (24×24), Medium (32×32), Large (48×48)
- **Seed**: Text field (blank = random; entering a number replays the same map)
- **Number of Towns**: 4–10 (slider)
- **Number of Castles**: 0–4 (slider)
- **Number of Factions**: 2, 3, or 4 (dropdown — connects to v2_06_MULTI_FACTION.md)
- **Faction Preset**: (only shown if factions > 2) Two-Way War / Three-Way War / Alliance
- **Win Condition**: HQ Capture / All Strongholds / Both

```
┌──────────────────────────────────────┐
│         MAP CONFIGURATION            │
├──────────────────────────────────────┤
│  Map Size:      [Medium 32×32 ▼]     │
│  Seed:          [____________]       │
│                 (blank = random)     │
│  Towns:         [●────── 6  ]        │
│  Castles:       [●── 2       ]       │
│  Factions:      [2 ▼]                │
│  Win Condition: [HQ Capture ▼]       │
├──────────────────────────────────────┤
│  Last Seed: 1847392  [Replay ↩]      │
├──────────────────────────────────────┤
│      [Back]          [Generate Map]  │
└──────────────────────────────────────┘
```

### Seed Replay

After any game (win or loss), the `VictoryScreen` shows the seed used:
```
VICTORY!
Map seed: 1847392   [Copy Seed]
```

`GameState.map_seed` already stores the active seed. Add a "Copy Seed" button that calls `DisplayServer.clipboard_set(str(GameState.map_seed))`.

The `MapConfigScreen` stores the last used seed in a simple config file:

```gdscript
const CONFIG_PATH := "user://map_config.cfg"

func _load_last_seed() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(CONFIG_PATH) == OK:
        _last_seed = cfg.get_value("map", "last_seed", 0)
        _seed_field.placeholder_text = "Last: %d" % _last_seed

func _save_last_seed(seed: int) -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("map", "last_seed", seed)
    cfg.save(CONFIG_PATH)
```

"Replay" button fills the seed field with the last used seed.

### Signal Flow

```gdscript
signal config_ready(params: MapParams, win_conditions: Array[String], active_factions: Array[int])

func _on_generate_pressed() -> void:
    var params := MapParams.new()
    params.width  = _size_to_width(_size_option.selected)
    params.height = params.width   # Square maps
    params.map_seed = int(_seed_field.text) if _seed_field.text != "" else 0
    params.num_towns   = int(_towns_slider.value)
    params.num_castles = int(_castles_slider.value)
    var factions := _faction_count_to_array(_faction_option.selected)
    var win_cond := _win_cond_to_array(_win_option.selected)
    _save_last_seed(params.map_seed)
    config_ready.emit(params, win_cond, factions)
```

---

## Flow: TitleScreen → MapConfig → ArmyBuilder → Game

Create a `GameSetupManager` node (child of a `SetupScene.tscn`) that orchestrates the setup sequence:

```gdscript
# GameSetupManager.gd
func _on_title_new_game() -> void:
    _show_map_config()

func _on_config_ready(params, win_cond, factions) -> void:
    _generate_map(params)   # MapGenerator.generate() — store result
    _apply_game_settings(win_cond, factions)
    _show_army_builder()

func _on_army_ready(squads) -> void:
    GameState.configured_squads = squads
    get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
```

---

## Save/Load System

### What to Save

A complete save captures:
- Map seed and params (to regenerate the exact same map)
- `GameState.town_ownership`
- `GameState.player_gold`
- `GameState.active_factions`, `faction_relations`
- All squad data: alive units, HP, XP, level, held items, grid positions
- Which squads are on the map vs. in reserve, and their world positions
- `active_conditions`

### Save Format

Use Godot's `ConfigFile` for simplicity (human-readable, no serialization library needed):

```gdscript
# autoloads/SaveSystem.gd
const SAVE_PATH := "user://savegame.cfg"

static func save() -> void:
    var cfg := ConfigFile.new()
    # Map
    cfg.set_value("map", "seed", GameState.map_seed)
    cfg.set_value("map", "width", _get_map_mgr().map_width)
    cfg.set_value("map", "height", _get_map_mgr().map_height)
    cfg.set_value("map", "num_towns", _get_map_mgr().num_towns)
    cfg.set_value("map", "num_castles", _get_map_mgr().num_castles)
    # Ownership
    cfg.set_value("towns", "ownership", GameState.town_ownership)
    # Gold
    cfg.set_value("economy", "player_gold", GameState.player_gold)
    # Factions
    cfg.set_value("factions", "active", GameState.active_factions)
    cfg.set_value("factions", "relations", _serialize_relations())
    # Squads
    var squad_list := []
    var all_squads := GameState.player_squads + GameState.reserve_squads
    for i in range(all_squads.size()):
        var sq = all_squads[i]
        var sq_data: SquadData = sq if sq is SquadData else sq.squad_data
        var on_map: bool = sq is Squad
        var world_pos := sq.global_position if on_map else Vector3.ZERO
        squad_list.append(_serialize_squad(sq_data, on_map, world_pos))
    cfg.set_value("squads", "data", squad_list)
    cfg.save(SAVE_PATH)

static func _serialize_squad(data: SquadData, on_map: bool, pos: Vector3) -> Dictionary:
    var units := []
    for u in data.units:
        units.append({
            "class_id": u.class_id,
            "unit_name": u.unit_name,
            "level": u.level,
            "xp": u.xp,
            "hp": u.hp,
            "max_hp": u.max_hp,
            "strength": u.strength,
            "agility": u.agility,
            "intelligence": u.intelligence,
            "defense": u.defense,
            "resistance": u.resistance,
            "row": u.row,
            "col": u.col,
            "is_leader": u.is_leader,
            "is_alive": u.is_alive,
            "held_item": u.held_item,
        })
    return {
        "squad_id": data.squad_id,
        "faction": data.faction,
        "on_map": on_map,
        "world_x": pos.x,
        "world_z": pos.z,
        "units": units,
    }
```

### Load

```gdscript
static func load_exists() -> bool:
    return FileAccess.file_exists(SAVE_PATH)

static func load_game() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return
    # Restore GameState fields from cfg
    GameState.map_seed = cfg.get_value("map", "seed", 0)
    GameState.player_gold = cfg.get_value("economy", "player_gold", 100)
    GameState.town_ownership = cfg.get_value("towns", "ownership", {})
    # ... etc.
    # Signal Main.tscn to regenerate map with this seed, then restore squad positions
    GameState.is_loading_save = true
    get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
```

In `Main.tscn`'s `_ready()`, check `GameState.is_loading_save` and if true, skip army builder setup and instead restore squads from `GameState.save_squad_data`.

### Save/Load UI

Add to `TitleScreen`:
```
[New Game]
[Continue]   ← grayed out if no save exists
[Quit]
```

Add a "Save Game" button to the pause menu (press Space → pause → save button).

### Auto-Save Hook

Auto-save after every battle ends (in `BattleManager._on_battle_completed()`):
```gdscript
func _on_battle_completed(scene: BattleAnimator) -> void:
    # ... existing code ...
    SaveSystem.save()   # Auto-save after each battle
```

---

## SaveSystem Autoload

Register `autoloads/SaveSystem.gd` in `project.godot`. It is a static-only helper (all methods are `static`) so it doesn't need `extends Node` — but register it as a Node autoload anyway for Godot to resolve the class name globally.
