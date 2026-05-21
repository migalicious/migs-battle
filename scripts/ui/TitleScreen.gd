extends Control

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 32)
	add_child(vbox)

	var title := Label.new()
	title.text = "MIGS BATTLE"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	vbox.add_child(title)

	var btn := Button.new()
	btn.text = "New Game"
	btn.custom_minimum_size = Vector2(200, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_new_game)
	vbox.add_child(btn)

func _on_new_game() -> void:
	GameSetupManager.start_new_game()
