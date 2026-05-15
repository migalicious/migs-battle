class_name SkillSystem
extends RefCounted

static func can_use_attack(unit: UnitData, atk: AttackDefinition, context: Dictionary) -> bool:
	var cond := atk.condition_id
	if cond == "":
		return true
	if cond == "hp_below_50":
		return unit.hp * 2 <= unit.max_hp
	if cond == "first_round_only":
		return int(context.get("round", 0)) == 0
	push_warning("SkillSystem: unknown condition_id '%s'" % cond)
	return true
