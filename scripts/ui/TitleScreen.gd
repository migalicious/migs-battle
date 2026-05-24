extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)

	var title := Label.new()
	title.text = "MIGS BATTLE"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "THE BLACK MARCH"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.7, 0.5)
	subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	vbox.add_child(subtitle)

	vbox.add_child(_spacer(16))

	_add_btn(vbox, "New Campaign", false, _on_new_campaign)

	var cont_campaign_btn := _add_btn(vbox, "Continue Campaign",
		not SaveSystem.load_exists_campaign(), _on_continue_campaign)
	cont_campaign_btn.modulate = Color(0.8, 0.9, 1.0) if SaveSystem.load_exists_campaign() else Color(0.6, 0.6, 0.6)

	_add_btn(vbox, "Random Map", false, _on_random_map)

	vbox.add_child(_spacer(8))

	_add_btn(vbox, "Quit", false, func() -> void: get_tree().quit())

func _add_btn(parent: VBoxContainer, label: String, disabled: bool, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(220, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.disabled = disabled
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _on_new_campaign() -> void:
	GameSetupManager.start_campaign()

func _on_continue_campaign() -> void:
	SaveSystem.load_game()

func _on_random_map() -> void:
	GameSetupManager.start_new_game()
