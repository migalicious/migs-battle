extends Node

signal faction_won(faction_id: int)
signal gold_changed(faction: int, new_total: int)
signal faction_relation_changed(f_a: int, f_b: int, new_relation: int)

enum Phase { OVERWORLD, IN_BATTLE, PAUSED, VICTORY, DEFEAT }
enum Relation { HOSTILE, NEUTRAL_REL, ALLIED }

var current_phase: Phase = Phase.OVERWORLD
var map_seed: int = 0
var town_ownership: Dictionary = {}
var player_squads: Array = []
var enemy_squads: Array = []
var reserve_squads: Array = []
var faction_squads: Dictionary = {}   # faction_id -> Array[Squad]

# Which factions exist on this map
var active_factions: Array[int] = [0, 1]
# Relations between faction pairs. Key: "min_max" e.g. "0_1", value: Relation int
var faction_relations: Dictionary = {}

# Which win conditions are active this run
var active_conditions: Array[String] = ["hq_capture"]

const RESERVE_CAP: int = 5

var pending_map_params: MapParams = null
var configured_squads: Array[SquadData] = []
var last_map_params: MapParams = null

var persistent_roster: Array[UnitData] = []
var campaign_run_active: bool = false
var current_scenario_idx: int = 0
var difficulty_permadeath: bool = false
var campaign_def = null      # CampaignDef instance (untyped)
var campaign_retry: bool = false  # true when retrying same scenario after defeat
var pre_scenario_levels: Dictionary = {}  # unit_name -> level before the last scenario
var enemy_difficulty_mult: float = 1.0

var is_loading_save: bool = false
var save_squad_data: Dictionary = {}

var player_gold: int = 100
var enemy_gold: int = 100
var gold_tick_interval: float = GameBalance.GOLD_TICK_INTERVAL
var _gold_timer: float = 0.0
var player_inventory: Dictionary = {}

func _ready() -> void:
	_init_default_relations()

func _init_default_relations() -> void:
	faction_relations = {}
	# By default all non-player factions are hostile to player and to each other
	for i in range(active_factions.size()):
		for j in range(i + 1, active_factions.size()):
			set_relation(active_factions[i], active_factions[j], Relation.HOSTILE)

# ── Faction Relation API ──────────────────────────────────────────────────────

func get_relation(f_a: int, f_b: int) -> Relation:
	if f_a == f_b:
		return Relation.ALLIED
	return faction_relations.get(_relation_key(f_a, f_b), Relation.HOSTILE) as Relation

func set_relation(f_a: int, f_b: int, relation: Relation) -> void:
	faction_relations[_relation_key(f_a, f_b)] = int(relation)
	faction_relation_changed.emit(f_a, f_b, int(relation))

func are_hostile(f_a: int, f_b: int) -> bool:
	return get_relation(f_a, f_b) == Relation.HOSTILE

func _relation_key(f_a: int, f_b: int) -> String:
	return "%d_%d" % [mini(f_a, f_b), maxi(f_a, f_b)]

# ── Squad Registry ────────────────────────────────────────────────────────────

func register_squad(sq: Squad) -> void:
	var f: int = sq.faction
	if not faction_squads.has(f):
		faction_squads[f] = []
	(faction_squads[f] as Array).append(sq)
	if f == TerrainDefs.Faction.PLAYER:
		player_squads.append(sq)
	else:
		enemy_squads.append(sq)

func unregister_squad(sq: Squad) -> void:
	var f: int = sq.faction
	if faction_squads.has(f):
		(faction_squads[f] as Array).erase(sq)
	player_squads.erase(sq)
	enemy_squads.erase(sq)

func get_squads_by_faction(faction: int) -> Array:
	return faction_squads.get(faction, []) as Array

func _process(delta: float) -> void:
	if current_phase != Phase.OVERWORLD:
		return
	_gold_timer += delta
	if _gold_timer >= gold_tick_interval:
		_gold_timer = 0.0
		_collect_income()

func _collect_income() -> void:
	var map_mgr := _get_map_manager()
	if not map_mgr:
		return
	for town in map_mgr.get_towns():
		var town_owner: int = town_ownership.get(town.town_data.town_id, TerrainDefs.Faction.NEUTRAL)
		var income: int = town.town_data.income
		if town_owner == TerrainDefs.Faction.PLAYER:
			player_gold += income
			gold_changed.emit(TerrainDefs.Faction.PLAYER, player_gold)
		elif active_factions.has(town_owner) and town_owner != TerrainDefs.Faction.PLAYER:
			enemy_gold += income

# ── Win Condition Checks ──────────────────────────────────────────────────────

func check_win_conditions() -> void:
	if current_phase != Phase.OVERWORLD:
		return
	var winner := -1
	var has_strongholds := active_conditions.has("all_strongholds")
	if active_conditions.has("hq_capture"):
		var hq_result := _check_hq_capture()
		if hq_result == TerrainDefs.Faction.PLAYER:
			# On maps that also require all_strongholds, taking the enemy HQ alone
			# must NOT win — all_strongholds gates the victory. The player can still
			# LOSE here (handled below) if their own HQ falls.
			if not has_strongholds:
				winner = hq_result
		elif hq_result != -1:
			winner = hq_result  # non-player result => player HQ was captured (a loss)
	if winner == -1 and has_strongholds:
		winner = _check_all_strongholds()
	# Army-wipe defeat: if the player has no living units left to field (all squads
	# dead and no reserves), they cannot act — that is a loss.
	if winner == -1 and not _player_has_units():
		winner = _first_hostile_faction()  # any hostile faction "wins" => player DEFEAT
	if winner != -1:
		trigger_end(winner)

func _player_has_units() -> bool:
	for sq in player_squads:
		if is_instance_valid(sq) and sq.squad_data:
			for u in sq.squad_data.units:
				if (u as UnitData).is_alive:
					return true
	for sd in reserve_squads:
		if sd is SquadData:
			for u in (sd as SquadData).units:
				if (u as UnitData).is_alive:
					return true
	return false

func _first_hostile_faction() -> int:
	for f in active_factions:
		if f != TerrainDefs.Faction.PLAYER and are_hostile(TerrainDefs.Faction.PLAYER, f):
			return f
	return TerrainDefs.Faction.ENEMY_A

func _check_hq_capture() -> int:
	var map_mgr := _get_map_manager()
	if not map_mgr:
		return -1

	# Player wins if all hostile-faction HQs are captured by player
	var all_enemy_hqs_captured := true
	for faction in active_factions:
		if faction == TerrainDefs.Faction.PLAYER:
			continue
		if not are_hostile(TerrainDefs.Faction.PLAYER, faction):
			continue  # Allied factions don't count as targets
		var hq := map_mgr.get_hq(faction)
		if not hq:
			continue
		var hq_owner: int = int(town_ownership.get(hq.town_data.town_id, hq.town_data.starting_faction))
		if hq_owner != TerrainDefs.Faction.PLAYER:
			all_enemy_hqs_captured = false
	if all_enemy_hqs_captured and active_factions.size() > 1:
		return TerrainDefs.Faction.PLAYER

	# Player loses if their HQ is captured by any hostile faction
	var player_hq := map_mgr.get_hq(TerrainDefs.Faction.PLAYER)
	if player_hq:
		var player_hq_owner: int = int(town_ownership.get(
			player_hq.town_data.town_id, player_hq.town_data.starting_faction))
		if player_hq_owner != TerrainDefs.Faction.PLAYER:
			return player_hq_owner

	return -1

func _check_all_strongholds() -> int:
	# Win by owning every STRONGHOLD (HQ + castles). Plain towns are optional
	# liberate-for-reward objectives and do NOT count toward this condition.
	var map_mgr := _get_map_manager()
	if not map_mgr:
		return -1
	var strongholds: Array = []
	for town in map_mgr.get_towns():
		if town.town_data.is_stronghold():
			strongholds.append(town)
	if strongholds.is_empty():
		return -1
	for faction in active_factions:
		var owns_all := true
		for town in strongholds:
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
	faction_squads = {}
	active_factions = [0, 1]
	faction_relations = {}
	active_conditions = ["hq_capture"]
	pending_map_params = null
	configured_squads = []
	last_map_params = null
	is_loading_save = false
	save_squad_data = {}
	player_gold = 100
	enemy_gold = 100
	_gold_timer = 0.0
	player_inventory = {}
	persistent_roster = []
	campaign_run_active = false
	current_scenario_idx = 0
	difficulty_permadeath = false
	campaign_def = null
	campaign_retry = false
	pre_scenario_levels = {}
	enemy_difficulty_mult = 1.0
	_init_default_relations()

# ── Campaign Unit Persistence ─────────────────────────────────────────────────

func collect_survivors() -> void:
	persistent_roster = []
	for sq in player_squads:
		if not is_instance_valid(sq):
			continue
		for u in sq.squad_data.units:
			_roster_add(u)
	for sd in reserve_squads:
		for u in sd.units:
			_roster_add(u)

func _roster_add(u: UnitData) -> void:
	if difficulty_permadeath and not u.is_alive:
		return
	if not u.is_alive:
		u.hp = maxi(1, int(float(u.max_hp) * 0.25))
		u.is_alive = true
	persistent_roster.append(u)

func apply_between_map_recovery(unit: UnitData) -> void:
	if not unit.is_alive:
		unit.hp = maxi(1, int(float(unit.max_hp) * 0.25))
		unit.is_alive = true
	if float(unit.hp) / float(maxi(unit.max_hp, 1)) < 0.5:
		unit.hp = int(float(unit.max_hp) * 0.5)
	unit.is_wounded = float(unit.hp) / float(maxi(unit.max_hp, 1)) < 0.25

func _get_map_manager() -> MapManager:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("MapManager") as MapManager
