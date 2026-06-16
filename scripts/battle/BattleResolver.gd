class_name BattleResolver
extends RefCounted

const _ItemDef = preload("res://scripts/items/ItemDefinition.gd")
const _SkillDef = preload("res://scripts/battle/SkillDefinition.gd")

static func resolve(attacker: SquadData, defender: SquadData,
		atk_on_water: bool = false, def_on_water: bool = false) -> BattleResult:
	var result := BattleResult.new()
	result.attacker_squad_id = attacker.squad_id
	result.defender_squad_id = defender.squad_id

	var atk_units: Array[UnitData] = _copy_units(attacker.units)
	var def_units: Array[UnitData] = _copy_units(defender.units)
	var battle_log: Array[BattleAction] = []

	for round_num in range(GameBalance.ROUNDS):
		if _all_dead(atk_units) or _all_dead(def_units):
			break
		_run_round(atk_units, def_units, battle_log, round_num + 1, atk_on_water, def_on_water)

	result.action_log = battle_log
	result.attacker_unit_states = atk_units
	result.defender_unit_states = def_units
	result.attacker_wiped = _all_dead(atk_units) or _leader_dead(atk_units)
	result.defender_wiped = _all_dead(def_units) or _leader_dead(def_units)

	var atk_avg_level := _avg_level(atk_units)
	var def_avg_level := _avg_level(def_units)
	var atk_alive := _count_alive(atk_units)
	var def_alive := _count_alive(def_units)

	var atk_per := (GameBalance.XP_WIN_BASE + int(def_avg_level * GameBalance.XP_WIN_PER_LEVEL)) if not result.attacker_wiped else (GameBalance.XP_LOSE_BASE + int(def_avg_level * GameBalance.XP_LOSE_PER_LEVEL))
	var def_per := (GameBalance.XP_WIN_BASE + int(atk_avg_level * GameBalance.XP_WIN_PER_LEVEL)) if not result.defender_wiped else (GameBalance.XP_LOSE_BASE + int(atk_avg_level * GameBalance.XP_LOSE_PER_LEVEL))
	result.attacker_xp = atk_per * maxi(atk_alive, 1)
	result.defender_xp = def_per * maxi(def_alive, 1)

	return result

static func _copy_units(units: Array[UnitData]) -> Array[UnitData]:
	var copies: Array[UnitData] = []
	for u in units:
		copies.append(u.duplicate() as UnitData)
	return copies

static func _all_dead(units: Array[UnitData]) -> bool:
	for u in units:
		if u.is_alive:
			return false
	return true

static func _leader_dead(units: Array[UnitData]) -> bool:
	for u in units:
		if u.is_leader and not u.is_alive:
			return true
	return false

static func _count_dead(units: Array[UnitData]) -> int:
	var count := 0
	for u in units:
		if not u.is_alive:
			count += 1
	return count

static func _count_alive(units: Array[UnitData]) -> int:
	var count := 0
	for u in units:
		if u.is_alive:
			count += 1
	return count

static func _avg_level(units: Array[UnitData]) -> float:
	if units.is_empty():
		return 1.0
	var total := 0
	for u in units:
		total += u.level
	return float(total) / float(units.size())

static func _run_round(atk_units: Array[UnitData], def_units: Array[UnitData],
		battle_log: Array[BattleAction], round_num: int,
		atk_on_water: bool = false, def_on_water: bool = false) -> void:
	var sep := BattleAction.new()
	sep.action_type = BattleAction.ActionType.ROUND_START
	sep.attack_name = "Round %d" % round_num
	battle_log.append(sep)

	# Initiative queue sorted by agility descending
	var queue: Array = []
	for u in atk_units:
		if u.is_alive:
			queue.append({"unit": u, "side": 0})
	for u in def_units:
		if u.is_alive:
			queue.append({"unit": u, "side": 1})
	queue.sort_custom(func(a, b): return (a["unit"] as UnitData).agility > (b["unit"] as UnitData).agility)

	for entry in queue:
		var unit: UnitData = entry["unit"] as UnitData
		if not unit.is_alive:
			continue
		var enemies: Array[UnitData] = def_units if entry["side"] == 0 else atk_units
		var allies: Array[UnitData]  = atk_units if entry["side"] == 0 else def_units
		var on_water: bool = atk_on_water if entry["side"] == 0 else def_on_water
		if _all_dead(enemies):
			break
		_execute_attacks(unit, enemies, allies, battle_log, round_num, on_water)

static func _execute_attacks(unit: UnitData, enemies: Array[UnitData], allies: Array[UnitData],
		battle_log: Array[BattleAction], round_num: int, on_water: bool = false) -> void:
	var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id)
	if not cls:
		return
	var attacks: Array = cls.front_attacks if unit.row == 0 else cls.back_attacks
	var context := _build_context(unit, allies, enemies, round_num, on_water)

	var dmg_mult := 1.0
	for skill in cls.skills:
		if skill.effect == _SkillDef.SkillEffect.DAMAGE_MULTIPLIER:
			if SkillSystem.condition_met(skill, unit, context):
				dmg_mult *= skill.power

	for atk in attacks:
		var atk_def := atk as AttackDefinition
		if not SkillSystem.can_use_attack(unit, atk_def, context):
			continue
		if atk_def.is_heal:
			for _hit in range(atk_def.hits):
				var lowest := _find_lowest_hp_ally(allies)
				if lowest:
					var heal := maxi(1, int(_get_stat(unit, "intelligence") * atk_def.power_multiplier))
					lowest.hp = mini(lowest.max_hp, lowest.hp + heal)
					_log_heal(unit, lowest, heal, atk_def.attack_name, battle_log)
			continue
		var targets: Array[UnitData] = _select_targets(atk_def, enemies)
		for _hit in range(atk_def.hits):
			for target in targets:
				if not target.is_alive:
					continue
				var dmg := _calculate_damage(unit, target, atk_def, dmg_mult)
				dmg = _apply_guard(target, dmg)
				_apply_damage(unit, target, dmg, atk_def, battle_log)
				_fire_post_attack_skills(unit, target, allies, enemies, context, battle_log)

static func _select_targets(atk_def: AttackDefinition, enemies: Array[UnitData]) -> Array[UnitData]:
	var alive_front: Array[UnitData] = []
	var alive_back: Array[UnitData] = []
	for u in enemies:
		if not u.is_alive:
			continue
		if u.row == 0:
			alive_front.append(u)
		else:
			alive_back.append(u)

	var base_pool: Array[UnitData] = []
	match atk_def.targets_row:
		TerrainDefs.TargetRow.FRONT:
			base_pool = alive_front if not alive_front.is_empty() else alive_back
		TerrainDefs.TargetRow.BACK:
			base_pool = alive_back if not alive_back.is_empty() else alive_front
		TerrainDefs.TargetRow.ANY:
			for u in alive_front:
				base_pool.append(u)
			for u in alive_back:
				base_pool.append(u)

	if base_pool.is_empty():
		return []

	if atk_def.hits_all_in_row:
		return base_pool

	if atk_def.hits_all_in_column:
		var col := (base_pool[0] as UnitData).col
		var col_targets: Array[UnitData] = []
		for u in enemies:
			if u.is_alive and u.col == col:
				col_targets.append(u)
		return col_targets

	# Single random target from pool
	return [base_pool[randi() % base_pool.size()]]

static func _get_stat(unit: UnitData, stat: String) -> float:
	var base: float = float(unit.get(stat))
	if unit.held_item == "":
		return base
	var item = ItemRegistry.get_item(unit.held_item)
	if not item:
		return base
	match stat:
		"strength":     return base + float(item.str_bonus)
		"agility":      return base + float(item.agi_bonus)
		"defense":      return base + float(item.def_bonus)
		"resistance":   return base + float(item.res_bonus)
		"intelligence": return base + float(item.int_bonus)
	return base

static func _build_context(actor: UnitData, allies: Array[UnitData],
		enemies: Array[UnitData], round_num: int, on_water: bool = false) -> Dictionary:
	var alive_allies := 0
	for u in allies:
		if u.is_alive:
			alive_allies += 1
	var front_alive := 0
	for u in enemies:
		if u.is_alive and u.row == 0:
			front_alive += 1
	return {
		"round": round_num,
		"total_rounds": GameBalance.ROUNDS,
		"hp_fraction": float(actor.hp) / float(maxi(actor.max_hp, 1)),
		"ally_dead": alive_allies < allies.size(),
		"enemy_front_empty": front_alive == 0,
		"on_water": on_water,
	}

static func _apply_guard(target: UnitData, dmg: int) -> int:
	if dmg <= 0:
		return dmg
	var cls := UnitRegistry.get_class_def(target.class_id) as ClassDefinition
	if not cls:
		return dmg
	var ctx := {"hp_fraction": float(target.hp) / float(maxi(target.max_hp, 1)),
			"round": 0, "ally_dead": false, "enemy_front_empty": false}
	for skill in cls.skills:
		if skill.effect == _SkillDef.SkillEffect.GUARD:
			if SkillSystem.condition_met(skill, target, ctx):
				dmg = maxi(1, int(float(dmg) * (1.0 - skill.damage_reduction)))
	return dmg

static func _fire_post_attack_skills(actor: UnitData, target: UnitData,
		allies: Array[UnitData], _enemies: Array[UnitData],
		context: Dictionary, battle_log: Array[BattleAction]) -> void:
	var cls := UnitRegistry.get_class_def(actor.class_id) as ClassDefinition
	if not cls:
		return
	for skill in cls.skills:
		if not SkillSystem.condition_met(skill, actor, context):
			continue
		var eff: int = skill.effect
		if eff == _SkillDef.SkillEffect.BONUS_DAMAGE:
			if not target.is_alive:
				continue
			var bdmg := maxi(1, int(_get_stat(actor, "strength") * skill.power))
			_apply_skill_hit(actor, target, bdmg, skill.display_name, battle_log)
		elif eff == _SkillDef.SkillEffect.HEAL_SELF:
			var heal := maxi(1, int(float(actor.max_hp) * skill.heal_percent))
			actor.hp = mini(actor.max_hp, actor.hp + heal)
			_log_heal(actor, actor, heal, skill.display_name, battle_log)
		elif eff == _SkillDef.SkillEffect.HEAL_ALLY:
			var lowest := _find_lowest_hp_ally(allies)
			if lowest:
				var heal := maxi(1, int(float(lowest.max_hp) * skill.heal_percent))
				lowest.hp = mini(lowest.max_hp, lowest.hp + heal)
				_log_heal(actor, lowest, heal, skill.display_name, battle_log)
		elif eff == _SkillDef.SkillEffect.EXTRA_ATTACK:
			if target.is_alive:  # guard already present — keep
				var extra := _calculate_damage(actor, target, _make_skill_atk(skill))
				extra = _apply_guard(target, extra)
				_apply_skill_hit(actor, target, extra, skill.display_name, battle_log)
		elif eff == _SkillDef.SkillEffect.STAT_DEBUFF_ENEMY:
			var cur := int(target.get(skill.stat_target))
			target.set(skill.stat_target, maxi(0, cur + skill.stat_amount))
			var debuff_action := BattleAction.new()
			debuff_action.action_type = BattleAction.ActionType.SKILL
			debuff_action.actor_unit_id = actor.unit_name
			debuff_action.target_unit_id = target.unit_name
			debuff_action.attack_name = skill.display_name
			debuff_action.description = skill.display_name
			debuff_action.damage_dealt = 0
			battle_log.append(debuff_action)
		elif eff == _SkillDef.SkillEffect.STAT_BUFF_SELF:
			var cur := int(actor.get(skill.stat_target))
			actor.set(skill.stat_target, cur + skill.stat_amount)
			var buff_action := BattleAction.new()
			buff_action.action_type = BattleAction.ActionType.SKILL
			buff_action.actor_unit_id = actor.unit_name
			buff_action.target_unit_id = actor.unit_name
			buff_action.attack_name = skill.display_name
			buff_action.description = skill.display_name
			buff_action.damage_dealt = 0
			battle_log.append(buff_action)

static func _apply_skill_hit(actor: UnitData, target: UnitData, dmg: int,
		skill_name: String, battle_log: Array[BattleAction]) -> void:
	var action := BattleAction.new()
	action.actor_unit_id = actor.unit_name
	action.target_unit_id = target.unit_name
	action.attack_name = skill_name
	if dmg <= 0:
		action.action_type = BattleAction.ActionType.MISS
		action.damage_dealt = 0
	else:
		target.hp -= dmg
		action.damage_dealt = dmg
		if target.hp <= 0:
			target.hp = 0
			target.is_alive = false
			action.action_type = BattleAction.ActionType.KILL
		else:
			action.action_type = BattleAction.ActionType.SKILL
	battle_log.append(action)

static func _log_heal(actor: UnitData, target: UnitData, amount: int,
		skill_name: String, battle_log: Array[BattleAction]) -> void:
	var action := BattleAction.new()
	action.action_type = BattleAction.ActionType.HEAL
	action.actor_unit_id = actor.unit_name
	action.target_unit_id = target.unit_name
	action.attack_name = skill_name
	action.damage_dealt = amount
	battle_log.append(action)

static func _find_lowest_hp_ally(allies: Array[UnitData]) -> UnitData:
	var lowest: UnitData = null
	var lowest_frac := 1.1
	for u in allies:
		if not u.is_alive:
			continue
		var frac := float(u.hp) / float(maxi(u.max_hp, 1))
		if frac < lowest_frac:
			lowest_frac = frac
			lowest = u
	return lowest

static func _make_skill_atk(skill) -> AttackDefinition:
	var a := AttackDefinition.new()
	a.attack_name = skill.display_name
	a.power_multiplier = skill.power
	a.damage_type = TerrainDefs.DamageType.PHYSICAL
	a.hits = 1
	a.targets_row = TerrainDefs.TargetRow.ANY
	return a

static func _calculate_damage(attacker: UnitData, target: UnitData, atk_def: AttackDefinition, mult: float = 1.0) -> int:
	if attacker.is_wounded:
		mult *= 0.8
	var stat: float
	var defense: float
	if atk_def.damage_type == TerrainDefs.DamageType.PHYSICAL:
		stat = _get_stat(attacker, "strength")
		defense = _get_stat(target, "defense")
	else:
		stat = _get_stat(attacker, "intelligence")
		defense = _get_stat(target, "resistance")

	var base_dmg := maxf(1.0, (stat * atk_def.power_multiplier) - (defense * GameBalance.DEFENSE_REDUCTION))
	base_dmg *= mult
	base_dmg += base_dmg * GameBalance.DAMAGE_VARIANCE * (randf() * 2.0 - 1.0)

	var hit_chance := clampf(GameBalance.BASE_HIT_CHANCE + (_get_stat(attacker, "agility") - _get_stat(target, "agility")) * GameBalance.HIT_CHANCE_PER_AGI, 0.5, 1.0)
	if randf() > hit_chance:
		return -1  # Miss

	return maxi(1, int(base_dmg))

static func _apply_damage(actor: UnitData, target: UnitData, dmg: int, atk_def: AttackDefinition, battle_log: Array[BattleAction]) -> void:
	var action := BattleAction.new()
	action.actor_unit_id = actor.unit_name
	action.target_unit_id = target.unit_name
	action.attack_name = atk_def.attack_name

	if dmg < 0:
		action.action_type = BattleAction.ActionType.MISS
		action.damage_dealt = 0
	else:
		target.hp -= dmg
		action.damage_dealt = dmg
		if target.hp <= 0:
			target.hp = 0
			target.is_alive = false
			action.action_type = BattleAction.ActionType.KILL
		else:
			action.action_type = BattleAction.ActionType.ATTACK

	battle_log.append(action)
