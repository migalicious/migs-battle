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

	var new_btn := Button.new()
	new_btn.text = "New Game"
	new_btn.custom_minimum_size = Vector2(200, 52)
	new_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_btn.pressed.connect(_on_new_game)
	vbox.add_child(new_btn)

	var cont_btn := Button.new()
	cont_btn.text = "Continue"
	cont_btn.custom_minimum_size = Vector2(200, 52)
	cont_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cont_btn.disabled = not SaveSystem.load_exists()
	cont_btn.pressed.connect(_on_continue)
	vbox.add_child(cont_btn)

func _on_new_game() -> void:
	GameSetupManager.start_new_game()

func _on_continue() -> void:
	SaveSystem.load_game()
