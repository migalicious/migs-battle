class_name MapManager
extends Node3D

@export var map_width:   int   = 32
@export var map_height:  int   = 32
@export var cell_size:   float = 2.0
@export var map_seed:    int   = 0
@export var num_towns:   int   = 6
@export var num_castles: int   = 2

var _terrain_grid: Array = []   # [x][z] -> TerrainType int
var _cells: Array = []          # [x][z] -> MapCell
var _towns: Array[TownNode] = []

var _params: MapParams

const _CELL_SCENE := preload("res://scenes/map/MapCell.tscn")
const _TOWN_SCENE := preload("res://scenes/map/TownNode.tscn")

func _ready() -> void:
	if GameState.pending_map_params:
		_params = GameState.pending_map_params
		GameState.pending_map_params = null
	else:
		_params = MapParams.new()
		_params.width        = map_width
		_params.height       = map_height
		_params.cell_size    = cell_size
		_params.map_seed     = map_seed
		_params.num_towns    = num_towns
		_params.num_castles  = num_castles

	var cells_node := Node3D.new()
	cells_node.name = "MapCells"
	add_child(cells_node)

	var towns_node := Node3D.new()
	towns_node.name = "TownNodes"
	add_child(towns_node)

	GameState.last_map_params = _params

	var result := MapGenerator.generate(_params)
	_terrain_grid = result["terrain"]
	GameState.map_seed = result["seed"]

	# Persist actual seed so MapConfigScreen can offer replay
	var seed_cfg := ConfigFile.new()
	seed_cfg.set_value("map", "last_seed", GameState.map_seed)
	seed_cfg.save("user://map_config.cfg")

	_init_cell_array()
	_spawn_cells(cells_node)
	_spawn_towns(towns_node, result["towns"])
	if GameState.is_loading_save:
		_restore_town_factions()
	_build_navmesh()

# ── Spawning ──────────────────────────────────────────────────────────────────

func _init_cell_array() -> void:
	_cells = []
	for x in range(_params.width):
		var col: Array = []
		for _z in range(_params.height):
			col.append(null)
		_cells.append(col)

func _spawn_cells(container: Node3D) -> void:
	for x in range(_params.width):
		for z in range(_params.height):
			var terrain := _terrain_grid[x][z] as TerrainDefs.TerrainType
			var cell: MapCell = _CELL_SCENE.instantiate()
			cell.position = grid_to_world(Vector2i(x, z))
			container.add_child(cell)
			cell.setup(x, z, terrain, _params.cell_size)
			_cells[x][z] = cell

func _spawn_towns(container: Node3D, defs: Array) -> void:
	for d in defs:
		var data       := TownData.new()
		data.town_id   = d["town_id"]
		data.town_type = d["town_type"] as TerrainDefs.TownType
		data.income = _income_for_type(data.town_type)
		data.starting_faction = d["faction"]
		data.grid_x    = d["grid_x"]
		data.grid_z    = d["grid_z"]
		data.is_deploy_point = true
		data.has_aquatic_recruit = d.get("has_aquatic_recruit", false)

		var gpos   := Vector2i(data.grid_x, data.grid_z)
		var wp     := grid_to_world(gpos)
		var base_y := TerrainDefs.get_top_y(get_terrain(gpos.x, gpos.y))

		var town: TownNode = _TOWN_SCENE.instantiate()
		town.position = wp
		container.add_child(town)
		town.setup(data, base_y)
		_towns.append(town)

		if not GameState.is_loading_save:
			GameState.town_ownership[data.town_id] = data.starting_faction

# ── Navigation ────────────────────────────────────────────────────────────────

func _build_navmesh() -> void:
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_height    = 0.5
	nav_mesh.agent_radius    = 0.3
	nav_mesh.agent_max_climb = 0.35

	# Build a vertex grid so adjacent walkable cells share polygon edges.
	var half_w := _params.width  * 0.5
	var half_h := _params.height * 0.5
	var verts  := PackedVector3Array()
	var vidx   := {}   # Vector2i(vx, vz) -> int

	for vx in range(_params.width + 1):
		for vz in range(_params.height + 1):
			var wx := (vx - half_w) * _params.cell_size
			var wz := (vz - half_h) * _params.cell_size
			vidx[Vector2i(vx, vz)] = verts.size()
			verts.append(Vector3(wx, 0.2, wz))   # flat navmesh slightly above ground

	nav_mesh.vertices = verts

	for x in range(_params.width):
		for z in range(_params.height):
			var t: int = _terrain_grid[x][z]
			if t == TerrainDefs.TerrainType.WATER or t == TerrainDefs.TerrainType.MOUNTAIN:
				continue
			nav_mesh.add_polygon(PackedInt32Array([
				vidx[Vector2i(x,   z)],
				vidx[Vector2i(x+1, z)],
				vidx[Vector2i(x+1, z+1)],
				vidx[Vector2i(x,   z+1)],
			]))

	nav_region.navigation_mesh = nav_mesh

# ── Public API ────────────────────────────────────────────────────────────────

func get_cell(x: int, z: int) -> MapCell:
	if x < 0 or x >= _params.width or z < 0 or z >= _params.height:
		return null
	return _cells[x][z] as MapCell

func get_terrain(x: int, z: int) -> TerrainDefs.TerrainType:
	if x < 0 or x >= _params.width or z < 0 or z >= _params.height:
		return TerrainDefs.TerrainType.WATER
	return _terrain_grid[x][z] as TerrainDefs.TerrainType

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var gx := int(floor(world_pos.x / _params.cell_size + _params.width  * 0.5))
	var gz := int(floor(world_pos.z / _params.cell_size + _params.height * 0.5))
	return Vector2i(clampi(gx, 0, _params.width - 1), clampi(gz, 0, _params.height - 1))

func grid_to_world(grid: Vector2i) -> Vector3:
	var wx := (grid.x - _params.width  * 0.5 + 0.5) * _params.cell_size
	var wz := (grid.y - _params.height * 0.5 + 0.5) * _params.cell_size
	return Vector3(wx, 0.0, wz)

func get_towns() -> Array[TownNode]:
	return _towns

func get_towns_by_faction(faction: int) -> Array[TownNode]:
	var result: Array[TownNode] = []
	for t in _towns:
		if t.faction == faction:
			result.append(t)
	return result

func get_hq(faction: int) -> TownNode:
	for t in _towns:
		if t.town_data and t.town_data.town_type == TerrainDefs.TownType.HQ and t.town_data.starting_faction == faction:
			return t
	return null

func _restore_town_factions() -> void:
	for town in _towns:
		var saved_faction: int = GameState.town_ownership.get(
			town.town_data.town_id, town.town_data.starting_faction)
		town.faction = saved_faction
		_tween_town_colors(town, saved_faction)

func _tween_town_colors(town: TownNode, new_faction: int) -> void:
	if town._base_mat:
		town._base_mat.albedo_color = TerrainDefs.FACTION_COLORS.get(new_faction, Color(0.55, 0.55, 0.55))
	if town._tower_mat:
		town._tower_mat.albedo_color = TerrainDefs.FACTION_COLORS.get(new_faction, Color(0.55, 0.55, 0.55)).darkened(0.15)
	if town._flag_mat:
		town._flag_mat.albedo_color = TerrainDefs.FACTION_COLORS.get(new_faction, Color(0.55, 0.55, 0.55))

func _income_for_type(t: TerrainDefs.TownType) -> int:
	match t:
		TerrainDefs.TownType.TOWN:   return 15
		TerrainDefs.TownType.CASTLE: return 30
		TerrainDefs.TownType.HQ:     return 50
		_: return 0
