# V2-03 — Gold Economy

## Overview

Gold gives strategic meaning to town capture beyond just win conditions. Towns generate income over time. Deploying squads costs gold. A shop system at towns lets the player spend gold on items and equipment.

The V1 architecture already has hooks for this: `TownData.income` is defined (set to 0), `ClassDefinition.deploy_cost` is defined (set to 0). Both just need to be populated and wired.

---

## GameState Changes

```gdscript
# Add to GameState.gd
var player_gold: int = 100
var enemy_gold: int = 100
var gold_tick_interval: float = 10.0
var _gold_timer: float = 0.0

signal gold_changed(faction: int, new_total: int)

func _process(delta: float) -> void:
    if current_phase != Phase.OVERWORLD:
        return
    _gold_timer += delta
    if _gold_timer >= gold_tick_interval:
        _gold_timer = 0.0
        _collect_income()

func _collect_income() -> void:
    var map_mgr := _get_map_manager()
    if not map_mgr:
        return
    for town in map_mgr.get_towns():
        var owner: int = town_ownership.get(town.town_data.town_id, TerrainDefs.Faction.NEUTRAL)
        var income: int = town.town_data.income
        if owner == TerrainDefs.Faction.PLAYER:
            player_gold += income
            gold_changed.emit(TerrainDefs.Faction.PLAYER, player_gold)
        elif owner == TerrainDefs.Faction.ENEMY:
            enemy_gold += income
```

---

## Town Income Values

Set in `TownData.income` during map generation, assigned by `MapManager._spawn_towns()`.

| Town Type | Income per tick |
|-----------|----------------|
| TOWN | 15 gold |
| CASTLE | 30 gold |
| HQ | 50 gold |

```gdscript
# In MapManager._spawn_towns(), after setting data.town_type:
data.income = _income_for_type(data.town_type)

func _income_for_type(t: TerrainDefs.TownType) -> int:
    match t:
        TerrainDefs.TownType.TOWN:    return 15
        TerrainDefs.TownType.CASTLE:  return 30
        TerrainDefs.TownType.HQ:      return 50
        _: return 0
```

---

## Deploy Costs

Deploying a squad from reserve costs gold equal to the sum of all unit deploy costs in that squad.

Set in `UnitRegistry._build_default_classes()`:

| Class | Deploy Cost |
|-------|------------|
| Fighter | 50 |
| Archer | 60 |
| Mage | 70 |
| Knight | 80 |
| Paladin | 130 |
| Sorcerer | 120 |
| Cavalry | 100 |
| Gryphon Rider | 110 |

### Deployment Gate

In `SquadController._on_deploy_requested()`, add before spawning:

```gdscript
func _on_deploy_requested(squad_data: SquadData, town: TownNode) -> void:
    var cost := _squad_deploy_cost(squad_data)
    if GameState.player_gold < cost:
        _show_cant_afford_label(town.global_position, cost)
        return
    GameState.player_gold -= cost
    GameState.gold_changed.emit(TerrainDefs.Faction.PLAYER, GameState.player_gold)
    # ... rest of existing deploy logic

func _squad_deploy_cost(squad: SquadData) -> int:
    var total := 0
    for unit in squad.get_alive_units():
        var cls := UnitRegistry.get_class_def(unit.class_id) as ClassDefinition
        if cls:
            total += cls.deploy_cost
    return total

func _show_cant_afford_label(pos: Vector3, cost: int) -> void:
    var lbl := Label3D.new()
    lbl.text = "Need %dg!" % cost
    lbl.modulate = Color(1.0, 0.3, 0.3)
    lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    lbl.position = pos + Vector3(0, 2.5, 0)
    get_parent().add_child(lbl)
    var tween := create_tween()
    tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
    tween.tween_callback(lbl.queue_free)
```

The `TownMenu` should also show the deploy cost for each reserve squad in its list:
```
[Deploy: Roland's Squad  (4 units)  Cost: 290g]
```

---

## HUD Gold Display

Add a gold counter to `TopBar`. `TopBar.gd` connects to `GameState.gold_changed`:

```gdscript
var _gold_lbl: Label = null

func _ready() -> void:
    _gold_lbl = Label.new()
    _gold_lbl.text = "Gold: 100"
    # Add to top bar hbox after existing elements
    GameState.gold_changed.connect(_on_gold_changed)

func _on_gold_changed(faction: int, amount: int) -> void:
    if faction == TerrainDefs.Faction.PLAYER:
        _gold_lbl.text = "Gold: %d" % amount
        var tween := create_tween()
        tween.tween_property(_gold_lbl, "modulate", Color(1.0, 0.85, 0.1), 0.15)
        tween.tween_property(_gold_lbl, "modulate", Color.WHITE, 0.3)
```

---

## Item System

### ItemDefinition Resource

New resource class at `scripts/items/ItemDefinition.gd`:

```gdscript
class_name ItemDefinition
extends Resource

@export var item_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var cost: int = 0

enum ItemType { PASSIVE, CONSUMABLE }
@export var item_type: ItemType = ItemType.PASSIVE

# Stat bonuses applied while held
@export var hp_bonus: int = 0
@export var str_bonus: int = 0
@export var def_bonus: int = 0
@export var res_bonus: int = 0
@export var agi_bonus: int = 0
@export var int_bonus: int = 0

# For consumables: what they do at battle start
@export var heal_percent: float = 0.0   # 0.3 = restore 30% of max HP
```

Add to `UnitData.gd`:
```gdscript
@export var held_item: String = ""   # item_id, or "" for none
```

Add to `GameState.gd`:
```gdscript
var player_inventory: Dictionary = {}  # item_id -> count (int)
```

### ItemRegistry Autoload

New autoload `ItemRegistry` at `autoloads/ItemRegistry.gd`. Loads `.tres` files from `res://data/items/`. Provides `get_item(item_id) -> ItemDefinition`.

Register in `project.godot` autoloads.

### Starter Items (V2)

Create `.tres` files in `res://data/items/`:

| item_id | Display | Cost | Effect |
|---------|---------|------|--------|
| iron_shield | Iron Shield | 80 | +3 DEF |
| power_ring | Power Ring | 100 | +4 STR |
| silver_mail | Silver Mail | 120 | +5 DEF, +2 RES |
| mage_robe | Mage Robe | 110 | +5 RES, +2 INT |
| speed_boots | Speed Boots | 90 | +3 AGI |
| healing_herb | Healing Herb | 60 | Consumable: heal 30% HP at battle start |
| elixir | Elixir | 150 | Consumable: heal 100% HP at battle start |

### Applying Items in BattleResolver

Add a helper to compute effective stats:

```gdscript
# In BattleResolver
static func _get_stat(unit: UnitData, stat: String) -> float:
    var base: float = float(unit.get(stat))
    if unit.held_item == "":
        return base
    var item := ItemRegistry.get_item(unit.held_item) as ItemDefinition
    if not item:
        return base
    match stat:
        "strength":     return base + item.str_bonus
        "agility":      return base + item.agi_bonus
        "defense":      return base + item.def_bonus
        "resistance":   return base + item.res_bonus
        "intelligence": return base + item.int_bonus
    return base
```

Use `_get_stat(unit, "strength")` in `_calculate_damage()` instead of `float(attacker.strength)` directly.

Add `_apply_consumables()` called at the start of `resolve()`:

```gdscript
static func _apply_consumables(units: Array[UnitData]) -> void:
    for u in units:
        if not u.is_alive or u.held_item == "":
            continue
        var item := ItemRegistry.get_item(u.held_item) as ItemDefinition
        if not item or item.item_type != ItemDefinition.ItemType.CONSUMABLE:
            continue
        if item.heal_percent > 0.0:
            u.hp = mini(u.max_hp, u.hp + int(u.max_hp * item.heal_percent))
        u.held_item = ""   # Consumed
```

### Town Shop UI

Add a "Shop" button to `TownMenu._build_friendly_body()`. Opens a sub-panel (or replaces the body):

```
┌─────────────────────────────────────────┐
│  SHOP                     Gold: 340     │
├─────────────────────────────────────────┤
│  [Iron Shield   +3 DEF        80g  Buy] │
│  [Healing Herb  Heal 30%      60g  Buy] │
│  ...                                    │
├─────────────────────────────────────────┤
│  EQUIP                                  │
│  Unit: [Roland ▼]   Item: [None ▼]      │
│  Inventory: Iron Shield x1              │
│                              [Equip]    │
└─────────────────────────────────────────┘
```

- "Buy" button: deducts gold, adds item_id to `GameState.player_inventory`.
- "Equip" button: selects a unit from any reserve or on-map squad, assigns `unit.held_item`.
- If unit already has an item, it goes back to inventory first.
- Show current inventory count next to each item name.

---

## AI Gold Usage

Enemy accumulates gold via income ticks but doesn't spend it in V2. Stub comment added:

```gdscript
# In AIFaction._initial_spawn():
# TODO V3: deduct GameState.enemy_gold for squad spawning cost
```

In V3, `AIFaction` can spend gold to spawn reinforcement squads at enemy towns when it has enough gold and below max squad count.
