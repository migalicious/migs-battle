# 06 — Battle System

## Overview

When two opposing squads collide on the map, a battle automatically triggers. The battle is **fully automatic** — neither player takes action during it. The outcome is determined by the `BattleResolver` running the combat logic, which produces a `BattleResult`. The `BattleScene` then plays back the result visually.

Battles are inspired by Ogre Battle and Unicorn Overlord: squads face off on a 3×2 grid per side, with front-row and back-row positioning mattering for attack targeting. No timing mechanics, no player input during resolution.

---

## Battle Grid

Each side has a **3×2 grid** of slots:

```
Attacker side                Defender side
  col: 0   1   2              col: 0   1   2
row 0: [F] [F] [F]    vs    [F] [F] [F]  ← front rows face each other
row 1: [B] [B] [B]          [B] [B] [B]  ← back rows
```

Units keep their `row` and `col` assignments from `SquadData`. An empty slot is simply a gap — attacks that would hit an empty slot miss entirely.

---

## Battle Resolution (BattleResolver.gd)

`BattleResolver` is a **pure logic class** — no scene nodes, no signals to the overworld. It takes two `SquadData` references and returns a `BattleResult`.

```gdscript
static func resolve(attacker: SquadData, defender: SquadData) -> BattleResult:
```

### Resolution Loop

Each battle runs for a fixed number of **rounds** (V1: 3 rounds). In each round:

1. Determine attack order (by agility, highest goes first).
2. Each alive unit executes its attacks for its current row.
3. Apply damage.
4. Check for deaths.
5. Log all actions to `BattleResult.action_log`.

After all rounds, determine winner (side with more surviving HP, or the side that wiped the other).

### Round Structure

```gdscript
func run_round(attackers: Array[UnitData], defenders: Array[UnitData], log: Array) -> void:
    # Build combined action queue sorted by agility descending
    var queue = []
    for u in attackers:
        if u.is_alive:
            queue.append({unit: u, side: "atk"})
    for u in defenders:
        if u.is_alive:
            queue.append({unit: u, side: "def"})
    queue.sort_custom(func(a, b): return a.unit.agility > b.unit.agility)

    for entry in queue:
        if not entry.unit.is_alive:
            continue
        var attacks = get_attacks_for_unit(entry.unit)
        var enemies = defenders if entry.side == "atk" else attackers
        for atk_def in attacks:
            var targets = select_targets(atk_def, enemies)
            for target in targets:
                var dmg = calculate_damage(entry.unit, target, atk_def)
                apply_damage(target, dmg, log, entry.unit, atk_def)
```

### Attack Selection

A unit uses the attacks defined for its current row in `ClassDefinition`:
- If `unit.row == 0`: use `class_def.front_attacks`
- If `unit.row == 1`: use `class_def.back_attacks`

Each `AttackDefinition` is executed `hits` times.

### Target Selection

```gdscript
func select_targets(atk: AttackDefinition, enemies: Array[UnitData]) -> Array[UnitData]:
    var alive = enemies.filter(func(u): return u.is_alive)
    match atk.targets_row:
        TargetRow.FRONT:
            # Target front row first; if empty, target back row
            var front = alive.filter(func(u): return u.row == 0)
            return [front.pick_random()] if front.size() > 0 else \
                   ([alive.pick_random()] if alive.size() > 0 else [])
        TargetRow.BACK:
            var back = alive.filter(func(u): return u.row == 1)
            return [back.pick_random()] if back.size() > 0 else \
                   ([alive.pick_random()] if alive.size() > 0 else [])
        TargetRow.ANY:
            return [alive.pick_random()] if alive.size() > 0 else []
```

If `hits_all_in_column` or `hits_all_in_row` is set, override: return all alive units matching that column/row instead of a single random target.

### Damage Formula

```gdscript
func calculate_damage(attacker: UnitData, target: UnitData, atk: AttackDefinition) -> int:
    # Determine attack stat
    var atk_stat: float
    if atk.damage_type == DamageType.PHYSICAL:
        atk_stat = attacker.strength
    else:
        atk_stat = attacker.intelligence

    # Determine defense stat
    var def_stat: float
    if atk.damage_type == DamageType.PHYSICAL:
        def_stat = target.defense
    else:
        def_stat = target.resistance

    # Base damage
    var base = (atk_stat * atk.power_multiplier) - (def_stat * 0.5)
    base = max(1.0, base)   # Minimum 1 damage

    # Agility-based hit/miss chance
    var hit_chance = 0.85 + (attacker.agility - target.agility) * 0.01
    hit_chance = clamp(hit_chance, 0.5, 0.99)
    if randf() > hit_chance:
        return 0   # Miss

    # Variance ±10%
    var variance = randf_range(0.9, 1.1)
    return int(base * variance)
```

### Death and Leader Fall

```gdscript
func apply_damage(target: UnitData, dmg: int, log: Array, actor: UnitData, atk: AttackDefinition) -> void:
    if dmg == 0:
        log.append(make_action(ActionType.MISS, actor, target, 0, atk.attack_name))
        return
    target.hp = max(0, target.hp - dmg)
    log.append(make_action(ActionType.ATTACK, actor, target, dmg, atk.attack_name))
    if target.hp == 0:
        target.is_alive = false
        log.append(make_action(ActionType.KILL, actor, target, 0, ""))
```

If the leader is killed mid-battle, the battle still continues to conclusion (the squad doesn't flee until after the battle is over).

---

## Post-Battle

After all rounds:

1. **Determine winner**: side with at least one alive unit wins. If both are alive, side with higher remaining HP% wins (rare but possible).
2. **XP grant**: applied to all surviving units per the rules in §04.
3. **Level-up check**: `try_level_up()` called for each unit; promotion check follows.
4. **Loser outcome**:
   - If attacker is wiped: attacker squad removed from map.
   - If defender is wiped: defender squad removed from map.
   - If attacker loses (not wiped): attacker squad retreats to nearest friendly town (teleported in V1, animated in V2).
   - If defender loses (not wiped): defender retreats similarly.
5. **Town capture check**: if a squad wins a battle at a town it was trying to capture (see §07), begin or complete capture.

---

## Battle Scene (Visual Playback)

`BattleScene.tscn` is a full-screen overlay that plays back the `BattleResult.action_log` as a simple animation. The overworld is paused behind it.

### Layout

```
┌─────────────────────────────────────────────┐
│  [Attacker name]          [Defender name]   │
│                                             │
│  [3×2 grid, attacker]  [3×2 grid, defender] │
│                                             │
│  [Battle log text scrolling at bottom]      │
│                                             │
│  [Auto-advance or Skip button]              │
└─────────────────────────────────────────────┘
```

### Unit Display in Battle

Each unit slot is a **colored cube** (matching their class placeholder color) with a small HP bar below it. Dead units show as a greyed-out tilted cube.

### Playback

The animator steps through `action_log` entries with a short delay between each (~0.4s). For each action:
- **ATTACK**: flash the target cube briefly, update HP bar, show damage number floating above target.
- **MISS**: show "MISS" text above target.
- **KILL**: tilt target cube, grey it out, shake screen slightly.

After all actions are played, show "Round X" text and pause briefly before the next round.

At battle end: show winner banner ("Victory!" / "Defeat!"), XP gained, level-ups, then a "Continue" button that dismisses the scene and resumes the overworld.

---

## Skill System (V1 Stub)

`SkillSystem.gd` exists but is minimal in V1. `AttackDefinition.condition_id` is checked before an attack fires:

```gdscript
static func can_use_attack(unit: UnitData, atk: AttackDefinition, battle_context: Dictionary) -> bool:
    if atk.condition_id == "":
        return true
    # V1: only implement a couple of conditions
    match atk.condition_id:
        "hp_below_50":
            return unit.hp < unit.max_hp * 0.5
        "first_round_only":
            return battle_context.get("round", 1) == 1
        _:
            return true   # Unknown condition = always allow (safe default)
```

More conditions are added in V2 when the full UO-style skill/condition system is built out.
