class_name DifficultyScreen
extends Control

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -260.0
	panel.offset_right  =  260.0
	panel.offset_top    = -240.0
	panel.offset_bottom =  240.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE DIFFICULTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Standard
	var std_lbl := Label.new()
	std_lbl.text = "Standard"
	std_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(std_lbl)

	var std_desc := Label.new()
	std_desc.text = "Fallen units recover between scenarios.\nFailed scenarios can be retried.\nRecommended for first-time players."
	std_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_ADAPTIVE
	std_desc.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(std_desc)

	var std_btn := Button.new()
	std_btn.text = "Play Standard"
	std_btn.custom_minimum_size = Vector2(200, 44)
	std_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	std_btn.pressed.connect(func() -> void: GameSetupManager.on_difficulty_chosen(false))
	vbox.add_child(std_btn)

	vbox.add_child(HSeparator.new())

	# Permadeath
	var pd_lbl := Label.new()
	pd_lbl.text = "Permadeath"
	pd_lbl.add_theme_font_size_override("font_size", 18)
	pd_lbl.modulate = Color(1.0, 0.5, 0.3)
	vbox.add_child(pd_lbl)

	var pd_desc := Label.new()
	pd_desc.text = "Fallen units are gone forever.\nIf no leader-capable units survive, the campaign ends.\nFor veterans only."
	pd_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_ADAPTIVE
	pd_desc.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(pd_desc)

	var pd_btn := Button.new()
	pd_btn.text = "Play Permadeath"
	pd_btn.custom_minimum_size = Vector2(200, 44)
	pd_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pd_btn.modulate = Color(1.0, 0.7, 0.5)
	pd_btn.pressed.connect(func() -> void: GameSetupManager.on_difficulty_chosen(true))
	vbox.add_child(pd_btn)

	vbox.add_child(HSeparator.new())

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(120, 40)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn"))
	vbox.add_child(back_btn)
