class_name MapConfigScreen
extends Control

signal config_ready(params: MapParams, win_conditions: Array[String])
signal back_requested()

const CONFIG_PATH := "user://map_config.cfg"

var _size_option: OptionButton = null
var _seed_field: LineEdit = null
var _towns_slider: HSlider = null
var _towns_value: Label = null
var _castles_slider: HSlider = null
var _castles_value: Label = null
var _win_option: OptionButton = null
var _last_seed_lbl: Label = null
var _replay_btn: Button = null

var _last_seed: int = 0

func _ready() -> void:
	_build_ui()
	_load_last_seed()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left  = -260.0
	panel.offset_right =  260.0
	panel.offset_top   = -260.0
	panel.offset_bottom = 260.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "MAP CONFIGURATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Map Size
	vbox.add_child(_make_label("Map Size"))
	_size_option = OptionButton.new()
	_size_option.name = "SizeOption"
	_size_option.add_item("Small  (24 × 24)")
	_size_option.add_item("Medium (32 × 32)")
	_size_option.add_item("Large  (48 × 48)")
	_size_option.selected = 1
	vbox.add_child(_size_option)

	# Seed
	vbox.add_child(_make_label("Seed"))
	_seed_field = LineEdit.new()
	_seed_field.name = "SeedField"
	_seed_field.placeholder_text = "blank = random"
	_seed_field.custom_minimum_size = Vector2(0, 34)
	vbox.add_child(_seed_field)

	# Towns slider
	var towns_row := HBoxContainer.new()
	towns_row.add_theme_constant_override("separation", 8)
	vbox.add_child(towns_row)
	towns_row.add_child(_make_label("Towns"))
	_towns_slider = _make_slider(4, 10, 6)
	towns_row.add_child(_towns_slider)
	_towns_value = Label.new()
	_towns_value.text = "6"
	_towns_value.custom_minimum_size = Vector2(22, 0)
	towns_row.add_child(_towns_value)
	_towns_slider.value_changed.connect(func(v: float) -> void: _towns_value.text = str(int(v)))

	# Castles slider
	var castles_row := HBoxContainer.new()
	castles_row.add_theme_constant_override("separation", 8)
	vbox.add_child(castles_row)
	castles_row.add_child(_make_label("Castles"))
	_castles_slider = _make_slider(0, 4, 2)
	castles_row.add_child(_castles_slider)
	_castles_value = Label.new()
	_castles_value.text = "2"
	_castles_value.custom_minimum_size = Vector2(22, 0)
	castles_row.add_child(_castles_value)
	_castles_slider.value_changed.connect(func(v: float) -> void: _castles_value.text = str(int(v)))

	# Win Condition
	vbox.add_child(_make_label("Win Condition"))
	_win_option = OptionButton.new()
	_win_option.name = "WinOption"
	_win_option.add_item("HQ Capture")
	_win_option.add_item("All Strongholds")
	_win_option.add_item("Both")
	_win_option.selected = 0
	vbox.add_child(_win_option)

	vbox.add_child(HSeparator.new())

	# Last seed row
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	vbox.add_child(seed_row)
	_last_seed_lbl = Label.new()
	_last_seed_lbl.text = "Last Seed: —"
	_last_seed_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_last_seed_lbl)
	_replay_btn = Button.new()
	_replay_btn.text = "Replay ↩"
	_replay_btn.disabled = true
	_replay_btn.pressed.connect(_on_replay_pressed)
	seed_row.add_child(_replay_btn)

	vbox.add_child(HSeparator.new())

	# Back / Generate buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(110, 44)
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	btn_row.add_child(back_btn)

	var gen_btn := Button.new()
	gen_btn.text = "Generate Map"
	gen_btn.custom_minimum_size = Vector2(150, 44)
	gen_btn.pressed.connect(_on_generate_pressed)
	btn_row.add_child(gen_btn)

# ── Seed persistence ──────────────────────────────────────────────────────────

func _load_last_seed() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_last_seed = cfg.get_value("map", "last_seed", 0)
	_update_last_seed_display()

func _update_last_seed_display() -> void:
	if _last_seed_lbl:
		_last_seed_lbl.text = "Last Seed: %d" % _last_seed if _last_seed != 0 else "Last Seed: —"
	if _replay_btn:
		_replay_btn.disabled = (_last_seed == 0)

func _on_replay_pressed() -> void:
	_seed_field.text = str(_last_seed)

# ── Generate ──────────────────────────────────────────────────────────────────

func _on_generate_pressed() -> void:
	var params := MapParams.new()
	match _size_option.selected:
		0: params.width = 24; params.height = 24
		1: params.width = 32; params.height = 32
		2: params.width = 48; params.height = 48
	params.map_seed    = int(_seed_field.text) if _seed_field.text.is_valid_int() else 0
	params.num_towns   = int(_towns_slider.value)
	params.num_castles = int(_castles_slider.value)
	config_ready.emit(params, _get_win_conditions())

func _get_win_conditions() -> Array[String]:
	match _win_option.selected:
		0: return ["hq_capture"]
		1: return ["all_strongholds"]
		2: return ["hq_capture", "all_strongholds"]
	return ["hq_capture"]

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl

func _make_slider(min_val: float, max_val: float, default_val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_val
	s.max_value = max_val
	s.step = 1.0
	s.value = default_val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s
