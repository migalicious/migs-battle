class_name MinimapPanel
extends Control

const MM_SIZE: int = 200

var _map_mgr: MapManager = null
var _camera: Camera3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_setup_refs")

func _setup_refs() -> void:
	var main := get_tree().current_scene
	if not main:
		return
	_map_mgr = main.get_node_or_null("MapManager") as MapManager
	_camera  = main.get_node_or_null("Camera") as Camera3D

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, MM_SIZE, MM_SIZE), Color(0.08, 0.08, 0.12))
	if not _map_mgr:
		return

	var W: int = _map_mgr.map_width
	var H: int = _map_mgr.map_height
	var cell_px: float = float(MM_SIZE) / float(maxi(W, H))

	# Terrain cells
	for x in range(W):
		for z in range(H):
			var t: TerrainDefs.TerrainType = _map_mgr.get_terrain(x, z)
			draw_rect(Rect2(x * cell_px, z * cell_px, cell_px + 0.5, cell_px + 0.5), _terrain_color(t))

	# Towns as colored dots
	for town in _map_mgr.get_towns():
		var px: float = town.town_data.grid_x * cell_px + cell_px * 0.5
		var pz: float = town.town_data.grid_z * cell_px + cell_px * 0.5
		draw_circle(Vector2(px, pz), maxf(cell_px * 0.9, 3.0), _faction_color(town.faction))

	# Player squads
	for sq in GameState.player_squads:
		if not is_instance_valid(sq):
			continue
		draw_circle(_world_to_mm(sq.global_position, W, H), 3.5, Color(0.25, 0.55, 1.0))

	# Enemy squads
	for sq in GameState.enemy_squads:
		if not is_instance_valid(sq):
			continue
		draw_circle(_world_to_mm(sq.global_position, W, H), 3.5, Color(1.0, 0.30, 0.30))

	# Camera viewport approximation
	if _camera:
		var center := _world_to_mm(
			Vector3(_camera.global_position.x, 0.0, _camera.global_position.z),
			W, H)
		var view_r: float = (_camera.global_position.y * 0.35 / (_map_mgr.cell_size * float(W))) * float(MM_SIZE)
		draw_rect(Rect2(center.x - view_r, center.y - view_r, view_r * 2.0, view_r * 2.0),
			Color(1.0, 1.0, 1.0, 0.75), false, 1.5)

	# Border
	draw_rect(Rect2(0, 0, MM_SIZE, MM_SIZE), Color(0.29, 0.29, 0.42), false, 1.5)

func _world_to_mm(world_pos: Vector3, W: int, H: int) -> Vector2:
	var half_w: float = float(W) * _map_mgr.cell_size * 0.5
	var half_h: float = float(H) * _map_mgr.cell_size * 0.5
	var nx: float = (world_pos.x + half_w) / (float(W) * _map_mgr.cell_size)
	var nz: float = (world_pos.z + half_h) / (float(H) * _map_mgr.cell_size)
	return Vector2(nx * float(MM_SIZE), nz * float(MM_SIZE))

func _terrain_color(t: TerrainDefs.TerrainType) -> Color:
	match t:
		TerrainDefs.TerrainType.WATER:    return Color(0.25, 0.45, 0.75)
		TerrainDefs.TerrainType.PLAINS:   return Color(0.76, 0.82, 0.56)
		TerrainDefs.TerrainType.GRASS:    return Color(0.35, 0.65, 0.35)
		TerrainDefs.TerrainType.FOREST:   return Color(0.15, 0.40, 0.15)
		TerrainDefs.TerrainType.MOUNTAIN: return Color(0.55, 0.55, 0.55)
		TerrainDefs.TerrainType.ROAD:     return Color(0.70, 0.60, 0.45)
		_: return Color.MAGENTA

func _faction_color(f: int) -> Color:
	match f:
		TerrainDefs.Faction.PLAYER: return Color(0.25, 0.55, 1.0)
		TerrainDefs.Faction.ENEMY:  return Color(1.0, 0.30, 0.30)
		_: return Color(0.70, 0.70, 0.70)
