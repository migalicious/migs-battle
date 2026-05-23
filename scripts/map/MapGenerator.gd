class_name MapGenerator

# Returns { "terrain": Array[Array[int]], "towns": Array[Dictionary], "seed": int }
static func generate(params: MapParams) -> Dictionary:
	var actual_seed: int = params.map_seed if params.map_seed != 0 else randi()
	var grid: Array = []
	var attempts: int = 0

	while attempts < 20:
		grid = _gen_terrain(params, actual_seed)
		if _valid_continent(grid, params):
			break
		actual_seed = randi()
		attempts += 1

	var towns: Array = _place_towns(grid, params)
	_flatten_town_cells(grid, towns)
	_apply_roads(grid, params, towns)
	_mark_coastal_towns(towns, grid)

	return {"terrain": grid, "towns": towns, "seed": actual_seed}

# ── Terrain generation ────────────────────────────────────────────────────────

static func _gen_terrain(params: MapParams, noise_seed: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = 0.05

	var fnoise := FastNoiseLite.new()
	fnoise.seed = noise_seed + 9973
	fnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnoise.frequency = 0.12

	var grid: Array = []
	for x in range(params.width):
		var col: Array = []
		for z in range(params.height):
			var v: float = (noise.get_noise_2d(x, z) + 1.0) * 0.5
			var t: int
			if   v < params.water_threshold:    t = TerrainDefs.TerrainType.WATER
			elif v < 0.45:                      t = TerrainDefs.TerrainType.PLAINS
			elif v < params.mountain_threshold: t = TerrainDefs.TerrainType.GRASS
			else:                               t = TerrainDefs.TerrainType.MOUNTAIN

			if t == TerrainDefs.TerrainType.GRASS:
				var fv: float = (fnoise.get_noise_2d(x, z) + 1.0) * 0.5
				if fv > 1.0 - params.forest_coverage:
					t = TerrainDefs.TerrainType.FOREST
			col.append(t)
		grid.append(col)
	return grid

static func _valid_continent(grid: Array, params: MapParams) -> bool:
	var cx: int = int(params.width  * 0.5)
	var cz: int = int(params.height * 0.5)
	if grid[cx][cz] == TerrainDefs.TerrainType.WATER:
		return false

	var total_land: int = 0
	for x in range(params.width):
		for z in range(params.height):
			if grid[x][z] != TerrainDefs.TerrainType.WATER:
				total_land += 1
	if total_land == 0:
		return false

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	queue.append(Vector2i(cx, cz))
	visited[Vector2i(cx, cz)] = true
	var filled: int = 0
	var dirs: Array = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		filled += 1
		for d in dirs:
			var dir: Vector2i = d
			var n := Vector2i(cell.x + dir.x, cell.y + dir.y)
			if n.x < 0 or n.x >= params.width or n.y < 0 or n.y >= params.height:
				continue
			if visited.has(n):
				continue
			if grid[n.x][n.y] == TerrainDefs.TerrainType.WATER:
				continue
			visited[n] = true
			queue.append(n)

	return float(filled) / float(total_land) >= 0.40

# ── Town placement ────────────────────────────────────────────────────────────

static func _is_placeable(grid: Array, x: int, z: int) -> bool:
	var t: int = grid[x][z]
	return t != TerrainDefs.TerrainType.WATER and t != TerrainDefs.TerrainType.MOUNTAIN

static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

static func _is_far_enough(pos: Vector2i, others: Array, min_dist: int) -> bool:
	for o in others:
		var ov: Vector2i = o
		if ov == Vector2i(-1, -1):
			continue
		if _chebyshev(pos, ov) < min_dist:
			return false
	return true

static func _find_in_region(grid: Array, _params: MapParams,
		x0: int, x1: int, z0: int, z1: int, exclude: Array, min_dist: int) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for x in range(x0, x1):
		for z in range(z0, z1):
			if _is_placeable(grid, x, z) and _is_far_enough(Vector2i(x, z), exclude, min_dist):
				candidates.append(Vector2i(x, z))
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	# Fallback: any land in range
	for x in range(x0, x1):
		for z in range(z0, z1):
			if _is_placeable(grid, x, z):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

# HQ placement quadrants: [x_min_frac, x_max_frac, z_min_frac, z_max_frac]
const HQ_REGIONS: Dictionary = {
	0: [0.0,   0.333, 0.667, 1.0  ],
	1: [0.667, 1.0,   0.0,   0.333],
	2: [0.667, 1.0,   0.667, 1.0  ],
	3: [0.0,   0.333, 0.0,   0.333],
}

static func _place_towns(grid: Array, params: MapParams) -> Array:
	var towns: Array = []
	var placed: Array[Vector2i] = []

	# Place one HQ per active faction using quadrant regions
	for faction in params.active_factions:
		var region: Array = HQ_REGIONS.get(faction, [0.4, 0.6, 0.4, 0.6]) as Array
		var x0 := int(params.width  * float(region[0]))
		var x1 := int(params.width  * float(region[1]))
		var z0 := int(params.height * float(region[2]))
		var z1 := int(params.height * float(region[3]))
		var hq_pos := _find_in_region(grid, params, x0, x1, z0, z1, placed, 0)
		if hq_pos != Vector2i(-1, -1):
			towns.append({"town_id": "%d_hq" % faction, "town_type": TerrainDefs.TownType.HQ,
				"faction": faction, "grid_x": hq_pos.x, "grid_z": hq_pos.y})
			placed.append(hq_pos)

	# Neutral towns and castles
	var extra_castles: int = maxi(0, params.num_castles - int(params.active_factions.size()))
	extra_castles = maxi(0, extra_castles)
	var neutral_total: int = extra_castles + params.num_towns
	var spawned: int = 0
	var tries: int   = 0

	while spawned < neutral_total and tries < 1000:
		tries += 1
		var x: int = randi_range(0, params.width  - 1)
		var z: int = randi_range(0, params.height - 1)
		var pos := Vector2i(x, z)
		if not _is_placeable(grid, x, z):
			continue
		# HQ positions are already in `placed`; min distance 4 from any placed town/HQ
		if not _is_far_enough(pos, placed, 4):
			continue
		var is_castle: bool = spawned < extra_castles
		var tid: String = "castle_%d" % spawned if is_castle else "town_%d" % spawned
		towns.append({"town_id": tid,
			"town_type": TerrainDefs.TownType.CASTLE if is_castle else TerrainDefs.TownType.TOWN,
			"faction": TerrainDefs.Faction.NEUTRAL, "grid_x": x, "grid_z": z})
		placed.append(pos)
		spawned += 1

	return towns

static func _mark_coastal_towns(towns: Array, grid: Array) -> void:
	for town_data in towns:
		town_data["has_aquatic_recruit"] = _is_coastal(grid, town_data["grid_x"], town_data["grid_z"])

static func _is_coastal(grid: Array, tx: int, tz: int, radius: int = 2) -> bool:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var nx := tx + dx
			var nz := tz + dz
			if nx >= 0 and nz >= 0 and nx < grid.size() and nz < grid[0].size():
				if grid[nx][nz] == TerrainDefs.TerrainType.WATER:
					return true
	return false

static func _flatten_town_cells(grid: Array, towns: Array) -> void:
	for t in towns:
		grid[t["grid_x"]][t["grid_z"]] = TerrainDefs.TerrainType.PLAINS

# ── Road pass (A*) ───────────────────────────────────────────────────────────

static func _apply_roads(grid: Array, params: MapParams, towns: Array) -> void:
	# Road connects faction-0 HQ to faction-1 HQ
	var phq := Vector2i(-1, -1)
	var ehq := Vector2i(-1, -1)
	for t in towns:
		if   t["town_id"] == "0_hq": phq = Vector2i(t["grid_x"], t["grid_z"])
		elif t["town_id"] == "1_hq": ehq = Vector2i(t["grid_x"], t["grid_z"])
	if phq == Vector2i(-1, -1) or ehq == Vector2i(-1, -1):
		return
	var path: Array[Vector2i] = _astar(grid, params, phq, ehq)
	for pos in path:
		var pv: Vector2i = pos
		var t: int = grid[pv.x][pv.y]
		if t != TerrainDefs.TerrainType.WATER and t != TerrainDefs.TerrainType.MOUNTAIN:
			grid[pv.x][pv.y] = TerrainDefs.TerrainType.ROAD

static func _astar(grid: Array, params: MapParams, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var open: Array    = [[0, start]]   # [f_cost, Vector2i]
	var from: Dictionary = {}
	var g:    Dictionary = {}
	g[start] = 0
	var dirs: Array = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	while not open.is_empty():
		open.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var entry: Array    = open.pop_front()
		var cur:   Vector2i = entry[1]

		if cur == goal:
			var path: Array[Vector2i] = []
			while from.has(cur):
				path.append(cur)
				cur = from[cur]
			path.reverse()
			return path

		for d in dirs:
			var dir: Vector2i = d
			var nxt := Vector2i(cur.x + dir.x, cur.y + dir.y)
			if nxt.x < 0 or nxt.x >= params.width or nxt.y < 0 or nxt.y >= params.height:
				continue
			var t: int = grid[nxt.x][nxt.y]
			if t == TerrainDefs.TerrainType.WATER or t == TerrainDefs.TerrainType.MOUNTAIN:
				continue
			var ng: int = (g[cur] as int) + 1
			if not g.has(nxt) or ng < (g[nxt] as int):
				g[nxt] = ng
				open.append([ng + abs(nxt.x - goal.x) + abs(nxt.y - goal.y), nxt])
				from[nxt] = cur

	return []
