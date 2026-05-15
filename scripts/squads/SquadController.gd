extends Node3D

const _SQUAD_SCENE := preload("res://scenes/squads/Squad.tscn")

var _camera: Camera3D = null
var _map_manager: MapManager = null
var _inspector = null

var _selected_squad: Squad = null

func _ready() -> void:
	call_deferred("_init_refs")

func _init_refs() -> void:
	_camera = get_parent().get_node("Camera") as Camera3D
	_map_manager = get_parent().get_node("MapManager") as MapManager
	var hud := get_parent().get_node("HUD")
	if hud and hud.has_node("SquadInspector"):
		_inspector = hud.get_node("SquadInspector")
	_spawn_squads()

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_squads() -> void:
	_spawn_player_squads()
	_spawn_enemy_squads()

func _spawn_player_squads() -> void:
	var hq := _map_manager.get_hq(TerrainDefs.Faction.PLAYER)
	var base_pos := Vector3.ZERO
	if hq:
		base_pos = hq.global_position

	for i in range(2):
		var data := _build_player_squad(i)
		var sq: Squad = _SQUAD_SCENE.instantiate()
		add_child(sq)
		sq.global_position = Vector3(base_pos.x + (i - 0.5) * 4.0, 0.5, base_pos.z + 2.0)
		sq.setup(data)
		sq.squad_collided_with_enemy.connect(_on_squads_collided)
		GameState.player_squads.append(sq)

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
		sq.squad_collided_with_enemy.connect(_on_squads_collided)
		GameState.enemy_squads.append(sq)

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
		0: c0 = "knight";   c1 = "fighter"; n0 = "Dread Knight"; n1 = "Soldier"
		1: c0 = "archer";   c1 = "mage";    n0 = "Dark Archer";  n1 = "Shadow"
		2: c0 = "fighter";  c1 = "archer";  n0 = "Grunt";        n1 = "Minion"
		_: c0 = "cavalry";  c1 = "fighter"; n0 = "Scout";        n1 = "Runner"

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
		elif kb.keycode == KEY_SPACE:
			get_tree().paused = not get_tree().paused

func _handle_left_click(screen_pos: Vector2) -> void:
	# Check squads first (layer 2), then map/town (layer 1)
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
	var hit := _raycast_at(screen_pos, 1)
	if hit.is_empty():
		return
	var world_pos: Vector3 = hit["position"]
	var grid := _map_manager.world_to_grid(world_pos)
	var terrain := _map_manager.get_terrain(grid.x, grid.y)
	var spd := TerrainDefs.get_speed(_selected_squad.squad_data.movement_type, terrain)
	if spd == 0.0:
		return  # impassable; TODO: show "can't go there" indicator in M10
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
	if _inspector and _inspector.has_method("show_squad"):
		_inspector.show_squad(sq.squad_data)

func _deselect() -> void:
	if _selected_squad:
		_selected_squad.deselect_squad()
		_selected_squad = null
	if _inspector and _inspector.has_method("hide_inspector"):
		_inspector.hide_inspector()

# ── Battle ────────────────────────────────────────────────────────────────────

func _on_squads_collided(sq_a: Squad, sq_b: Squad) -> void:
	BattleManager.on_squads_collided(sq_a, sq_b)
