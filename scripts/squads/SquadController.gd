class_name SquadController
extends Node3D

const _SQUAD_SCENE := preload("res://scenes/squads/Squad.tscn")

var _camera: Camera3D = null
var _map_manager: MapManager = null
var _inspector: SquadInspector = null
var _town_menu: TownMenu = null

var _selected_squad: Squad = null

func _ready() -> void:
	call_deferred("_init_refs")

func _init_refs() -> void:
	_camera = get_parent().get_node("Camera") as Camera3D
	_map_manager = get_parent().get_node("MapManager") as MapManager
	var hud := get_parent().get_node("HUD")
	if hud:
		if hud.has_node("SquadInspector"):
			_inspector = hud.get_node("SquadInspector") as SquadInspector
		if hud.has_node("TownMenu"):
			_town_menu = hud.get_node("TownMenu") as TownMenu
			_town_menu.deploy_requested.connect(_on_deploy_requested)
	_connect_town_signals()
	_spawn_squads()

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_squads() -> void:
	_spawn_player_squads()
	# Enemy squads are spawned by AIFaction._setup()

func _spawn_player_squads() -> void:
	var hq := _map_manager.get_hq(TerrainDefs.Faction.PLAYER)
	var base_pos := Vector3.ZERO
	if hq:
		base_pos = hq.global_position

	# Spawn squad 0 on the map near the player HQ
	var data0 := _build_player_squad(0)
	var sq0: Squad = _SQUAD_SCENE.instantiate()
	add_child(sq0)
	sq0.global_position = Vector3(base_pos.x, 0.5, base_pos.z + 2.5)
	sq0.setup(data0)
	wire_squad(sq0)
	GameState.player_squads.append(sq0)

	# Put squad 1 in reserve for TownMenu deployment
	var data1 := _build_player_squad(1)
	GameState.reserve_squads.append(data1)

func _spawn_enemy_squads() -> void:
	var enemy_towns := _map_manager.get_towns_by_faction(TerrainDefs.Faction.ENEMY)
	var count := mini(4, enemy_towns.size())
	for i in range(count):
		var town: TownNode = enemy_towns[i]
		var data := _build_enemy_squad(i)
		var sq: Squad = _SQUAD_SCENE.instantiate()
		add_child(sq)
		sq.global_position = Vector3(town.global_position.x, 0.5, town.global_position.z + 2.0)
		sq.setup(data)
		wire_squad(sq)
		GameState.enemy_squads.append(sq)

func wire_squad(sq: Squad) -> void:
	sq.squad_collided_with_enemy.connect(_on_squads_collided)
	sq.squad_arrived.connect(_on_squad_arrived)

# ── Squad Data Builders ───────────────────────────────────────────────────────

func _build_player_squad(idx: int) -> SquadData:
	var data := SquadData.new()
	data.squad_id = "player_%d" % idx
	data.faction = TerrainDefs.Faction.PLAYER

	var c0: String; var c1: String; var c2: String
	var n0: String; var n1: String; var n2: String
	if idx == 0:
		c0 = "fighter"; c1 = "archer"; c2 = "mage"
		n0 = "Roland"; n1 = "Sylvia"; n2 = "Merlin"
	else:
		c0 = "knight"; c1 = "fighter"; c2 = "archer"
		n0 = "Gawain"; n1 = "Bors"; n2 = "Tristan"

	_add_unit(data, c0, n0, 0, 0, true)
	_add_unit(data, c1, n1, 0, 1, false)
	_add_unit(data, c2, n2, 1, 0, false)
	return data

func _build_enemy_squad(idx: int) -> SquadData:
	var data := SquadData.new()
	data.squad_id = "enemy_%d" % idx
	data.faction = TerrainDefs.Faction.ENEMY

	var c0: String; var c1: String
	var n0: String; var n1: String
	match idx % 4:
		0: c0 = "knight";  c1 = "fighter"; n0 = "Dread Knight"; n1 = "Soldier"
		1: c0 = "archer";  c1 = "mage";    n0 = "Dark Archer";  n1 = "Shadow"
		2: c0 = "fighter"; c1 = "archer";  n0 = "Grunt";        n1 = "Minion"
		_: c0 = "cavalry"; c1 = "fighter"; n0 = "Scout";        n1 = "Runner"

	_add_unit(data, c0, n0, 0, 0, true)
	_add_unit(data, c1, n1, 1, 0, false)
	return data

func _add_unit(data: SquadData, class_id: String, unit_name: String, row: int, col: int, is_leader: bool) -> void:
	var unit := UnitRegistry.create_unit(class_id, 1)
	if not unit:
		return
	unit.unit_name = unit_name
	unit.row = row
	unit.col = col
	unit.faction = data.faction
	unit.is_leader = is_leader
	data.units.append(unit)

# ── Town Signals ──────────────────────────────────────────────────────────────

func _connect_town_signals() -> void:
	for town in _map_manager.get_towns():
		town.town_selected.connect(_on_town_selected.bind(town))

func _on_town_selected(town: TownNode) -> void:
	var town_faction: int = GameState.town_ownership.get(town.town_data.town_id, TerrainDefs.Faction.NEUTRAL)
	if town_faction == TerrainDefs.Faction.PLAYER and _town_menu:
		_town_menu.open(town, GameState.reserve_squads)

# ── Squad Arrival at Towns ────────────────────────────────────────────────────

func _on_squad_arrived(squad: Squad, pos: Vector3) -> void:
	var arrival_grid := _map_manager.world_to_grid(pos)
	for town in _map_manager.get_towns():
		if town.town_data.grid_x == arrival_grid.x and town.town_data.grid_z == arrival_grid.y:
			_handle_squad_at_town(squad, town)
			return

func _handle_squad_at_town(squad: Squad, town: TownNode) -> void:
	var town_faction: int = GameState.town_ownership.get(
		town.town_data.town_id, TerrainDefs.Faction.NEUTRAL)

	if town_faction == squad.faction:
		# Friendly town: only player squads garrison (AI squads keep moving)
		if squad.faction == TerrainDefs.Faction.PLAYER:
			squad.garrison_at(town)
			town.set_garrison(squad)
	elif town.garrisoned_squad != null and town.garrisoned_squad.faction != squad.faction:
		# Enemy garrison present: trigger battle
		_on_squads_collided(squad, town.garrisoned_squad)
	else:
		# Neutral or undefended enemy: begin capture
		town.begin_capture(squad)

# ── Deploy Reserve Squad ──────────────────────────────────────────────────────

func _on_deploy_requested(squad_data: SquadData, town: TownNode) -> void:
	var idx: int = GameState.reserve_squads.find(squad_data)
	if idx >= 0:
		GameState.reserve_squads.remove_at(idx)

	var sq: Squad = _SQUAD_SCENE.instantiate()
	add_child(sq)
	sq.global_position = Vector3(town.global_position.x, 0.5, town.global_position.z + 1.5)
	sq.setup(squad_data)
	wire_squad(sq)
	GameState.player_squads.append(sq)

# ── Retreat Helper ────────────────────────────────────────────────────────────

func retreat_squad(squad: Squad) -> void:
	var friendly := _map_manager.get_towns_by_faction(squad.faction)
	if friendly.is_empty():
		return
	var nearest: TownNode = friendly[0]
	var min_dist: float = squad.global_position.distance_to(nearest.global_position)
	for t in friendly:
		var d: float = squad.global_position.distance_to(t.global_position)
		if d < min_dist:
			min_dist = d
			nearest = t
	squad.retreat_to(nearest.global_position)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mb.position)
	elif event is InputEventKey:
		var kb := event as InputEventKey
		if not kb.pressed:
			return
		if kb.keycode == KEY_ESCAPE:
			_deselect()
			if _town_menu and _town_menu.visible:
				_town_menu.close()
		elif kb.keycode == KEY_SPACE:
			get_tree().paused = not get_tree().paused

func _handle_left_click(screen_pos: Vector2) -> void:
	var hit := _raycast_at(screen_pos, 2)
	if not hit.is_empty():
		var collider: Object = hit["collider"] as Object
		if collider is Squad:
			var sq := collider as Squad
			if sq.faction == TerrainDefs.Faction.PLAYER:
				_select(sq)
				return
	_deselect()

func _handle_right_click(screen_pos: Vector2) -> void:
	if not _selected_squad or not _map_manager:
		return
	# Ungarrison if currently garrisoned
	if _selected_squad.is_garrisoned:
		var gt := _selected_squad.garrison_town
		if gt:
			gt.clear_garrison()
		_selected_squad.ungarrison()

	var hit := _raycast_at(screen_pos, 1)
	if hit.is_empty():
		return
	var world_pos: Vector3 = hit["position"]
	var grid := _map_manager.world_to_grid(world_pos)
	var terrain := _map_manager.get_terrain(grid.x, grid.y)
	var spd := TerrainDefs.get_speed(_selected_squad.squad_data.movement_type, terrain)
	if spd == 0.0:
		return  # impassable; TODO M10: show "can't go there" indicator
	var dest := _map_manager.grid_to_world(grid)
	_selected_squad.set_destination(dest)

func _raycast_at(screen_pos: Vector2, mask: int) -> Dictionary:
	if not _camera:
		return {}
	var space := get_viewport().get_world_3d().direct_space_state
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	return space.intersect_ray(query)

func _select(sq: Squad) -> void:
	if _selected_squad == sq:
		return
	_deselect()
	_selected_squad = sq
	sq.select_squad()
	if _inspector:
		_inspector.show_squad(sq.squad_data)

func _deselect() -> void:
	if _selected_squad:
		_selected_squad.deselect_squad()
		_selected_squad = null
	if _inspector:
		_inspector.hide_inspector()

# ── Battle ────────────────────────────────────────────────────────────────────

func _on_squads_collided(sq_a: Squad, sq_b: Squad) -> void:
	BattleManager.on_squads_collided(sq_a, sq_b)
