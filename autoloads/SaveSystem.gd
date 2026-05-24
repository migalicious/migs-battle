extends Node

const SAVE_PATH := "user://savegame.cfg"

# ── Public API ────────────────────────────────────────────────────────────────

func load_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save() -> void:
	var cfg := ConfigFile.new()
	var mm := _get_map_manager()

	# Map params
	var p: MapParams = GameState.last_map_params
	if p:
		cfg.set_value("map", "seed",        GameState.map_seed)
		cfg.set_value("map", "width",        p.width)
		cfg.set_value("map", "height",       p.height)
		cfg.set_value("map", "num_towns",    p.num_towns)
		cfg.set_value("map", "num_castles",  p.num_castles)
		cfg.set_value("map", "water_threshold",    p.water_threshold)
		cfg.set_value("map", "mountain_threshold", p.mountain_threshold)
		cfg.set_value("map", "forest_coverage",    p.forest_coverage)

	# Game state
	cfg.set_value("state", "player_gold",       GameState.player_gold)
	cfg.set_value("state", "active_factions",   GameState.active_factions)
	cfg.set_value("state", "faction_relations", GameState.faction_relations)
	cfg.set_value("state", "active_conditions", GameState.active_conditions)
	cfg.set_value("state", "town_ownership",    GameState.town_ownership)
	cfg.set_value("state", "player_inventory",  GameState.player_inventory)

	# Active player squads (on the field)
	var active_arr: Array = []
	for sq in GameState.player_squads:
		if not is_instance_valid(sq):
			continue
		var grid := Vector2i(-1, -1)
		if mm:
			grid = mm.world_to_grid(sq.global_position)
		active_arr.append(_serialize_squad(sq.squad_data, grid))
	cfg.set_value("squads", "active",  active_arr)

	# Reserve squads
	var reserve_arr: Array = []
	for sd in GameState.reserve_squads:
		if sd is SquadData:
			reserve_arr.append(_serialize_squad(sd as SquadData))
	cfg.set_value("squads", "reserve", reserve_arr)

	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	GameState.reset()

	# Restore map params
	var p := MapParams.new()
	p.map_seed           = cfg.get_value("map", "seed",               0)
	p.width              = cfg.get_value("map", "width",              32)
	p.height             = cfg.get_value("map", "height",             32)
	p.num_towns          = cfg.get_value("map", "num_towns",           6)
	p.num_castles        = cfg.get_value("map", "num_castles",         2)
	p.water_threshold    = cfg.get_value("map", "water_threshold",   0.38)
	p.mountain_threshold = cfg.get_value("map", "mountain_threshold",0.72)
	p.forest_coverage    = cfg.get_value("map", "forest_coverage",   0.30)

	var saved_factions: Array = cfg.get_value("state", "active_factions", [0, 1])
	var factions: Array[int] = []
	for f in saved_factions:
		factions.append(int(f))
	p.active_factions = factions

	GameState.active_factions   = factions
	GameState._init_default_relations()
	# Restore saved relations (may override defaults e.g. for Alliance presets)
	var saved_relations: Dictionary = cfg.get_value("state", "faction_relations", {})
	for key in saved_relations:
		GameState.faction_relations[key] = saved_relations[key]
	GameState.active_conditions = cfg.get_value("state", "active_conditions", ["hq_capture"])
	GameState.player_gold       = cfg.get_value("state", "player_gold", 100)
	GameState.town_ownership    = cfg.get_value("state", "town_ownership",   {})
	GameState.player_inventory  = cfg.get_value("state", "player_inventory", {})

	# Deserialize squads
	var active_raw:  Array = cfg.get_value("squads", "active",  [])
	var reserve_raw: Array = cfg.get_value("squads", "reserve", [])
	GameState.save_squad_data = {"active": active_raw, "reserve": reserve_raw}

	GameState.is_loading_save   = true
	GameState.pending_map_params = p

	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

# ── Serialization ─────────────────────────────────────────────────────────────

func _serialize_squad(sd: SquadData, grid: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var units_arr: Array = []
	for u in sd.units:
		units_arr.append(_serialize_unit(u))
	return {
		"squad_id": sd.squad_id,
		"faction":  sd.faction,
		"grid_x":   grid.x,
		"grid_z":   grid.y,
		"units":    units_arr,
	}

func _serialize_unit(u: UnitData) -> Dictionary:
	return {
		"unit_name":    u.unit_name,
		"class_id":     u.class_id,
		"faction":      u.faction,
		"row":          u.row,
		"col":          u.col,
		"hp":           u.hp,
		"max_hp":       u.max_hp,
		"strength":     u.strength,
		"agility":      u.agility,
		"intelligence": u.intelligence,
		"defense":      u.defense,
		"resistance":   u.resistance,
		"level":        u.level,
		"xp":           u.xp,
		"xp_to_next":   u.xp_to_next,
		"is_alive":     u.is_alive,
		"is_leader":    u.is_leader,
		"is_wounded":   u.is_wounded,
		"held_item":    u.held_item,
	}

# ── Deserialization (called from SquadController) ─────────────────────────────

func deserialize_squad(d: Dictionary) -> SquadData:
	var sd := SquadData.new()
	sd.squad_id = d.get("squad_id", "saved_squad")
	sd.faction  = d.get("faction", TerrainDefs.Faction.PLAYER)
	for ud in d.get("units", []):
		sd.units.append(deserialize_unit(ud))
	sd.recalculate_speed(TerrainDefs.TerrainType.PLAINS)
	return sd

func deserialize_unit(d: Dictionary) -> UnitData:
	var u := UnitRegistry.create_unit(d.get("class_id", "fighter"), d.get("level", 1))
	u.unit_name    = d.get("unit_name",    u.unit_name)
	u.faction      = d.get("faction",      u.faction)
	u.row          = d.get("row",          0)
	u.col          = d.get("col",          0)
	u.hp           = d.get("hp",           u.hp)
	u.max_hp       = d.get("max_hp",       u.max_hp)
	u.strength     = d.get("strength",     u.strength)
	u.agility      = d.get("agility",      u.agility)
	u.intelligence = d.get("intelligence", u.intelligence)
	u.defense      = d.get("defense",      u.defense)
	u.resistance   = d.get("resistance",   u.resistance)
	u.level        = d.get("level",        1)
	u.xp           = d.get("xp",           0)
	u.xp_to_next   = d.get("xp_to_next",   100)
	u.is_alive     = d.get("is_alive",     true)
	u.is_leader    = d.get("is_leader",    false)
	u.is_wounded   = d.get("is_wounded",   false)
	u.held_item    = d.get("held_item",    "")
	return u

func _get_map_manager() -> MapManager:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("MapManager") as MapManager
