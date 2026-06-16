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

# Clear all in-battle state. MUST be called when a scenario starts/restarts: if a run
# ends while a battle is mid-resolution (e.g. a timeout/restart before the result screen
# is dismissed), `_in_battle` would otherwise stay true forever and silently block EVERY
# future collision — the campaign would load with zero battles possible. Also frees any
# orphaned battle scene left under the tree root by an interrupted battle.
func reset() -> void:
	_in_battle = false
	_current_attacker = null
	_current_defender = null
	_current_result = null
	var root := get_tree().root
	for child in root.get_children():
		if child is BattleAnimator:
			child.queue_free()

func on_squads_collided(sq_a: Squad, sq_b: Squad) -> void:
	if not is_instance_valid(sq_a) or not is_instance_valid(sq_b):
		return  # a deferred collision signal can fire after a squad was freed
	if _in_battle or sq_a.in_battle or sq_b.in_battle:
		return
	if not GameState.are_hostile(sq_a.faction, sq_b.faction):
		return

	_in_battle = true
	sq_a.in_battle = true
	sq_b.in_battle = true
	_current_attacker = sq_a
	_current_defender = sq_b

	GameState.current_phase = GameState.Phase.IN_BATTLE

	var _mm := get_tree().current_scene.get_node_or_null("MapManager") as MapManager
	var atk_on_water := false
	var def_on_water := false
	if _mm:
		var _WATER := TerrainDefs.TerrainType.WATER
		var _ag := _mm.world_to_grid(sq_a.global_position)
		var _dg := _mm.world_to_grid(sq_b.global_position)
		atk_on_water = _mm.get_terrain(_ag.x, _ag.y) == _WATER
		def_on_water = _mm.get_terrain(_dg.x, _dg.y) == _WATER
	# NO pre-battle healing. Wounds persist between encounters for both sides; the ONLY
	# way to recover is to retreat to a player-owned building and heal in garrison. Free
	# pre-battle healing would make retreating pointless and enemy forces unkillable.
	_current_result = BattleResolver.resolve(sq_a.squad_data, sq_b.squad_data, atk_on_water, def_on_water)
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
	if GameState.current_phase == GameState.Phase.OVERWORLD:
		SaveSystem.save()

# ── Result Application ────────────────────────────────────────────────────────

func _apply_result() -> void:
	# Guard against a participant that was freed before the result applies (e.g. a
	# squad wiped/retreated via a deferred collision signal). Previously this crashed.
	var atk_ok := is_instance_valid(_current_attacker) and _current_attacker.squad_data != null
	var def_ok := is_instance_valid(_current_defender) and _current_defender.squad_data != null

	if atk_ok:
		_apply_unit_states(_current_attacker.squad_data, _current_result.attacker_unit_states)
		_grant_xp(_current_attacker.squad_data, _current_result.attacker_xp)
	if def_ok:
		_apply_unit_states(_current_defender.squad_data, _current_result.defender_unit_states)
		_grant_xp(_current_defender.squad_data, _current_result.defender_xp)

	if atk_ok:
		if _current_result.attacker_wiped:
			_handle_loser(_current_attacker)
		else:
			_current_attacker.in_battle = false

	if def_ok:
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
				if unit.is_alive:
					unit.is_wounded = float(unit.hp) / float(maxi(unit.max_hp, 1)) < 0.25
				else:
					unit.is_wounded = false
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
	GameState.unregister_squad(squad)

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
		GameState.register_squad(squad)
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
			sim_xp_to_next = GameBalance.XP_THRESHOLD_BASE * sim_level
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
