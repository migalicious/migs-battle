extends Node

signal faction_won(faction_id: int)

enum Phase { OVERWORLD, IN_BATTLE, PAUSED, VICTORY, DEFEAT }

var current_phase: Phase = Phase.OVERWORLD
var map_seed: int = 0
var town_ownership: Dictionary = {}
var player_squads: Array = []
var enemy_squads: Array = []
var reserve_squads: Array = []

# Which win conditions are active this run
var active_conditions: Array[String] = ["hq_capture"]

var pending_map_params: MapParams = null

func _ready() -> void:
	pass

# ── Win Condition Checks ──────────────────────────────────────────────────────

func check_win_conditions() -> void:
	if current_phase != Phase.OVERWORLD:
		return
	var winner := -1
	if active_conditions.has("hq_capture"):
		winner = _check_hq_capture()
	if winner == -1 and active_conditions.has("all_strongholds"):
		winner = _check_all_strongholds()
	if winner != -1:
		trigger_end(winner)

func _check_hq_capture() -> int:
	var map_mgr := _get_map_manager()
	if not map_mgr:
		return -1
	for faction in [TerrainDefs.Faction.PLAYER, TerrainDefs.Faction.ENEMY]:
		var enemy_faction: int = TerrainDefs.Faction.ENEMY if faction == TerrainDefs.Faction.PLAYER else TerrainDefs.Faction.PLAYER
		var enemy_hq := map_mgr.get_hq(enemy_faction)
		if not enemy_hq:
			continue
		var hq_owner: int = int(town_ownership.get(enemy_hq.town_data.town_id, enemy_hq.town_data.starting_faction))
		if hq_owner == faction:
			return faction
	return -1

func _check_all_strongholds() -> int:
	var map_mgr := _get_map_manager()
	if not map_mgr:
		return -1
	var all_towns := map_mgr.get_towns()
	if all_towns.is_empty():
		return -1
	for faction in [TerrainDefs.Faction.PLAYER, TerrainDefs.Faction.ENEMY]:
		var owns_all := true
		for town in all_towns:
			var town_owner: int = int(town_ownership.get(town.town_data.town_id, town.town_data.starting_faction))
			if town_owner != faction:
				owns_all = false
				break
		if owns_all:
			return faction
	return -1

func trigger_end(winning_faction: int) -> void:
	if current_phase == Phase.VICTORY or current_phase == Phase.DEFEAT:
		return
	current_phase = Phase.VICTORY if winning_faction == TerrainDefs.Faction.PLAYER else Phase.DEFEAT
	get_tree().paused = true
	faction_won.emit(winning_faction)

# ── Reset ─────────────────────────────────────────────────────────────────────

func reset() -> void:
	current_phase = Phase.OVERWORLD
	map_seed = 0
	town_ownership = {}
	player_squads = []
	enemy_squads = []
	reserve_squads = []
	active_conditions = ["hq_capture"]
	pending_map_params = null

func _get_map_manager() -> MapManager:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("MapManager") as MapManager
