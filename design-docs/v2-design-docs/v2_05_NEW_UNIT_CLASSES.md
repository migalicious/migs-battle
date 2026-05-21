# V2-05 — New Unit Classes and Aquatic Movement

## Overview

V1 has 8 classes. V2 adds 6 more, completes the promotion trees, and activates the AQUATIC movement type that's already stubbed in `TerrainDefs` but unused.

---

## Aquatic Movement — Activation

The `AQUATIC` movement type is already in `TerrainDefs.MovementType` and `TerrainDefs.SPEED_TABLE`. The speed table values are:

| Terrain | AQUATIC speed |
|---------|--------------|
| PLAINS | 0.5 |
| GRASS | 0.5 |
| FOREST | 0.4 |
| MOUNTAIN | 0.3 |
| WATER | 1.2 |
| ROAD | 0.5 |

What's needed to activate it:

### 1. Squad Navigation for Aquatic Units

Currently the navmesh excludes WATER cells. Aquatic units need to traverse water. **Do not modify the existing navmesh** — instead, aquatic squads bypass the navmesh similarly to flying units (direct lerp toward destination), but they move at normal speed on water and reduced speed on land.

In `Squad.setup()`:
```gdscript
var _is_aquatic: bool = false

func setup(data: SquadData) -> void:
    # ... existing code ...
    var cls := UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
    if cls:
        _is_flying = cls.movement_type == TerrainDefs.MovementType.FLYING
        _is_aquatic = cls.movement_type == TerrainDefs.MovementType.AQUATIC
```

In `Squad._physics_process()`, aquatic movement uses the same direct-lerp path as flying (no navmesh), but respects terrain cost (slows on land, fast on water):

```gdscript
if _is_flying or _is_aquatic:
    var dir := _destination - global_position
    dir.y = 0.0
    if dir.length() < 0.3:
        _stop_moving()
        return
    velocity = dir.normalized() * squad_data.move_speed
```

The terrain speed update (Fix 1 in v2_01) will naturally slow aquatic units on land.

### 2. Town capture: aquatic squads can capture coastal towns

No special logic needed — collision detection and capture work the same regardless of movement type.

---

## New Classes

### Cleric (new)

Healer class — fills the dedicated support role. Promotes from Mage.

```
class_id: "cleric"
display_name: "Cleric"
placeholder_color: Color(1.0, 0.9, 0.6)   # Warm yellow

base_hp: 18, base_str: 3, base_agi: 5, base_int: 7, base_def: 4, base_res: 10
growth: hp(3,5), str(1,2), agi(1,2), int(3,5), def(1,2), res(3,5)

movement_type: INFANTRY
base_move_speed: 3.0
can_lead: true
deploy_cost: 75

front_attacks: [Staff x1 (PHYSICAL, power 0.5, FRONT)]
back_attacks:  [Heal x1 (HOLY, power 0.0, ANY)]
  — Heal: targets the lowest-HP ally, restores INT * 1.5 HP (not damage)
  — Implement as a special attack_type: HEAL in AttackDefinition (add to enum)

skill: "Devoted" — ALWAYS: HEAL_ALLY (heal_percent 0.12 each round)

promotions: []   # Cleric is a terminal class in V2; add Bishop in V3

Promotes from: Mage at level 8 (add to mage.promotions)
```

**AttackDefinition change needed**: Add `HEAL` to `DamageType` or handle healing attacks as a special case in `BattleResolver`. Recommended: add `is_heal: bool` to `AttackDefinition`. When `is_heal = true`, the "damage" is applied as HP restoration to the lowest-HP ally instead.

---

### Warrior (new)

Heavy front-liner. Alternative to Knight — more damage, less defense.

```
class_id: "warrior"
display_name: "Warrior"
placeholder_color: Color(0.7, 0.2, 0.15)   # Dark red

base_hp: 30, base_str: 10, base_agi: 7, base_int: 2, base_def: 7, base_res: 3
growth: hp(6,8), str(4,6), agi(2,3), int(1,2), def(2,3), res(1,2)

movement_type: INFANTRY
base_move_speed: 3.0
can_lead: true
deploy_cost: 90

front_attacks: [Heavy Strike x2 (PHYSICAL, power 1.4, FRONT)]
back_attacks:  [Throw x1 (PHYSICAL, power 0.9, ANY)]

skill: "Berserk" — HP_BELOW_50: DAMAGE_MULTIPLIER (power 1.5)
  Description: "When cornered, strikes with terrifying force."

promotions: [→ Berserker at level 12]
Promotes from: Fighter at level 6 (add to fighter.promotions alongside knight/archer/mage)
```

---

### Berserker (new)

Top-tier physical damage. Promotes from Warrior.

```
class_id: "berserker"
display_name: "Berserker"
placeholder_color: Color(0.9, 0.1, 0.1)   # Bright red

base_hp: 40, base_str: 14, base_agi: 9, base_int: 2, base_def: 8, base_res: 3
growth: hp(7,9), str(5,7), agi(2,4), int(1,2), def(2,3), res(1,2)

movement_type: INFANTRY
base_move_speed: 3.0
can_lead: true
deploy_cost: 140

front_attacks: [Rampage x3 (PHYSICAL, power 1.3, FRONT)]
back_attacks:  [War Cry x1 (PHYSICAL, power 1.0, hits_all_in_row: true)]

skill: "Bloodlust" — ALWAYS: HEAL_SELF (heal_percent 0.05 per attack landed)
  Description: "Draws strength from the violence of battle."

promotions: []
```

---

### Witch (new)

Magic damage class with debuffing. Alternative to Mage, promoting from Fighter.

```
class_id: "witch"
display_name: "Witch"
placeholder_color: Color(0.5, 0.0, 0.6)   # Magenta-purple

base_hp: 15, base_str: 3, base_agi: 6, base_int: 10, base_def: 3, base_res: 9
growth: hp(2,4), str(1,2), agi(2,3), int(4,6), def(1,2), res(3,4)

movement_type: INFANTRY
base_move_speed: 3.0
can_lead: true
deploy_cost: 70

front_attacks: [Hex x1 (DARK, power 0.7, FRONT)]
back_attacks:  [Curse Bolt x2 (DARK, power 1.1, ANY)]

skill: "Weaken" — ALWAYS: STAT_DEBUFF_ENEMY (stat_target: "defense", stat_amount: -3 for one battle)
  Description: "Her spells leave enemies spiritually exposed."

promotions: [→ Sorcerer at level 12]
Promotes from: Fighter at level 4 (alongside mage and archer)
```

---

### Merman / Merfolk (new — AQUATIC)

First aquatic unit class. Can traverse water at full speed.

```
class_id: "merfolk"
display_name: "Merfolk"
placeholder_color: Color(0.0, 0.7, 0.8)   # Teal

base_hp: 24, base_str: 8, base_agi: 8, base_int: 5, base_def: 6, base_res: 7
growth: hp(4,6), str(2,4), agi(2,4), int(2,3), def(2,3), res(2,3)

movement_type: AQUATIC
base_move_speed: 3.2
can_lead: true
deploy_cost: 95

front_attacks: [Trident x2 (PHYSICAL, power 1.1, FRONT)]
back_attacks:  [Tidal Wave x1 (COLD, power 1.0, hits_all_in_row: true)]

skill: "Tide Turn" — ENEMY_FRONT_EMPTY: BONUS_DAMAGE (power 0.7, COLD)
  Description: "Surges through gaps in the enemy line."

promotions: [→ Sea Knight at level 12]
Promotes from: Base (starts as Merfolk; recruited differently — see §recruiting below)
```

---

### Sea Knight (new — AQUATIC)

Promoted form of Merfolk. Stronger all-around aquatic warrior.

```
class_id: "sea_knight"
display_name: "Sea Knight"
placeholder_color: Color(0.0, 0.45, 0.6)   # Deep teal

base_hp: 34, base_str: 11, base_agi: 9, base_int: 6, base_def: 9, base_res: 9
growth: hp(5,7), str(3,5), agi(2,4), int(2,3), def(3,4), res(3,4)

movement_type: AQUATIC
base_move_speed: 3.5
can_lead: true
deploy_cost: 130

front_attacks: [Coral Blade x2 (PHYSICAL, power 1.3, FRONT)]
back_attacks:  [Storm Surge x1 (COLD, power 1.3, ANY)]

skill: "Deep Current" — ALWAYS: STAT_BUFF_SELF (stat_target: "agility", stat_amount: +4 on water terrain)
  Description: "In their element, moves with inhuman speed."
  Note: Condition check needs context["on_water"] = true when squad is on a water cell.

promotions: []
```

---

## Promotion Tree Update

Updated full tree after V2:

```
Fighter
  ├── → Knight (Lv.5)
  │     ├── → Paladin (Lv.15)
  │     ├── → Cavalry (Lv.8)
  │     └── → Gryphon Rider (Lv.10)
  ├── → Archer (Lv.4)
  ├── → Mage (Lv.4)
  │     ├── → Sorcerer (Lv.12)
  │     └── → Cleric (Lv.8)
  ├── → Warrior (Lv.6)      [NEW]
  │     └── → Berserker (Lv.12) [NEW]
  └── → Witch (Lv.4)        [NEW]
        └── → Sorcerer (Lv.12)

Merfolk (recruited separately, not from Fighter)
  └── → Sea Knight (Lv.12)
```

Update `fighter.promotions` in `UnitRegistry._build_default_classes()` to add warrior and witch.
Update `mage.promotions` to add cleric.

---

## Recruiting Merfolk

Merfolk are not in the default army roster. They are recruited by capturing coastal towns (towns adjacent to water cells) and then selecting "Recruit" from that town's menu. V2 stub:

- Add `has_aquatic_recruit: bool` to `TownData`.
- `MapGenerator` sets `has_aquatic_recruit = true` on towns within 2 cells of a water cell.
- `TownMenu` shows a "Recruit Merfolk" button (costs 120g) on those towns.
- Recruited Merfolk go to `GameState.player_inventory_units` (unassigned pool, see army builder).

This creates a natural strategic decision: contest the coastline to gain aquatic units.

---

## Adding New Classes to UnitRegistry

All new classes are added to `_build_default_classes()` following the exact same pattern as existing classes. Add `deploy_cost` for each. Don't forget to update `_save_classes()` — it already iterates `_classes` and saves all of them.
