extends Node

signal battle_started(attacker: SquadData, defender: SquadData)
signal battle_ended(result: BattleResult)

const _BATTLE_SCENE := preload("res://scenes/battle/BattleScene.tscn")

var _in_battle: bool = false
var _current_attacker: Squad = null
var _current_defender: Squad = null
var _current_result: BattleResult = null

func _ready() -> void:
	pass

func on_squads_collided(sq_a: Squad, sq_b: Squad) -> void:
	if _in_battle or sq_a.in_battle or sq_b.in_battle:
		return

	_in_battle = true
	sq_a.in_battle = true
	sq_b.in_battle = true
	_current_attacker = sq_a
	_current_defender = sq_b

	GameState.current_phase = GameState.Phase.IN_BATTLE

	_current_result = BattleResolver.resolve(sq_a.squad_data, sq_b.squad_data)
	_precompute_level_ups(_current_result)
	battle_started.emit(sq_a.squad_data, sq_b.squad_data)

	get_tree().paused = true

	var scene: BattleAnimator = _BATTLE_SCENE.instantiate() as BattleAnimator
	scene.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.battle_completed.connect(_on_battle_completed.bind(scene))
	get_tree().root.add_child(scene)
	scene.start(sq_a.squad_data, sq_b.squad_data, _current_result)

func _on_battle_completed(scene: BattleAnimator) -> void:
	scene.queue_free()
	_apply_result()
	get_tree().paused = false
	GameState.current_phase = GameState.Phase.OVERWORLD
	_in_battle = false
	battle_ended.emit(_current_result)
	# Check win conditions now that phase is OVERWORLD (trigger_end will re-pause if needed)
	GameState.check_win_conditions()

# ── Result Application ────────────────────────────────────────────────────────

func _apply_result() -> void:
	_apply_unit_states(_current_attacker.squad_data, _current_result.attacker_unit_states)
	_apply_unit_states(_current_defender.squad_data, _current_result.defender_unit_states)

	_grant_xp(_current_attacker.squad_data, _current_result.attacker_xp)
	_grant_xp(_current_defender.squad_data, _current_result.defender_xp)

	if _current_result.attacker_wiped:
		_handle_loser(_current_attacker)
	else:
		_current_attacker.in_battle = false

	if _current_result.defender_wiped:
		_handle_loser(_current_defender)
	else:
		_current_defender.in_battle = false

func _apply_unit_states(data: SquadData, states: Array[UnitData]) -> void:
	for state in states:
		for unit in data.units:
			if unit.unit_name == state.unit_name:
				unit.hp = state.hp
				unit.is_alive = state.is_alive
				break

func _grant_xp(data: SquadData, total_xp: int) -> void:
	var alive := data.get_alive_units()
	if alive.is_empty() or total_xp <= 0:
		return
	var xp_each := int(float(total_xp) / float(alive.size()))
	for unit in alive:
		unit.xp += xp_each
		while LevelSystem.try_level_up(unit):
			print("[BattleManager] Level up: %s → level %d" % [unit.unit_name, unit.level])
			var promo := LevelSystem.check_promotion(unit)
			if promo != "":
				LevelSystem.apply_promotion(unit, promo)
				print("[BattleManager] %s promoted → %s" % [unit.unit_name, promo])

func _handle_loser(squad: Squad) -> void:
	GameState.player_squads.erase(squad)
	GameState.enemy_squads.erase(squad)

	# Keep only survivors
	var alive: Array[UnitData] = []
	for u in squad.squad_data.units:
		if u.is_alive:
			alive.append(u)
	squad.squad_data.units = alive

	var nearest := _find_nearest_friendly_town(squad)
	if nearest and not alive.is_empty():
		squad.retreat_to(nearest.global_position)
		squad.in_battle = false
		if squad.faction == TerrainDefs.Faction.PLAYER:
			GameState.player_squads.append(squad)
		else:
			GameState.enemy_squads.append(squad)
	else:
		squad.queue_free()


func _find_nearest_friendly_town(squad: Squad) -> TownNode:
	var map_mgr := _get_map_manager()
	if not map_mgr:
		return null
	var nearest: TownNode = null
	var nearest_dist := INF
	for town in map_mgr.get_towns():
		if town.faction == squad.faction:
			var dist := squad.global_position.distance_to(town.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = town
	return nearest

func _precompute_level_ups(result: BattleResult) -> void:
	_precompute_side(result.attacker_unit_states, result.attacker_xp, result)
	_precompute_side(result.defender_unit_states, result.defender_xp, result)

func _precompute_side(unit_states: Array[UnitData], total_xp: int, result: BattleResult) -> void:
	var alive: Array[UnitData] = []
	for u in unit_states:
		if u.is_alive:
			alive.append(u)
	if alive.is_empty() or total_xp <= 0:
		return
	var xp_each := int(float(total_xp) / float(alive.size()))
	for unit in alive:
		var sim_xp := unit.xp + xp_each
		var sim_level := unit.level
		var sim_class := unit.class_id
		var sim_xp_to_next := unit.xp_to_next
		while sim_xp >= sim_xp_to_next:
			sim_xp -= sim_xp_to_next
			sim_level += 1
			sim_xp_to_next = 100 * sim_level
			var promo := _sim_check_promotion(sim_class, sim_level)
			var event := {"unit_name": unit.unit_name, "new_level": sim_level, "promoted_to": promo}
			result.level_up_events.append(event)
			if promo != "":
				sim_class = promo

func _sim_check_promotion(class_id: String, level: int) -> String:
	var cls: ClassDefinition = UnitRegistry.get_class_def(class_id) as ClassDefinition
	if not cls:
		return ""
	for promo in cls.promotions:
		if level >= promo.required_level:
			return promo.target_class_id
	return ""

func _get_map_manager() -> MapManager:
	return get_tree().current_scene.get_node_or_null("MapManager") as MapManager
