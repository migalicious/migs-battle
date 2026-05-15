# 02 — Data Model

All persistent game data uses Godot `Resource` subclasses so they can be serialized to `.tres` files and passed between scenes without coupling.

---

## UnitData (Resource)

Represents one individual unit. Instances live inside a `SquadData`.

```gdscript
class_name UnitData
extends Resource

# Identity
@export var unit_name: String = ""
@export var class_id: String = ""          # Key into UnitRegistry
@export var faction: int = 0               # 0 = player, 1 = enemy

# Grid position within squad (set by SquadData)
@export var row: int = 0                   # 0 = front, 1 = back
@export var col: int = 0                   # 0, 1, 2

# Current stats (may differ from class base due to level/equipment)
@export var hp: int = 0
@export var max_hp: int = 0
@export var strength: int = 0
@export var agility: int = 0
@export var intelligence: int = 0
@export var defense: int = 0
@export var resistance: int = 0            # magic defense

# Progression
@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next: int = 100

# State flags
@export var is_alive: bool = true
@export var is_leader: bool = false        # Leader's death causes squad retreat

# Computed at runtime, not exported
var class_def: ClassDefinition             # Populated by UnitRegistry on load
```

**XP thresholds**: `xp_to_next = 100 * level`. On level-up, call `ClassDefinition.apply_level_up(unit)` which adds stat ranges from the class definition.

---

## ClassDefinition (Resource)

Defines a unit class: base stats, stat growth, attack patterns, movement type, and upgrade paths.

```gdscript
class_name ClassDefinition
extends Resource

@export var class_id: String = ""
@export var display_name: String = ""
@export var description: String = ""

# Visual placeholder color (used to tint the cube mesh in V1)
@export var placeholder_color: Color = Color.WHITE

# Base stats at level 1
@export var base_hp: int = 20
@export var base_strength: int = 5
@export var base_agility: int = 5
@export var base_intelligence: int = 5
@export var base_defense: int = 5
@export var base_resistance: int = 5

# Stat growth per level (applied as a flat range: rng(min, max))
@export var hp_growth: Vector2i = Vector2i(3, 5)
@export var str_growth: Vector2i = Vector2i(1, 3)
@export var agi_growth: Vector2i = Vector2i(1, 3)
@export var int_growth: Vector2i = Vector2i(1, 2)
@export var def_growth: Vector2i = Vector2i(1, 3)
@export var res_growth: Vector2i = Vector2i(1, 2)

# Movement
@export var movement_type: MovementType = MovementType.INFANTRY
# INFANTRY, CAVALRY, FLYING, AQUATIC
# (see TerrainDefs for how each type interacts with terrain)

@export var base_move_speed: float = 3.0   # world units per second on preferred terrain

# Can this class lead a squad?
@export var can_lead: bool = false

# Deployment cost (future gold system hook — set to 0 for V1)
@export var deploy_cost: int = 0

# --- Attack definition ---
# Front row attacks (executed when unit is in row 0)
@export var front_attacks: Array[AttackDefinition] = []
# Back row attacks (executed when unit is in row 1)
@export var back_attacks: Array[AttackDefinition] = []

# --- Class progression ---
# Classes this unit can promote to, and the requirements
@export var promotions: Array[PromotionRequirement] = []
```

---

## AttackDefinition (Resource)

Defines a single attack action a unit can perform during battle.

```gdscript
class_name AttackDefinition
extends Resource

@export var attack_name: String = ""
@export var damage_type: DamageType = DamageType.PHYSICAL
# PHYSICAL, FIRE, COLD, THUNDER, HOLY, DARK

@export var hits: int = 1                  # Number of strikes per attack
@export var power_multiplier: float = 1.0  # Multiplied against attacker's STR or INT
@export var targets_row: TargetRow = TargetRow.FRONT
# FRONT = targets front row of enemy, BACK = targets back row, ANY = attacker picks best

@export var hits_all_in_column: bool = false   # AoE: hits all units in target column
@export var hits_all_in_row: bool = false      # AoE: hits entire row

# Skill condition hook (evaluated by SkillSystem before use)
@export var condition_id: String = ""          # "" = always usable
```

---

## PromotionRequirement (Resource)

```gdscript
class_name PromotionRequirement
extends Resource

@export var target_class_id: String = ""
@export var required_level: int = 10
# Future hooks:
# @export var required_item_id: String = ""
# @export var required_alignment: int = -1  # -1 = any
```

---

## SquadData (Resource)

Represents the configuration of one squad. Passed to and from BattleManager.

```gdscript
class_name SquadData
extends Resource

@export var squad_id: String = ""           # Unique ID
@export var faction: int = 0
@export var units: Array[UnitData] = []     # Max 6 entries; row/col set per unit

# Derived at runtime — call recalculate() after any unit change
var move_speed: float = 0.0                 # Minimum of unit speeds on current terrain
var movement_type: MovementType             # Determined by squad leader's class

func get_unit_at(row: int, col: int) -> UnitData:
    for u in units:
        if u.row == row and u.col == col:
            return u
    return null

func get_leader() -> UnitData:
    for u in units:
        if u.is_leader:
            return u
    return units[0] if units.size() > 0 else null

func get_alive_units() -> Array[UnitData]:
    return units.filter(func(u): return u.is_alive)

func recalculate_speed(terrain: TerrainType) -> void:
    # Squad moves at the speed of its slowest unit on this terrain
    var min_speed = INF
    for u in get_alive_units():
        var cls = UnitRegistry.get_class(u.class_id)
        var spd = TerrainDefs.get_speed(cls.movement_type, terrain)
        min_speed = min(min_speed, spd)
    move_speed = min_speed if min_speed != INF else 0.0
```

---

## TownData (Resource)

Static definition of a town or castle node on the map.

```gdscript
class_name TownData
extends Resource

@export var town_id: String = ""
@export var display_name: String = ""
@export var town_type: TownType = TownType.TOWN
# TOWN, CASTLE, HQ (main stronghold — losing this = defeat)

@export var starting_faction: int = -1     # -1 = neutral, 0 = player, 1 = enemy
@export var is_deploy_point: bool = true
@export var capture_turns: int = 3         # How many "contact ticks" to capture (see §07)

# Position on map grid
@export var grid_x: int = 0
@export var grid_z: int = 0

# Income per game-tick (future gold system — set to 0 for V1)
@export var income: int = 0
```

---

## BattleResult (Resource)

Output of `BattleResolver.resolve()`. Consumed by BattleManager and BattleAnimator.

```gdscript
class_name BattleResult
extends Resource

@export var attacker_squad_id: String = ""
@export var defender_squad_id: String = ""

# Snapshot of unit states after battle (hp changes, deaths)
@export var attacker_unit_states: Array[UnitData] = []
@export var defender_unit_states: Array[UnitData] = []

# XP awarded to each surviving unit on each side
@export var attacker_xp: int = 0
@export var defender_xp: int = 0

@export var attacker_wiped: bool = false
@export var defender_wiped: bool = false

# Ordered log of actions for the animator to play back
@export var action_log: Array[BattleAction] = []
```

---

## BattleAction (Resource)

One entry in the battle playback log.

```gdscript
class_name BattleAction
extends Resource

enum ActionType { ATTACK, HEAL, SKILL, MISS, KILL }

@export var action_type: ActionType
@export var actor_unit_id: String = ""
@export var target_unit_id: String = ""
@export var damage_dealt: int = 0
@export var attack_name: String = ""
```

---

## Enums (TerrainDefs.gd)

```gdscript
enum TerrainType {
    PLAINS,
    GRASS,
    FOREST,
    MOUNTAIN,
    WATER,
    ROAD        # Fast movement for all ground types
}

enum MovementType {
    INFANTRY,
    CAVALRY,
    FLYING,
    AQUATIC
}

enum DamageType {
    PHYSICAL,
    FIRE,
    COLD,
    THUNDER,
    HOLY,
    DARK
}

enum TownType {
    TOWN,
    CASTLE,
    HQ
}

enum Faction {
    PLAYER = 0,
    ENEMY = 1,
    NEUTRAL = -1
}
```
