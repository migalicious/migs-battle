class_name SkillSystem
extends RefCounted

const _SkillDef = preload("res://scripts/battle/SkillDefinition.gd")

static func can_use_attack(unit: UnitData, atk: AttackDefinition, context: Dictionary) -> bool:
	var cond := atk.condition_id
	if cond == "":
		return true
	if cond == "hp_below_50":
		return unit.hp * 2 <= unit.max_hp
	if cond == "first_round_only":
		return int(context.get("round", 1)) == 1
	push_warning("SkillSystem: unknown condition_id '%s'" % cond)
	return true

static func condition_met(skill, unit: UnitData, context: Dictionary) -> bool:
	var c: int = skill.condition
	if c == _SkillDef.SkillCondition.ALWAYS:
		return true
	if c == _SkillDef.SkillCondition.HP_BELOW_50:
		return float(unit.hp) / float(maxi(unit.max_hp, 1)) < 0.5
	if c == _SkillDef.SkillCondition.HP_ABOVE_75:
		return float(unit.hp) / float(maxi(unit.max_hp, 1)) > 0.75
	if c == _SkillDef.SkillCondition.FIRST_ROUND:
		return int(context.get("round", 1)) == 1
	if c == _SkillDef.SkillCondition.LAST_ROUND:
		return int(context.get("round", 1)) == int(context.get("total_rounds", 3))
	if c == _SkillDef.SkillCondition.ALLY_DEAD:
		return bool(context.get("ally_dead", false))
	if c == _SkillDef.SkillCondition.ENEMY_FRONT_EMPTY:
		return bool(context.get("enemy_front_empty", false))
	return false
