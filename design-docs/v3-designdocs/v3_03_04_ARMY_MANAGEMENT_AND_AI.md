# V3-03 — Post-Battle Army Management

## The Problem

V2 has no way to reorganize squads while on the map. If a squad loses units and becomes weak, the player must retreat it to a town, ungarrison it, and… still can't change its composition. The town menu only deploys reserve squads; it doesn't let the player move individual units between squads.

V3 adds field recomposition at towns: merge weakened squads, transfer units, and garrison management.

---

## Town Menu — "Manage Army" Tab

Add a new tab to `TownMenu` for friendly towns: **Manage Army**.

```
┌─────────────────────────────────────────────────────────┐
│  Ironhold Keep  [Castle]    Owner: Player                │
├──────────────────┬───────────────────┬───────────────────┤
│  [Deploy]  [Shop] [Manage Army]                         │
├──────────────────────────────────────────────────────────┤
│  SQUADS AT THIS TOWN                                     │
│                                                          │
│  Garrison: Roland's Squad  (5 alive / 6)                 │
│  Nearby:   Gawain's Squad  (2 alive / 5)  ← weakened    │
│                                                          │
│  [Merge Gawain → Roland]                                 │
│  [Edit Roland's Squad]                                   │
│  [Edit Gawain's Squad]                                   │
└──────────────────────────────────────────────────────────┘
```

"Nearby" = squads within `cell_size * 2` world units of the town.

---

## Squad Edit View

Clicking "Edit [Squad Name]" opens a simplified army-builder-style grid for that squad only. The right panel shows units from other squads at this town (garrison + nearby) that can be transferred.

Rules:
- A unit can only be moved if its current squad is at or adjacent to this town.
- Moving a unit out of a squad leaves that slot empty.
- If a squad loses its leader, auto-assign triggers (same logic as ArmyBuilderScreen).
- A squad with 0 units is removed from the map.

```gdscript
# In TownMenu or a new SquadEditPopup
func _build_squad_edit(sq: Squad, available_units: Array[UnitData]) -> void:
    # Show sq.squad_data 3×2 grid (clickable slots)
    # Show available_units list on the right (units from other squads at this town)
    # Click unit in list → click slot → transfer
    # Clicking occupied slot → remove unit back to available pool
```

---

## Squad Merge

"Merge [Squad A] → [Squad B]" transfers all alive units from Squad A into empty slots in Squad B. Squad A is then destroyed. If Squad B has no empty slots, merge is blocked.

```gdscript
func merge_squads(source: Squad, target: Squad) -> void:
    var empty_slots: Array[Vector2i] = _find_empty_slots(target.squad_data)
    var to_move := source.squad_data.get_alive_units()
    var moved := 0
    for u in to_move:
        if moved >= empty_slots.size():
            break
        var slot := empty_slots[moved]
        u.row = slot.x
        u.col = slot.y
        target.squad_data.units.append(u)
        moved += 1
    # Remove source squad
    source.queue_free()
    GameState.unregister_squad(source)
    # Units that couldn't fit go to reserve
    for u in to_move.slice(moved):
        # Add to a new reserve SquadData or warn player
        pass

func _find_empty_slots(data: SquadData) -> Array[Vector2i]:
    var occupied: Dictionary = {}
    for u in data.units:
        occupied[Vector2i(u.row, u.col)] = true
    var empty: Array[Vector2i] = []
    for r in [0, 1]:
        for c in [0, 1, 2]:
            if not occupied.has(Vector2i(r, c)):
                empty.append(Vector2i(r, c))
    return empty
```

---

## Wounded Unit Status

Add `is_wounded: bool` to `UnitData`. A unit becomes wounded when its HP falls below 25% at the end of a battle (not killed, but badly hurt). Wounded units:

- Deal 20% less damage in the next battle.
- Recover to full health automatically at the start of the *following* battle (they needed rest, not permanent treatment).
- Show a bandage icon in `SquadInspector` slots.

This adds texture to attrition without requiring a full fatigue system.

```gdscript
# In BattleManager._apply_result(), after applying unit states:
for u in squad.squad_data.units:
    if u.is_alive and float(u.hp) / float(u.max_hp) < 0.25:
        u.is_wounded = true
    elif u.is_alive:
        u.is_wounded = false

# In BattleResolver._calculate_damage():
var dmg_mult := 1.0
if actor.is_wounded:
    dmg_mult *= 0.8
# ... apply dmg_mult to base_dmg
```

---

## Reserve Squad Cap

Currently `GameState.reserve_squads` is uncapped. Add a cap of 5 reserve squads. If a retreating squad would exceed this:
- The squad is held at the town where it retreated (garrison).
- A notification informs the player: "Reserve full. [Squad] held at [Town]."

---

# V3-04 — AI Improvements

## Problem Summary

V2 AI is tactically blind:
- Enemy units have no items.
- AI doesn't react to skill composition — a squad of Clerics and Berserkers is treated identically.
- AI never spends gold (it accumulates but does nothing).
- Allied AI factions don't cooperate (the assist-ally objective from the spec was skipped).

---

## AI Item Assignment

At spawn time, `AIFaction._initial_spawn()` gives items to AI units based on template:

```gdscript
func _equip_template_items(data: SquadData, template_idx: int) -> void:
    # Give basic items to leaders and front-row units
    for u in data.units:
        var cls := UnitRegistry.get_class_def(u.class_id) as ClassDefinition
        if not cls:
            continue
        if u.is_leader or u.row == 0:
            # Physical front-liners get defense items
            if cls.movement_type == TerrainDefs.MovementType.INFANTRY and u.row == 0:
                u.held_item = _pick_item(["iron_shield", "silver_mail"])
            # Magic users get resistance or power items
            elif u.class_id in ["mage", "sorcerer", "witch", "cleric"]:
                u.held_item = _pick_item(["mage_robe", "power_ring"])

func _pick_item(options: Array[String]) -> String:
    return options[randi() % options.size()]
```

Items scale with template difficulty:
- Templates A/D (easy): iron_shield or speed_boots only
- Template B (medium): silver_mail, mage_robe
- Template C (hard): silver_mail + power_ring for leader

---

## AI Gold Spending (Reinforcements)

`GameState.enemy_gold` accumulates but is never spent. V3 adds a reinforcement system:

```gdscript
# In AIFaction._run_ai_tick(), after objectives:
_consider_reinforcement()

func _consider_reinforcement() -> void:
    var current_squads := GameState.get_squads_by_faction(controlled_faction).size()
    if current_squads >= MAX_AI_SQUADS:
        return
    var cost := _cheapest_template_cost()
    if GameState.enemy_gold < cost:
        return
    # Find a friendly town to spawn at
    var spawn_town := _find_unoccupied_friendly_town()
    if not spawn_town:
        return
    GameState.enemy_gold -= cost
    var template_idx := randi() % 4
    var data := _build_template(template_idx)
    data.squad_id = "ai_%d_reinf_%d" % [controlled_faction, Time.get_ticks_msec()]
    var sq: Squad = _SQUAD_SCENE.instantiate()
    _squad_controller.add_child(sq)
    sq.global_position = Vector3(spawn_town.global_position.x, 0.5, spawn_town.global_position.z + 2.0)
    sq.setup(data)
    _squad_controller.wire_squad(sq)

func _cheapest_template_cost() -> int:
    return 200   # Approximate cost of Template A
```

`enemy_gold` starts at 100 and accumulates from town income. Reinforcement threshold: 200 gold. This creates pressure that grows over time if the player lets enemy towns stand.

---

## Allied AI Cooperation

Implement the missing cooperative objective from v2_06:

```gdscript
# In AIFaction._assign_objective(), before "capture neutral":
for faction in GameState.active_factions:
    if faction == controlled_faction:
        continue
    if GameState.get_relation(controlled_faction, faction) != GameState.Relation.ALLIED:
        continue
    if _faction_hq_under_threat(faction):
        var allied_hq := _map_manager.get_hq(faction)
        if allied_hq:
            return {"type": "assist_ally", "target": allied_hq}

func _faction_hq_under_threat(faction: int) -> bool:
    var hq := _map_manager.get_hq(faction)
    if not hq:
        return false
    for sq_faction in GameState.faction_squads.values():
        for sq in sq_faction:
            if not is_instance_valid(sq):
                continue
            if GameState.are_hostile(sq.faction, faction):
                if sq.global_position.distance_to(hq.global_position) < THREAT_RADIUS:
                    return true
    return false
```

---

## AI Difficulty Scaling

Add `@export var difficulty_mult: float = 1.0` to `AIFaction`. In `_build_template()`, scale enemy unit levels:

```gdscript
func _add(data: SquadData, class_id: String, uname: String, row: int, col: int,
          is_leader: bool, base_level: int) -> void:
    var scaled_level := int(float(base_level) * difficulty_mult)
    # ...existing code...
```

`Main.gd` sets `difficulty_mult` on each AIFaction node based on `GameState.difficulty_level` (see `v3_07`).

For campaign mode, `difficulty_mult` increases each scenario:
- Scenario 1: 1.0
- Scenario 2: 1.1
- Scenario 3: 1.2
- Scenario 4: 1.35
- Scenario 5: 1.5
- Scenario 6: 1.7
