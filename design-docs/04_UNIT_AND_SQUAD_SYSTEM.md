# 04 — Unit and Squad System

## Unit Classes (V1 Starter Set)

Eight classes covering the core archetypes. Each has a placeholder color for its cube mesh.

### Fighter Family

| Class | Promotes From | Level Req | Movement | Lead? | Color |
|-------|--------------|-----------|----------|-------|-------|
| Fighter | — (base) | — | INFANTRY | No | Steel blue |
| Knight | Fighter | 5 | INFANTRY | Yes | Gold |
| Paladin | Knight | 15 | INFANTRY | Yes | White |
| Archer | Fighter | 4 | INFANTRY | Yes | Brown |

### Magic Family

| Class | Promotes From | Level Req | Movement | Lead? | Color |
|-------|--------------|-----------|----------|-------|-------|
| Mage | Fighter | 4 | INFANTRY | Yes | Purple |
| Sorcerer | Mage | 12 | INFANTRY | Yes | Dark purple |

### Mobile Family

| Class | Promotes From | Level Req | Movement | Lead? | Color |
|-------|--------------|-----------|----------|-------|-------|
| Cavalry | Knight | 8 | CAVALRY | Yes | Tan |
| Gryphon Rider | Any leader | 10 | FLYING | Yes | Sky blue |

---

## Class Definitions (Detail)

### Fighter
```
base_hp: 22, base_str: 7, base_agi: 6, base_int: 3, base_def: 6, base_res: 3
growth: hp(4,6), str(2,4), agi(2,3), int(1,2), def(2,3), res(1,2)
front_attacks: [Slash x2 (PHYSICAL, power 1.0)]
back_attacks:  [Slash x1 (PHYSICAL, power 0.8)]
can_lead: false
```

### Knight
```
base_hp: 28, base_str: 8, base_agi: 5, base_int: 3, base_def: 9, base_res: 4
growth: hp(5,7), str(3,5), agi(1,3), int(1,2), def(3,4), res(1,2)
front_attacks: [Slash x2 (PHYSICAL, power 1.1)]
back_attacks:  [Slash x1 (PHYSICAL, power 0.9)]
can_lead: true
```

### Paladin
```
base_hp: 35, base_str: 10, base_agi: 6, base_int: 5, base_def: 12, base_res: 7
growth: hp(6,8), str(3,5), agi(2,3), int(2,3), def(3,5), res(2,3)
front_attacks: [Slash x3 (PHYSICAL, power 1.2)]
back_attacks:  [Holy Light x1 (HOLY, power 1.0, targets_row: ANY)]
can_lead: true
```

### Archer
```
base_hp: 20, base_str: 6, base_agi: 8, base_int: 4, base_def: 5, base_res: 5
growth: hp(3,5), str(2,3), agi(3,4), int(1,2), def(1,2), res(2,3)
front_attacks: [Shot x2 (PHYSICAL, power 0.9)]
back_attacks:  [Shot x2 (PHYSICAL, power 1.0, targets_row: BACK)]
can_lead: true
note: Archers in back row can target enemy back row — rare capability
```

### Mage
```
base_hp: 16, base_str: 3, base_agi: 5, base_int: 9, base_def: 3, base_res: 8
growth: hp(2,4), str(1,2), agi(1,2), int(4,6), def(1,2), res(3,4)
front_attacks: [Staff x1 (PHYSICAL, power 0.6)]
back_attacks:  [Magic x2 (element varies per cast, power 1.2, uses INT)]
can_lead: true
note: back_attacks use intelligence instead of strength for damage
```

### Sorcerer
```
base_hp: 20, base_str: 4, base_agi: 5, base_int: 13, base_def: 4, base_res: 12
growth: hp(3,5), str(1,2), agi(1,2), int(5,7), def(1,2), res(4,5)
front_attacks: [Staff x1 (PHYSICAL, power 0.6)]
back_attacks:  [Arcane Blast x2 (DARK, power 1.5, hits_all_in_column: true, uses INT)]
can_lead: true
```

### Cavalry
```
base_hp: 32, base_str: 9, base_agi: 9, base_int: 3, base_def: 8, base_res: 4
growth: hp(5,7), str(3,4), agi(3,5), int(1,2), def(2,3), res(1,2)
front_attacks: [Lance Charge x2 (PHYSICAL, power 1.3)]
back_attacks:  [Slash x1 (PHYSICAL, power 0.8)]
can_lead: true
movement_type: CAVALRY
base_move_speed: 4.5
```

### Gryphon Rider
```
base_hp: 26, base_str: 8, base_agi: 10, base_int: 4, base_def: 6, base_res: 6
growth: hp(4,6), str(2,4), agi(3,5), int(1,3), def(2,3), res(2,3)
front_attacks: [Talon x2 (PHYSICAL, power 1.0)]
back_attacks:  [Wind Blade x1 (COLD, power 1.1, targets_row: ANY, uses INT*0.5+STR*0.5)]
can_lead: true
movement_type: FLYING
base_move_speed: 2.8   # Slower base but ignores terrain penalties
```

---

## Squad Composition Rules

- A squad holds **0–6 units** arranged in a **3×2 grid**:
  - Row 0 = front row (columns 0, 1, 2)
  - Row 1 = back row (columns 0, 1, 2)
- Every squad must have exactly **one leader** unit. The leader's class must have `can_lead = true`.
- If the leader is killed in battle, the squad immediately retreats to the nearest friendly town after the battle ends.
- A squad with 0 alive units is removed from the map.
- Empty grid slots are allowed (squads do not need to be full).

### Grid Position Significance

```
[ front-left | front-center | front-right ]   row 0
[ back-left  | back-center  | back-right  ]   row 1
```

- **Physical attacks from the front** can only target front-row units. If the front row is empty, they hit back row.
- **Ranged/magic attacks** can target any row (depends on `targets_row` in `AttackDefinition`).
- Column position has no mechanical effect in V1 (reserved for future skill targeting).

---

## XP and Leveling

### XP Awards (per battle)

- Each alive unit on the winning side earns: `base_xp = 10 + (enemy_level_avg * 3)`
- Each alive unit on the losing side earns: `base_xp = 5 + (enemy_level_avg * 1)` (partial credit)
- A unit that personally lands the killing blow on an enemy: `+5 bonus XP`
- XP is distributed individually to each unit; units that were dead at battle end receive nothing.

### Level-Up Process

```gdscript
func try_level_up(unit: UnitData) -> bool:
    if unit.xp >= unit.xp_to_next:
        unit.xp -= unit.xp_to_next
        unit.level += 1
        unit.xp_to_next = 100 * unit.level
        apply_stat_growth(unit)
        return true
    return false

func apply_stat_growth(unit: UnitData) -> void:
    var cls = UnitRegistry.get_class(unit.class_id)
    unit.max_hp += randi_range(cls.hp_growth.x, cls.hp_growth.y)
    unit.hp = unit.max_hp   # Full heal on level up
    unit.strength += randi_range(cls.str_growth.x, cls.str_growth.y)
    unit.agility += randi_range(cls.agi_growth.x, cls.agi_growth.y)
    unit.intelligence += randi_range(cls.int_growth.x, cls.int_growth.y)
    unit.defense += randi_range(cls.def_growth.x, cls.def_growth.y)
    unit.resistance += randi_range(cls.res_growth.x, cls.res_growth.y)
```

### Promotion

Check for promotion eligibility after every level-up:

```gdscript
func check_promotion(unit: UnitData) -> String:
    var cls = UnitRegistry.get_class(unit.class_id)
    for promo in cls.promotions:
        if unit.level >= promo.required_level:
            return promo.target_class_id   # Promote available
    return ""
```

In V1, promotion is **automatic** when requirements are met. The unit's `class_id` is updated, and base stats are re-based to the new class's values (keeping any surplus above the new base). Stats do not decrease on promotion.

---

## Squad Node (World Presence)

`Squad.tscn` is a `CharacterBody3D` with:
- `NavigationAgent3D` for pathfinding
- `MeshInstance3D`: a capsule or box tinted in faction color
- `Label3D` showing squad leader name and HP fraction
- `Area3D` + `CollisionShape3D` for enemy contact detection

### Squad Movement Loop

```gdscript
func _physics_process(delta):
    if not has_destination:
        return
    if navigation_agent.is_navigation_finished():
        has_destination = false
        emit_signal("squad_arrived", self, global_position)
        return
    var next = navigation_agent.get_next_path_position()
    var dir = (next - global_position).normalized()
    velocity = dir * current_speed
    move_and_slide()
    update_speed_for_current_cell()

func update_speed_for_current_cell():
    var grid = MapManager.world_to_grid(global_position)
    var terrain = MapManager.get_terrain(grid.x, grid.y)
    var cls = UnitRegistry.get_class(squad_data.get_leader().class_id)
    current_speed = cls.base_move_speed * TerrainDefs.get_speed(cls.movement_type, terrain)
```

### Enemy Contact

The `Area3D` on each squad monitors for overlap with enemy squads. When detected:

```gdscript
func _on_area_entered(area: Area3D):
    var other = area.get_parent()
    if other is Squad and other.faction != self.faction:
        emit_signal("squad_collided_with_enemy", self, other)
```

`BattleManager` listens for this signal and initiates a battle.

---

## Squad Deployment

Squads can only be deployed from **friendly towns**. In V1:
- Click a friendly town → open `TownMenu`
- `TownMenu` shows the player's army roster (all configured squads not currently on the map)
- Select a squad → it spawns at the town's world position
- Only one squad can deploy per town at a time (the town must not already have a squad standing on it)

The deploy roster is managed by `GameState`, which tracks which squads are "on map" vs "in reserve."
