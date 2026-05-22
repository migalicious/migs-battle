extends Node

func start_new_game() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/ui/MapConfigScreen.tscn")
	await get_tree().process_frame
	var screen := get_tree().current_scene
	if screen and screen.has_signal("config_ready"):
		screen.config_ready.connect(_on_config_ready, CONNECT_ONE_SHOT)
		screen.back_requested.connect(_on_back_requested, CONNECT_ONE_SHOT)

func _on_config_ready(params: MapParams, win_conditions: Array[String]) -> void:
	GameState.active_conditions = win_conditions
	GameState.pending_map_params = params
	get_tree().change_scene_to_file("res://scenes/ui/ArmyBuilderScreen.tscn")
	await get_tree().process_frame
	var screen := get_tree().current_scene
	if screen and screen.has_signal("army_ready"):
		screen.army_ready.connect(_on_army_ready, CONNECT_ONE_SHOT)

func _on_army_ready(squads: Array[SquadData]) -> void:
	GameState.configured_squads = squads
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _on_back_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
