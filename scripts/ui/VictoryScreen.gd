class_name VictoryScreen
extends CanvasLayer

var _result_label: Label = null
var _sub_label: Label = null
var _seed_label: Label = null
var _play_btn: Button = null
var _campaign_btn: Button = null

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
	vbox.offset_left   = -220.0
	vbox.offset_right  =  220.0
	vbox.offset_top    = -130.0
	vbox.offset_bottom =  130.0
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
	_campaign_btn.custom_minimum_size = Vector2(180.0, 44.0)
	_campaign_btn.pressed.connect(_on_campaign_continue_pressed)
	_campaign_btn.visible = false
	btn_row.add_child(_campaign_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(100.0, 44.0)
	quit_btn.pressed.connect(func(): get_tree().quit())
	btn_row.add_child(quit_btn)

func _on_faction_won(winning_faction: int) -> void:
	if winning_faction == TerrainDefs.Faction.PLAYER:
		_result_label.text = "VICTORY!"
		_result_label.modulate = Color(0.35, 1.0, 0.35)
		_sub_label.text = "The enemy stronghold has fallen."
		if GameState.campaign_run_active:
			GameState.collect_survivors()
			_play_btn.visible = false
			_campaign_btn.visible = true
	else:
		_result_label.text = "DEFEAT"
		_result_label.modulate = Color(1.0, 0.3, 0.3)
		_sub_label.text = "Your stronghold has been captured."
	if _seed_label:
		_seed_label.text = "Map Seed: %d" % GameState.map_seed
	visible = true

func _on_play_again_pressed() -> void:
	GameState.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_campaign_continue_pressed() -> void:
	GameState.current_scenario_idx += 1
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/CampaignTransitionScreen.tscn")
