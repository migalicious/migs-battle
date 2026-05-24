class_name CampaignIntroScreen
extends Control

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -300.0
	panel.offset_right  =  300.0
	panel.offset_top    = -260.0
	panel.offset_bottom =  260.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var campaign := GameState.campaign_def
	var campaign_name := "The Black March"
	var first_name := "Border Skirmish"
	var first_desc := "A small border dispute. Test your forces."
	if campaign:
		campaign_name = campaign.campaign_name
		if campaign.scenarios.size() > 0:
			first_name = campaign.scenarios[0].scenario_name
			first_desc = campaign.scenarios[0].description

	var title := Label.new()
	title.text = campaign_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var lore := Label.new()
	lore.text = "The realm fractures. Ancient pacts are broken and new powers stir at the borders. One commander must rise to forge order from the chaos — or perish in the attempt."
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_ADAPTIVE
	lore.modulate = Color(0.85, 0.85, 0.85)
	vbox.add_child(lore)

	vbox.add_child(HSeparator.new())

	var first_hdr := Label.new()
	first_hdr.text = "SCENARIO 1 — \"%s\"" % first_name
	first_hdr.add_theme_font_size_override("font_size", 16)
	vbox.add_child(first_hdr)

	var first_desc_lbl := Label.new()
	first_desc_lbl.text = first_desc
	first_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_ADAPTIVE
	first_desc_lbl.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(first_desc_lbl)

	var roster_note := Label.new()
	roster_note.text = "You will build your starting army before the battle begins."
	roster_note.add_theme_font_size_override("font_size", 11)
	roster_note.modulate = Color(0.6, 0.75, 0.9)
	vbox.add_child(roster_note)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(110, 44)
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn"))
	btn_row.add_child(back_btn)

	var begin_btn := Button.new()
	begin_btn.text = "Begin Campaign →"
	begin_btn.custom_minimum_size = Vector2(170, 44)
	begin_btn.pressed.connect(func() -> void: GameSetupManager.on_campaign_begun())
	btn_row.add_child(begin_btn)
