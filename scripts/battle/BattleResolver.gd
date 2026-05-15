class_name BattleResolver
extends RefCounted

const ROUNDS: int = 3

static func resolve(attacker: SquadData, defender: SquadData) -> BattleResult:
	var result := BattleResult.new()
	result.attacker_squad_id = attacker.squad_id
	result.defender_squad_id = defender.squad_id

	var atk_units: Array[UnitData] = _copy_units(attacker.units)
	var def_units: Array[UnitData] = _copy_units(defender.units)
	var battle_log: Array[BattleAction] = []

	for _round in range(ROUNDS):
		if _all_dead(atk_units) or _all_dead(def_units):
			break
		_run_round(atk_units, def_units, battle_log)

	result.action_log = battle_log
	result.attacker_unit_states = atk_units
	result.defender_unit_states = def_units
	result.attacker_wiped = _all_dead(atk_units) or _leader_dead(atk_units)
	result.defender_wiped = _all_dead(def_units) or _leader_dead(def_units)

	var atk_kills := _count_dead(def_units)
	var def_kills := _count_dead(atk_units)
	result.attacker_xp = atk_kills * 30 + 10 + (20 if result.defender_wiped else 0)
	result.defender_xp = def_kills * 30 + 10 + (20 if result.attacker_wiped else 0)

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

static func _run_round(atk_units: Array[UnitData], def_units: Array[UnitData], battle_log: Array[BattleAction]) -> void:
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
		if _all_dead(enemies):
			break
		_execute_attacks(unit, enemies, battle_log)

static func _execute_attacks(unit: UnitData, enemies: Array[UnitData], battle_log: Array[BattleAction]) -> void:
	var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id)
	if not cls:
		return
	var attacks: Array = cls.front_attacks if unit.row == 0 else cls.back_attacks
	for atk in attacks:
		var atk_def := atk as AttackDefinition
		if not SkillSystem.can_use_attack(unit, atk_def, {}):
			continue
		var targets: Array[UnitData] = _select_targets(atk_def, enemies)
		for _hit in range(atk_def.hits):
			for target in targets:
				if not target.is_alive:
					continue
				var dmg := _calculate_damage(unit, target, atk_def)
				_apply_damage(unit, target, dmg, atk_def, battle_log)

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

static func _calculate_damage(attacker: UnitData, target: UnitData, atk_def: AttackDefinition) -> int:
	var stat: float
	var defense: float
	if atk_def.damage_type == TerrainDefs.DamageType.PHYSICAL:
		stat = float(attacker.strength)
		defense = float(target.defense)
	else:
		stat = float(attacker.intelligence)
		defense = float(target.resistance)

	var base_dmg := maxf(1.0, (stat * atk_def.power_multiplier) - (defense * 0.5))
	base_dmg += base_dmg * 0.1 * (randf() * 2.0 - 1.0)

	# Hit/miss check: base 80%, modified by agility delta, clamped to [50%, 100%]
	var hit_chance := clampf(0.8 + (float(attacker.agility) - float(target.agility)) * 0.02, 0.5, 1.0)
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
