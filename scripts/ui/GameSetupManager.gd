extends Node

const _CampaignDef = preload("res://scripts/campaign/CampaignDef.gd")

# ── Random Map Flow ───────────────────────────────────────────────────────────

func start_new_game() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/ui/MapConfigScreen.tscn")
	await get_tree().process_frame
	var screen := get_tree().current_scene
	if screen and screen.has_signal("config_ready"):
		screen.config_ready.connect(_on_config_ready, CONNECT_ONE_SHOT)
		screen.back_requested.connect(_on_back_requested, CONNECT_ONE_SHOT)

func _on_config_ready(params: MapParams, win_conditions: Array[String], active_factions: Array[int]) -> void:
	GameState.active_conditions = win_conditions
	GameState.active_factions = active_factions
	GameState._init_default_relations()
	GameState.pending_map_params = params
	get_tree().change_scene_to_file("res://scenes/ui/ArmyBuilderScreen.tscn")
	# Random-map flow: ArmyBuilder emits army_ready (it only self-transitions for
	# campaigns). Connect it here so "Start Battle" actually loads Main.
	await get_tree().process_frame
	var builder := get_tree().current_scene
	if builder and builder.has_signal("army_ready"):
		builder.army_ready.connect(_on_army_ready, CONNECT_ONE_SHOT)

func _on_army_ready(squads: Array[SquadData]) -> void:
	GameState.configured_squads = squads
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _on_back_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")

# ── Campaign Flow ─────────────────────────────────────────────────────────────

func start_campaign() -> void:
	GameState.reset()
	GameState.campaign_run_active = true
	GameState.campaign_def = _make_campaign_def()
	get_tree().change_scene_to_file("res://scenes/ui/DifficultyScreen.tscn")

func on_difficulty_chosen(permadeath: bool) -> void:
	GameState.difficulty_permadeath = permadeath
	get_tree().change_scene_to_file("res://scenes/ui/CampaignIntroScreen.tscn")

func on_campaign_begun() -> void:
	_start_campaign_scenario(0)

func _start_campaign_scenario(idx: int) -> void:
	var campaign: Variant = _ensure_campaign_def()
	GameState.current_scenario_idx = idx

	if idx < campaign.scenarios.size():
		_apply_scenario(campaign.scenarios[idx])

	if idx == 0:
		GameState.persistent_roster = []
		for entry in campaign.starting_units:
			var unit := UnitRegistry.create_unit(str(entry["class_id"]), int(entry["level"]))
			if unit:
				unit.unit_name = str(entry["unit_name"])
				unit.faction = TerrainDefs.Faction.PLAYER
				GameState.persistent_roster.append(unit)
		GameState.player_gold = int(campaign.starting_gold)

	# Snapshot current roster levels so ArmyBuilder can detect who leveled up
	GameState.pre_scenario_levels = {}
	for u in GameState.persistent_roster:
		GameState.pre_scenario_levels[u.unit_name] = u.level

	get_tree().change_scene_to_file("res://scenes/ui/ArmyBuilderScreen.tscn")

func prepare_campaign_scenario(idx: int) -> void:
	var campaign: Variant = _ensure_campaign_def()
	GameState.current_scenario_idx = idx
	if idx < campaign.scenarios.size():
		_apply_scenario(campaign.scenarios[idx])
	# Snapshot roster levels so ArmyBuilder can highlight who leveled up
	GameState.pre_scenario_levels = {}
	for u in GameState.persistent_roster:
		GameState.pre_scenario_levels[u.unit_name] = u.level

func _make_campaign_def():
	var c := _CampaignDef.new()
	c.build_default()
	return c

func _ensure_campaign_def():
	if GameState.campaign_def == null:
		GameState.campaign_def = _make_campaign_def()
	return GameState.campaign_def

func _apply_scenario(scenario) -> void:
	var params := MapParams.new()
	params.map_seed    = int(scenario.map_seed)
	params.width       = int(scenario.map_width)
	params.height      = int(scenario.map_height)
	params.num_towns   = int(scenario.num_towns)
	params.num_castles = int(scenario.num_castles)

	var factions: Array[int] = []
	for f in scenario.active_factions:
		factions.append(int(f))
	params.active_factions = factions

	GameState.pending_map_params = params
	GameState.active_factions    = factions
	GameState.active_conditions  = []
	for wc in scenario.win_conditions:
		GameState.active_conditions.append(str(wc))

	_apply_faction_preset(str(scenario.faction_preset), factions)

func _apply_faction_preset(preset: String, factions: Array[int]) -> void:
	GameState.active_factions = factions
	GameState._init_default_relations()
	if preset == "alliance_b":
		GameState.set_relation(
			TerrainDefs.Faction.PLAYER,
			TerrainDefs.Faction.ENEMY_B,
			GameState.Relation.ALLIED)
	# "three_way" and "free_for_all" — all-hostile, already set by _init_default_relations
