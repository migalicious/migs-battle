class_name TopBar
extends Control

var _status_lbl: Label = null
var _gold_lbl: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.gold_changed.connect(_on_gold_changed)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.18, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	var title_lbl := Label.new()
	title_lbl.text = "  MIGS BATTLE"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.modulate = Color(0.94, 0.75, 0.25)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(title_lbl)

	_status_lbl = Label.new()
	_status_lbl.text = "OVERWORLD"
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_status_lbl)

	var right_box := HBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(right_box)

	_gold_lbl = Label.new()
	_gold_lbl.text = "Gold: %d" % GameState.player_gold
	_gold_lbl.add_theme_font_size_override("font_size", 13)
	_gold_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(_gold_lbl)

	var pause_btn := Button.new()
	pause_btn.text = "Pause"
	pause_btn.custom_minimum_size = Vector2(64, 0)
	pause_btn.pressed.connect(_on_pause_pressed)
	right_box.add_child(pause_btn)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(gap)

func _process(_delta: float) -> void:
	if not _status_lbl:
		return
	match GameState.current_phase:
		GameState.Phase.IN_BATTLE: _status_lbl.text = "IN BATTLE"
		GameState.Phase.VICTORY:   _status_lbl.text = "VICTORY"
		GameState.Phase.DEFEAT:    _status_lbl.text = "DEFEAT"
		_:
			_status_lbl.text = "PAUSED" if get_tree().paused else "OVERWORLD"

func _on_gold_changed(faction: int, amount: int) -> void:
	if faction != TerrainDefs.Faction.PLAYER or not _gold_lbl:
		return
	_gold_lbl.text = "Gold: %d" % amount
	var tween := create_tween()
	tween.tween_property(_gold_lbl, "modulate", Color(1.0, 0.85, 0.1), 0.15)
	tween.tween_property(_gold_lbl, "modulate", Color.WHITE, 0.3)

func _on_pause_pressed() -> void:
	if GameState.current_phase != GameState.Phase.OVERWORLD:
		return
	get_tree().paused = not get_tree().paused
