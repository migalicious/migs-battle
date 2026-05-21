extends Control

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 32)
	add_child(vbox)

	var title := Label.new()
	title.text = "MIGS BATTLE"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var btn := Button.new()
	btn.text = "New Game"
	btn.custom_minimum_size = Vector2(200, 52)
	btn.pressed.connect(_on_new_game)
	vbox.add_child(btn)

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
