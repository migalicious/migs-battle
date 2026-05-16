class_name AIFaction
extends Node

const TICK_INTERVAL: float = 8.0
const MAX_AI_SQUADS: int = 4
const THREAT_RADIUS: float = 12.0

const _SQUAD_SCENE := preload("res://scenes/squads/Squad.tscn")

var tick_timer: float = 0.0

var _map_manager: MapManager = null
var _squad_controller: SquadController = null

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	_map_manager = get_parent().get_node("MapManager") as MapManager
	_squad_controller = get_parent().get_node("Squads") as SquadController
	if _map_manager and _squad_controller:
		_initial_spawn()

func _process(delta: float) -> void:
	if GameState.current_phase != GameState.Phase.OVERWORLD:
		return
	tick_timer += delta
	if tick_timer >= TICK_INTERVAL:
		tick_timer = 0.0
		_run_ai_tick()

# ── Spawning ──────────────────────────────────────────────────────────────────

func _initial_spawn() -> void:
	var spawn_points := _map_manager.get_towns_by_faction(TerrainDefs.Faction.ENEMY)
	var count := mini(spawn_points.size(), MAX_AI_SQUADS)
	for i in range(count):
		var town: TownNode = spawn_points[i]
		var data := _build_template(i)
		data.squad_id = "ai_%d" % i
		var sq: Squad = _SQUAD_SCENE.instantiate() as Squad
		_squad_controller.add_child(sq)
		sq.global_position = Vector3(town.global_position.x, 0.5, town.global_position.z + 2.0)
		sq.setup(data)
		_squad_controller.wire_squad(sq)
		GameState.enemy_squads.append(sq)

# ── Tick Loop ─────────────────────────────────────────────────────────────────

func _run_ai_tick() -> void:
	for sq in GameState.enemy_squads:
		if not is_instance_valid(sq):
			continue
		if sq.in_battle or sq.is_garrisoned:
			continue
		var objective := _assign_objective(sq)
		_execute_objective(sq, objective)

func _assign_objective(squad: Squad) -> Dictionary:
	if _hq_under_threat():
		var hq := _map_manager.get_hq(TerrainDefs.Faction.ENEMY)
		if hq:
			return {"type": "defend", "target": hq}

	var lost := _find_recently_lost_town()
	if lost:
		return {"type": "recapture", "target": lost}

	var neutral := _find_nearest_town_with_faction(squad.global_position, TerrainDefs.Faction.NEUTRAL)
	if neutral:
		return {"type": "capture", "target": neutral}

	var player_town := _find_nearest_town_with_faction(squad.global_position, TerrainDefs.Faction.PLAYER)
	if player_town:
		return {"type": "attack", "target": player_town}

	return {"type": "patrol", "target": _find_patrol_target(squad)}

func _execute_objective(squad: Squad, objective: Dictionary) -> void:
	var target: Node = objective["target"] as Node
	if not is_instance_valid(target):
		return
	# Offset slightly so multiple squads converging on the same town don't stack
	var base_pos: Vector3 = target.global_position
	var jitter := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	squad.set_destination(base_pos + jitter)

# ── Threat Detection ──────────────────────────────────────────────────────────

func _hq_under_threat() -> bool:
	var hq := _map_manager.get_hq(TerrainDefs.Faction.ENEMY)
	if not hq:
		return false
	for sq in GameState.player_squads:
		if is_instance_valid(sq) and sq.global_position.distance_to(hq.global_position) < THREAT_RADIUS:
			return true
	return false

# ── Town Finders ──────────────────────────────────────────────────────────────

func _find_recently_lost_town() -> TownNode:
	for town in _map_manager.get_towns():
		if town.town_data.starting_faction == TerrainDefs.Faction.ENEMY \
		   and town.faction != TerrainDefs.Faction.ENEMY:
			return town
	return null

func _find_nearest_town_with_faction(from: Vector3, faction: int) -> TownNode:
	var nearest: TownNode = null
	var nearest_dist := INF
	for town in _map_manager.get_towns():
		if town.faction == faction:
			var dist := from.distance_to(town.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = town
	return nearest

func _find_patrol_target(_squad: Squad) -> TownNode:
	var friendly := _map_manager.get_towns_by_faction(TerrainDefs.Faction.ENEMY)
	if not friendly.is_empty():
		return friendly[randi() % friendly.size()]
	var hq := _map_manager.get_hq(TerrainDefs.Faction.ENEMY)
	if hq:
		return hq
	# Fallback: any town
	var all_towns := _map_manager.get_towns()
	if not all_towns.is_empty():
		return all_towns[randi() % all_towns.size()]
	return null

# ── Squad Templates ───────────────────────────────────────────────────────────

func _build_template(template_idx: int) -> SquadData:
	match template_idx % 4:
		0: return _template_a()
		1: return _template_b()
		2: return _template_c()
		_: return _template_d()

func _template_a() -> SquadData:
	var d := SquadData.new()
	d.faction = TerrainDefs.Faction.ENEMY
	_add(d, "knight",  "Commander",  0, 0, true,  5)
	_add(d, "fighter", "Soldier",    0, 1, false, 3)
	_add(d, "fighter", "Grunt",      0, 2, false, 3)
	_add(d, "archer",  "Bowman",     1, 0, false, 3)
	_add(d, "archer",  "Scout",      1, 1, false, 3)
	return d

func _template_b() -> SquadData:
	var d := SquadData.new()
	d.faction = TerrainDefs.Faction.ENEMY
	_add(d, "knight", "Dark Knight",  0, 0, true,  5)
	_add(d, "knight", "Iron Guard",   0, 1, false, 5)
	_add(d, "mage",   "Shadow Mage",  1, 0, false, 4)
	_add(d, "mage",   "Hex Caster",   1, 1, false, 4)
	return d

func _template_c() -> SquadData:
	var d := SquadData.new()
	d.faction = TerrainDefs.Faction.ENEMY
	_add(d, "paladin", "Paladin Lord",  0, 0, true,  8)
	_add(d, "knight",  "Heavy Knight",  0, 1, false, 6)
	_add(d, "knight",  "Iron Guard",    0, 2, false, 6)
	_add(d, "archer",  "Veteran Bow",   1, 0, false, 6)
	_add(d, "mage",    "Battle Mage",   1, 1, false, 5)
	return d

func _template_d() -> SquadData:
	var d := SquadData.new()
	d.faction = TerrainDefs.Faction.ENEMY
	_add(d, "cavalry", "Scout Captain", 0, 0, true,  4)
	_add(d, "cavalry", "Rider",         0, 1, false, 4)
	_add(d, "archer",  "Marksman",      1, 0, false, 3)
	return d

func _add(data: SquadData, class_id: String, uname: String, row: int, col: int, is_leader: bool, level: int) -> void:
	var unit := UnitRegistry.create_unit(class_id, level)
	if not unit:
		return
	unit.unit_name = uname
	unit.row = row
	unit.col = col
	unit.faction = TerrainDefs.Faction.ENEMY
	unit.is_leader = is_leader
	data.units.append(unit)
