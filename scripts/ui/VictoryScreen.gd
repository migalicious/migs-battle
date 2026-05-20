class_name VictoryScreen
extends CanvasLayer

var _result_label: Label = null
var _sub_label: Label = null

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

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var play_btn := Button.new()
	play_btn.text = "Play Again"
	play_btn.custom_minimum_size = Vector2(140.0, 44.0)
	play_btn.pressed.connect(_on_play_again_pressed)
	btn_row.add_child(play_btn)

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
	else:
		_result_label.text = "DEFEAT"
		_result_label.modulate = Color(1.0, 0.3, 0.3)
		_sub_label.text = "Your stronghold has been captured."
	visible = true

func _on_play_again_pressed() -> void:
	GameState.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()
