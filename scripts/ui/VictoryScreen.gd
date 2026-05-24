class_name VictoryScreen
extends CanvasLayer

var _result_label: Label = null
var _sub_label: Label = null
var _seed_label: Label = null
var _play_btn: Button = null
var _campaign_btn: Button = null
var _is_player_victory: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false
	_build_ui()
	GameState.faction_won.connect(_on_faction_won)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.80)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -240.0
	vbox.offset_right  =  240.0
	vbox.offset_top    = -150.0
	vbox.offset_bottom =  150.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	add_child(vbox)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 52)
	vbox.add_child(_result_label)

	_sub_label = Label.new()
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_sub_label)

	_seed_label = Label.new()
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.add_theme_font_size_override("font_size", 14)
	_seed_label.modulate = Color(0.75, 0.75, 0.75)
	vbox.add_child(_seed_label)

	var copy_btn := Button.new()
	copy_btn.text = "Copy Seed"
	copy_btn.custom_minimum_size = Vector2(120.0, 36.0)
	copy_btn.pressed.connect(func() -> void: DisplayServer.clipboard_set(str(GameState.map_seed)))
	vbox.add_child(copy_btn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_play_btn = Button.new()
	_play_btn.text = "Play Again"
	_play_btn.custom_minimum_size = Vector2(140.0, 44.0)
	_play_btn.pressed.connect(_on_play_again_pressed)
	btn_row.add_child(_play_btn)

	_campaign_btn = Button.new()
	_campaign_btn.text = "Continue Campaign"
	_campaign_btn.custom_minimum_size = Vector2(210.0, 44.0)
	_campaign_btn.pressed.connect(_on_campaign_btn_pressed)
	_campaign_btn.visible = false
	btn_row.add_child(_campaign_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(100.0, 44.0)
	quit_btn.pressed.connect(func(): get_tree().quit())
	btn_row.add_child(quit_btn)

func _on_faction_won(winning_faction: int) -> void:
	_is_player_victory = (winning_faction == TerrainDefs.Faction.PLAYER)

	if _is_player_victory:
		_result_label.modulate = Color(0.35, 1.0, 0.35)
		_sub_label.text = "The enemy stronghold has fallen."

		if GameState.campaign_run_active:
			GameState.collect_survivors()
			GameState.campaign_retry = false
			_play_btn.visible = false
			_campaign_btn.visible = true
			# Check if this was the final scenario
			var cdef = GameState.campaign_def
			if cdef != null and GameState.current_scenario_idx >= cdef.scenarios.size() - 1:
				_result_label.text = "CAMPAIGN COMPLETE!"
				_result_label.modulate = Color(1.0, 0.9, 0.1)
				_sub_label.text = "The Black March is over. Victory is yours!"
				_campaign_btn.text = "Return to Title"
			else:
				_result_label.text = "VICTORY!"
				_campaign_btn.text = "Continue Campaign →"
		else:
			_result_label.text = "VICTORY!"
	else:
		_result_label.text = "DEFEAT"
		_result_label.modulate = Color(1.0, 0.3, 0.3)
		_sub_label.text = "Your stronghold has been captured."

		if GameState.campaign_run_active:
			GameState.collect_survivors()
			GameState.campaign_retry = true
			_play_btn.visible = false
			_campaign_btn.visible = true
			if GameState.difficulty_permadeath and not _has_leader_survivors():
				_campaign_btn.text = "Campaign Over — Return to Title"
			else:
				_campaign_btn.text = "Retry Scenario"

	if _seed_label:
		_seed_label.text = "Map Seed: %d" % GameState.map_seed
	visible = true

func _on_play_again_pressed() -> void:
	GameState.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_campaign_btn_pressed() -> void:
	get_tree().paused = false

	# Permadeath with no leaders: campaign over
	if GameState.campaign_retry and GameState.difficulty_permadeath and not _has_leader_survivors():
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
		return

	if _is_player_victory:
		GameState.current_scenario_idx += 1
		# Campaign complete: all scenarios done
		var cdef = GameState.campaign_def
		if cdef != null and GameState.current_scenario_idx >= cdef.scenarios.size():
			GameState.reset()
			get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
			return

	# Prepare the next (or same, if retrying) scenario and go to transition screen
	GameSetupManager.prepare_campaign_scenario(GameState.current_scenario_idx)
	get_tree().change_scene_to_file("res://scenes/ui/CampaignTransitionScreen.tscn")

func _has_leader_survivors() -> bool:
	for u in GameState.persistent_roster:
		if not u.is_alive:
			continue
		var cls := UnitRegistry.get_class_def(u.class_id)
		if cls and cls.can_lead:
			return true
	return false
