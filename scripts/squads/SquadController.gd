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
			_town_menu.ungarrison_requested.connect(_on_ungarrison_requested)
			_town_menu.merge_requested.connect(_on_merge_requested)
	_connect_town_signals()
	_spawn_squads()

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_squads() -> void:
	if GameState.is_loading_save:
		_restore_player_squads()
	else:
		_spawn_player_squads()
	# Enemy squads are spawned by AIFaction._setup()

func _spawn_player_squads() -> void:
	var hq := _map_manager.get_hq(TerrainDefs.Faction.PLAYER)
	var base_pos := Vector3.ZERO
	if hq:
		base_pos = hq.global_position

	var squads := GameState.configured_squads
	if squads.is_empty():
		squads = [_build_player_squad(0), _build_player_squad(1)]

	for i in range(squads.size()):
		var data: SquadData = squads[i]
		data.faction = TerrainDefs.Faction.PLAYER
		if i == 0:
			var sq: Squad = _SQUAD_SCENE.instantiate()
			add_child(sq)
			sq.global_position = Vector3(base_pos.x, 0.5, base_pos.z + 2.5)
			sq.setup(data)
			wire_squad(sq)
		else:
			GameState.reserve_squads.append(data)

func _restore_player_squads() -> void:
	var save_data: Dictionary = GameState.save_squad_data
	var hq := _map_manager.get_hq(TerrainDefs.Faction.PLAYER)
	var fallback_pos := Vector3.ZERO
	if hq:
		fallback_pos = hq.global_position

	for d in save_data.get("active", []):
		var sd := SaveSystem.deserialize_squad(d)
		sd.faction = TerrainDefs.Faction.PLAYER
		var world_pos := fallback_pos
		var gx: int = d.get("grid_x", -1)
		var gz: int = d.get("grid_z", -1)
		if gx >= 0 and gz >= 0:
			world_pos = _map_manager.grid_to_world(Vector2i(gx, gz))
		var sq: Squad = _SQUAD_SCENE.instantiate()
		add_child(sq)
		sq.global_position = Vector3(world_pos.x, 0.5, world_pos.z)
		sq.setup(sd)
		wire_squad(sq)

	for d in save_data.get("reserve", []):
		var sd := SaveSystem.deserialize_squad(d)
		sd.faction = TerrainDefs.Faction.PLAYER
		GameState.reserve_squads.append(sd)

	GameState.is_loading_save = false

func wire_squad(sq: Squad) -> void:
	sq.map_manager = _map_manager
	sq.squad_collided_with_enemy.connect(_on_squads_collided)
	sq.squad_arrived.connect(_on_squad_arrived)
	GameState.register_squad(sq)

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

	_add_unit(data, c0, n0, 0, 0, true, 8)
	_add_unit(data, c1, n1, 0, 1, false, 6)
	_add_unit(data, "knight", "Aldric", 0, 2, false, 6)
	_add_unit(data, c2, n2, 1, 0, false, 6)
	return data

func _add_unit(data: SquadData, class_id: String, unit_name: String, row: int, col: int, is_leader: bool, level: int = 1) -> void:
	var unit := UnitRegistry.create_unit(class_id, level)
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
		town.town_selected.connect(_on_town_selected)

func _on_town_selected(town: TownNode) -> void:
	if not _town_menu:
		return
	var town_faction: int = GameState.town_ownership.get(town.town_data.town_id, TerrainDefs.Faction.NEUTRAL)
	if town_faction == TerrainDefs.Faction.PLAYER:
		_town_menu.open(town, GameState.reserve_squads)
	else:
		_town_menu.open_info(town)

# ── Squad Arrival at Towns ────────────────────────────────────────────────────

func _on_squad_arrived(squad: Squad, pos: Vector3) -> void:
	var threshold: float = _map_manager.cell_size * 0.75
	for town in _map_manager.get_towns():
		var dx := pos.x - town.global_position.x
		var dz := pos.z - town.global_position.z
		if dx * dx + dz * dz < threshold * threshold:
			_handle_squad_at_town(squad, town)
			return

func _handle_squad_at_town(squad: Squad, town: TownNode) -> void:
	var town_faction: int = GameState.town_ownership.get(
		town.town_data.town_id, TerrainDefs.Faction.NEUTRAL)

	if town_faction == squad.faction:
		# Own town: player garrisons, AI squads pass through
		if squad.faction == TerrainDefs.Faction.PLAYER:
			squad.garrison_at(town)
			town.set_garrison(squad)
	elif is_instance_valid(town.garrisoned_squad) \
			and GameState.are_hostile(squad.faction, town.garrisoned_squad.faction):
		# Hostile garrison: trigger battle
		_on_squads_collided(squad, town.garrisoned_squad)
	elif town_faction != TerrainDefs.Faction.NEUTRAL \
			and not GameState.are_hostile(squad.faction, town_faction):
		# Allied faction town: pass through without capturing
		pass
	else:
		# Neutral or hostile undefended town: begin capture
		town.begin_capture(squad)

# ── Deploy Reserve Squad ──────────────────────────────────────────────────────

func _squad_deploy_cost(squad: SquadData) -> int:
	var total := 0
	for unit in squad.get_alive_units():
		var cls := UnitRegistry.get_class_def(unit.class_id) as ClassDefinition
		if cls:
			total += cls.deploy_cost
	return total

func _show_cant_afford(pos: Vector3, cost: int) -> void:
	var lbl := Label3D.new()
	lbl.text = "Need %dg!" % cost
	lbl.pixel_size = 0.025
	lbl.font_size = 16
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.3, 0.3)
	lbl.position = Vector3(pos.x, 2.5, pos.z)
	add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tween.tween_callback(lbl.queue_free)

func _on_deploy_requested(squad_data: SquadData, town: TownNode) -> void:
	var cost := _squad_deploy_cost(squad_data)
	if GameState.player_gold < cost:
		_show_cant_afford(town.global_position, cost)
		return
	GameState.player_gold -= cost
	GameState.gold_changed.emit(TerrainDefs.Faction.PLAYER, GameState.player_gold)

	var idx: int = GameState.reserve_squads.find(squad_data)
	if idx >= 0:
		GameState.reserve_squads.remove_at(idx)

	var sq: Squad = _SQUAD_SCENE.instantiate()
	add_child(sq)
	sq.global_position = Vector3(town.global_position.x, 0.5, town.global_position.z + 1.5)
	sq.setup(squad_data)
	wire_squad(sq)

# ── Squad Merge ───────────────────────────────────────────────────────────────

func _on_merge_requested(source: Squad, target: Squad) -> void:
	if not is_instance_valid(source) or not is_instance_valid(target):
		return
	_merge_squads(source, target)

func _merge_squads(source: Squad, target: Squad) -> void:
	var occupied: Dictionary = {}
	for u in target.squad_data.units:
		if u.is_alive:
			occupied[Vector2i(u.row, u.col)] = true

	var empty_slots: Array[Vector2i] = []
	for r in [0, 1]:
		for c in [0, 1, 2]:
			if not occupied.has(Vector2i(r, c)):
				empty_slots.append(Vector2i(r, c))

	var alive_units := source.squad_data.get_alive_units()
	var overflow: Array[UnitData] = []
	for i in range(alive_units.size()):
		var u: UnitData = alive_units[i]
		if i < empty_slots.size():
			u.row = empty_slots[i].x
			u.col = empty_slots[i].y
			u.faction = target.squad_data.faction
			target.squad_data.units.append(u)
		else:
			overflow.append(u)

	# Ensure target still has a leader; if not, promote first alive unit
	if not target.squad_data.get_leader():
		var first_alive := target.squad_data.get_alive_units()
		if not first_alive.is_empty():
			(first_alive[0] as UnitData).is_leader = true

	# Overflow: add to reserve if there's room
	if not overflow.is_empty():
		var overflow_sd := SquadData.new()
		overflow_sd.squad_id = "overflow_%d" % Time.get_ticks_msec()
		overflow_sd.faction = source.squad_data.faction
		for u in overflow:
			overflow_sd.units.append(u)
		if GameState.reserve_squads.size() < GameState.RESERVE_CAP:
			GameState.reserve_squads.append(overflow_sd)

	# If source was garrisoned, clear it from the town
	if source.is_garrisoned and source.garrison_town:
		source.garrison_town.clear_garrison()

	GameState.unregister_squad(source)
	source.queue_free()

	target.squad_data.recalculate_speed(TerrainDefs.TerrainType.PLAINS)

# ── Ungarrison ────────────────────────────────────────────────────────────────

func _on_ungarrison_requested(town: TownNode) -> void:
	if town.garrisoned_squad:
		var sq := town.garrisoned_squad
		town.clear_garrison()
		sq.ungarrison()

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
	var spd := TerrainDefs.get_speed(_selected_squad.squad_data.get_movement_type(), terrain)
	if spd == 0.0:
		_show_cant_go_there(world_pos)
		return
	var dest := _map_manager.grid_to_world(grid)
	_selected_squad.set_destination(dest)

func _show_cant_go_there(world_pos: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = "Can't go there!"
	lbl.pixel_size = 0.025
	lbl.font_size = 16
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.35, 0.35)
	lbl.position = Vector3(world_pos.x, 1.0, world_pos.z)
	add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.0, 0.7)
	tween.tween_callback(lbl.queue_free)

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
