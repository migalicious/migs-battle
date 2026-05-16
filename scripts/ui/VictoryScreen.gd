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

	var btn := Button.new()
	btn.text = "Play Again"
	btn.custom_minimum_size = Vector2(160.0, 44.0)
	btn.pressed.connect(_on_play_again_pressed)
	vbox.add_child(btn)

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
