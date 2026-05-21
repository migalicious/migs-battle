# V2-04 — Skill System

## Overview

V1 has a `SkillSystem.gd` stub with only two conditions (`hp_below_50`, `first_round_only`). V2 builds the real system: a condition-gated, effect-based framework where units have **skills** that trigger automatically during battle under specific circumstances.

This is the core of what makes Unicorn Overlord's combat interesting — each unit class has a set of passive skills that fire when conditions are met, creating emergent synergies between squad compositions.

---

## Architecture

### Skill vs. Attack

V1 conflates "attack" with "action." V2 keeps attacks as they are (`AttackDefinition`) and adds a separate **skill layer** that can:
- Modify an attack before it fires (buff power, change target row)
- Fire an additional action after an attack (follow-up strike, heal ally)
- Apply a status effect to a target
- Provide passive stat bonuses during battle

### SkillDefinition Resource

New resource at `scripts/battle/SkillDefinition.gd`:

```gdscript
class_name SkillDefinition
extends Resource

@export var skill_id: String = ""
@export var display_name: String = ""
@export var description: String = ""

# --- Trigger condition ---
@export var condition: SkillCondition = SkillCondition.ALWAYS
enum SkillCondition {
    ALWAYS,           # Every round
    HP_BELOW_50,      # Unit's HP < 50%
    HP_ABOVE_75,      # Unit's HP > 75%
    FIRST_ROUND,      # Only round 1
    LAST_ROUND,       # Only round 3 (or final round)
    ALLY_DEAD,        # At least one ally in squad is dead
    ENEMY_FRONT_EMPTY,# Enemy front row has no alive units
    TARGET_PHYSICAL,  # The attacker's attack is PHYSICAL type
    TARGET_MAGICAL,   # The attacker's attack is any magic type
}

# --- Effect type ---
@export var effect: SkillEffect = SkillEffect.BONUS_DAMAGE
enum SkillEffect {
    BONUS_DAMAGE,       # Add flat damage after the triggering attack
    DAMAGE_MULTIPLIER,  # Multiply the triggering attack's damage
    HEAL_SELF,          # Restore HP to self (% of max)
    HEAL_ALLY,          # Restore HP to lowest-HP ally
    STAT_BUFF_SELF,     # Grant a temporary stat bonus for this battle
    STAT_DEBUFF_ENEMY,  # Reduce enemy stat for this battle
    GUARD,              # Reduce incoming damage by %
    COUNTER,            # Deal damage back to attacker when hit
    EXTRA_ATTACK,       # Perform an additional attack after the triggering one
}

# --- Effect parameters ---
@export var power: float = 1.0        # Damage multiplier or flat bonus
@export var heal_percent: float = 0.0 # For HEAL_SELF / HEAL_ALLY
@export var stat_target: String = ""  # "strength", "defense", etc.
@export var stat_amount: int = 0      # Bonus/penalty amount
@export var damage_reduction: float = 0.0  # For GUARD (0.3 = 30% reduction)
@export var damage_type: TerrainDefs.DamageType = TerrainDefs.DamageType.PHYSICAL
```

### ClassDefinition Change

Add to `ClassDefinition.gd`:
```gdscript
@export var skills: Array[SkillDefinition] = []
```

Each class can have 0–3 skills. Skills are passive — they are always checked during battle, no player input required.

---

## Skill Evaluation in BattleResolver

Skills are evaluated at two points during `_execute_attacks()`:

1. **Pre-attack**: Check if any skill modifies the upcoming attack (buff/debuff/guard).
2. **Post-attack**: Check if any skill fires a follow-up (bonus damage, heal, extra attack).

```gdscript
# In BattleResolver._execute_attacks() — revised:
static func _execute_attacks(actor: UnitData, enemies: Array[UnitData], allies: Array[UnitData],
        battle_log: Array[BattleAction], round_num: int) -> void:
    var cls: ClassDefinition = UnitRegistry.get_class_def(actor.class_id)
    if not cls:
        return
    var attacks: Array = cls.front_attacks if actor.row == 0 else cls.back_attacks
    var context := _build_context(actor, allies, enemies, round_num)

    for atk in attacks:
        var atk_def := atk as AttackDefinition
        # Check attack-level condition from V1 SkillSystem
        if not SkillSystem.can_use_attack(actor, atk_def, context):
            continue
        var targets: Array[UnitData] = _select_targets(atk_def, enemies)
        for _hit in range(atk_def.hits):
            for target in targets:
                if not target.is_alive:
                    continue
                var dmg := _calculate_damage(actor, target, atk_def)
                # Apply GUARD skills on target
                dmg = _apply_guard_skills(target, allies_of_target(target, enemies, allies), dmg)
                _apply_damage(actor, target, dmg, atk_def, battle_log)
                # Post-attack skills
                _fire_post_attack_skills(actor, target, enemies, allies, context, battle_log)

static func _build_context(actor: UnitData, allies: Array[UnitData],
        enemies: Array[UnitData], round_num: int) -> Dictionary:
    var alive_allies := allies.filter(func(u): return u.is_alive)
    var alive_enemies := enemies.filter(func(u): return u.is_alive)
    var front_alive := alive_enemies.filter(func(u): return u.row == 0)
    return {
        "round": round_num,
        "hp_fraction": float(actor.hp) / float(actor.max_hp),
        "ally_dead": alive_allies.size() < allies.size(),
        "enemy_front_empty": front_alive.is_empty(),
    }
```

### Condition Evaluation

```gdscript
# In SkillSystem.gd — expanded
static func condition_met(skill: SkillDefinition, unit: UnitData, context: Dictionary) -> bool:
    match skill.condition:
        SkillDefinition.SkillCondition.ALWAYS:
            return true
        SkillDefinition.SkillCondition.HP_BELOW_50:
            return float(unit.hp) / float(unit.max_hp) < 0.5
        SkillDefinition.SkillCondition.HP_ABOVE_75:
            return float(unit.hp) / float(unit.max_hp) > 0.75
        SkillDefinition.SkillCondition.FIRST_ROUND:
            return context.get("round", 1) == 1
        SkillDefinition.SkillCondition.LAST_ROUND:
            return context.get("round", 1) == BattleResolver.ROUNDS
        SkillDefinition.SkillCondition.ALLY_DEAD:
            return bool(context.get("ally_dead", false))
        SkillDefinition.SkillCondition.ENEMY_FRONT_EMPTY:
            return bool(context.get("enemy_front_empty", false))
    return false
```

### Post-Attack Skill Firing

```gdscript
static func _fire_post_attack_skills(actor: UnitData, target: UnitData,
        enemies: Array[UnitData], allies: Array[UnitData],
        context: Dictionary, battle_log: Array[BattleAction]) -> void:
    var cls: ClassDefinition = UnitRegistry.get_class_def(actor.class_id)
    if not cls:
        return
    for skill in cls.skills:
        if not SkillSystem.condition_met(skill, actor, context):
            continue
        match skill.effect:
            SkillDefinition.SkillEffect.BONUS_DAMAGE:
                var bonus_dmg := int(float(actor.strength) * skill.power)
                _apply_damage(actor, target, bonus_dmg, _make_skill_atk(skill), battle_log)
            SkillDefinition.SkillEffect.HEAL_SELF:
                var heal := int(float(actor.max_hp) * skill.heal_percent)
                actor.hp = mini(actor.max_hp, actor.hp + heal)
                battle_log.append(_make_heal_action(actor, actor, heal, skill.display_name))
            SkillDefinition.SkillEffect.HEAL_ALLY:
                var lowest := _find_lowest_hp_ally(allies)
                if lowest:
                    var heal := int(float(lowest.max_hp) * skill.heal_percent)
                    lowest.hp = mini(lowest.max_hp, lowest.hp + heal)
                    battle_log.append(_make_heal_action(actor, lowest, heal, skill.display_name))
            SkillDefinition.SkillEffect.EXTRA_ATTACK:
                # Fire one more attack against the same target
                var extra_dmg := _calculate_damage(actor, target, _make_skill_atk(skill))
                _apply_damage(actor, target, extra_dmg, _make_skill_atk(skill), battle_log)
```

---

## BattleAction Changes

Add `SKILL` and `HEAL` to `BattleAction.ActionType`:

```gdscript
enum ActionType { ATTACK, HEAL, SKILL, MISS, KILL }
```

`BattleAnimator` handles HEAL by showing a green "+N HP" floating number on the target's slot.

---

## V2 Skills by Class

### Fighter — "Grit"
- Condition: `HP_BELOW_50`
- Effect: `GUARD` (20% damage reduction while below half HP)
- Description: "When wounded, digs in and takes less punishment."

### Knight — "Shield Bash" (replaces no skill)
- Condition: `FIRST_ROUND`
- Effect: `BONUS_DAMAGE` (power 0.5, PHYSICAL)
- Description: "Opens with a powerful shield charge on the first round."

### Paladin — "Holy Aura"
- Condition: `ALWAYS`
- Effect: `HEAL_ALLY` (heal_percent 0.10 per round — heals the lowest-HP ally for 10% of their max HP each round)
- Description: "Radiates divine energy, gradually restoring allies."

### Archer — "Eagle Eye"
- Condition: `HP_ABOVE_75`
- Effect: `DAMAGE_MULTIPLIER` (power 1.3 — 30% more damage when healthy)
- Description: "Calm nerves mean precise shots."

### Mage — "Mana Surge"
- Condition: `LAST_ROUND`
- Effect: `EXTRA_ATTACK` (fires one more Magic attack on the final round)
- Description: "Unleashes remaining reserves in a final burst."

### Sorcerer — "Drain Life"
- Condition: `ALWAYS`
- Effect: `HEAL_SELF` (heal_percent 0.08 — restores 8% HP after each attack)
- Description: "Siphons vitality from enemies with each casting."

### Cavalry — "Momentum"
- Condition: `FIRST_ROUND`
- Effect: `DAMAGE_MULTIPLIER` (power 1.5 — 50% more damage on round 1 only)
- Description: "The charge's initial impact is devastating."

### Gryphon Rider — "Swoop"
- Condition: `ENEMY_FRONT_EMPTY`
- Effect: `BONUS_DAMAGE` (power 0.8, PHYSICAL — bonus strike when front row is clear, targeting back row)
- Description: "Dives past the front line to strike exposed enemies."

---

## Displaying Skills in UI

Update `UnitDetailPopup` to show skills:

```
SKILLS
  Eagle Eye: When HP > 75%, deal 30% more damage.
  [No second skill]
```

Update `SquadInspector` slot tooltip to briefly mention active skills.

---

## Data Files

Create `res://data/skills/` directory with one `.tres` per skill. `ClassDefinition.tres` files reference them by path. Alternatively, build skills inline in `UnitRegistry._build_default_classes()` (same pattern as attacks) — simpler for V2.

Recommended: inline in `UnitRegistry` for V2, export to `.tres` files in V3 when skill count grows.
