class_name ArmyBuilderScreen
extends Control

const _ScenarioDataScript = preload("res://scripts/units/ScenarioData.gd")

signal army_ready(squads: Array[SquadData])

const SLOT_IDS := ["F-0", "F-1", "F-2", "B-0", "B-1", "B-2"]
# row=0 front, row=1 back; col=0/1/2
const SLOT_COORDS := [
	[0, 0], [0, 1], [0, 2],
	[1, 0], [1, 1], [1, 2],
]

var _scenario = null
var _all_units: Array[UnitData] = []
var _unassigned: Array[UnitData] = []
var _squads: Array[SquadData] = []
var _selected_unit: UnitData = null
var _active_squad_idx: int = 0

var _tab_row: HBoxContainer = null
var _new_squad_btn: Button = null
var _slot_btns: Array[Button] = []
var _roster_vbox: VBoxContainer = null
var _error_label: Label = null
var _start_btn: Button = null
var _popup: UnitDetailPopup = null
var _banner_lbl: Label = null

func _ready() -> void:
	_build_ui()
	if GameState.campaign_run_active and not GameState.persistent_roster.is_empty():
		setup_from_roster(GameState.persistent_roster)
	else:
		setup(_make_v2_starter())

func _make_v2_starter():
	var s = _ScenarioDataScript.new()
	s.scenario_name = "V2 Starter"
	s.max_squads = 3
	s.max_reserve_squads = 5
	s.starting_units = [
		{"class_id": "knight",  "unit_name": "Roland",  "level": 5},
		{"class_id": "knight",  "unit_name": "Gawain",  "level": 4},
		{"class_id": "archer",  "unit_name": "Sylvia",  "level": 4},
		{"class_id": "mage",    "unit_name": "Elara",   "level": 4},
		{"class_id": "cavalry", "unit_name": "Marcus",  "level": 4},
		{"class_id": "fighter", "unit_name": "Bors",    "level": 3},
		{"class_id": "fighter", "unit_name": "Aldric",  "level": 3},
		{"class_id": "archer",  "unit_name": "Tristan", "level": 3},
		{"class_id": "archer",  "unit_name": "Isolde",  "level": 3},
		{"class_id": "fighter", "unit_name": "Cedric",  "level": 2},
		{"class_id": "fighter", "unit_name": "Petra",   "level": 2},
		{"class_id": "mage",    "unit_name": "Lyra",    "level": 3},
		{"class_id": "fighter", "unit_name": "Dara",    "level": 2},
		{"class_id": "fighter", "unit_name": "Finn",    "level": 2},
		{"class_id": "archer",  "unit_name": "Wren",    "level": 2},
		{"class_id": "fighter", "unit_name": "Cael",    "level": 2},
		{"class_id": "fighter", "unit_name": "Mira",    "level": 2},
		{"class_id": "mage",    "unit_name": "Oryn",    "level": 2},
	]
	return s

func setup(scenario) -> void:
	_scenario = scenario
	_all_units = _build_unit_pool(scenario)
	_unassigned = _all_units.duplicate()
	_squads = []
	_add_squad()
	_refresh()

func setup_from_roster(roster: Array[UnitData]) -> void:
	var stub := _ScenarioDataScript.new()
	stub.scenario_name = "Campaign"
	stub.max_squads = 3
	stub.max_reserve_squads = 5
	stub.starting_units = []
	_scenario = stub
	_all_units = []
	for u in roster:
		_all_units.append(u)
	_unassigned = _all_units.duplicate()
	_squads = []
	_add_squad()
	_refresh()
	_show_levelup_banners(roster)

func _show_levelup_banners(roster: Array[UnitData]) -> void:
	var prev: Dictionary = GameState.pre_scenario_levels
	if prev.is_empty():
		return
	var notices: Array[String] = []
	for u in roster:
		var old_level: int = prev.get(u.unit_name, u.level)
		if u.level > old_level:
			notices.append("%s: Level %d → %d!" % [u.unit_name, old_level, u.level])
	if notices.is_empty():
		return
	if _banner_lbl == null:
		_banner_lbl = Label.new()
		_banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner_lbl.add_theme_font_size_override("font_size", 14)
		_banner_lbl.modulate = Color(0.4, 1.0, 0.5)
		_banner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_banner_lbl)
		# Position above the roster, anchored to top
		_banner_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_banner_lbl.offset_top = 4.0
		_banner_lbl.offset_bottom = 32.0
	_banner_lbl.text = "  ".join(notices)
	_banner_lbl.visible = true

func _build_unit_pool(scenario) -> Array[UnitData]:
	var pool: Array[UnitData] = []
	for entry in scenario.starting_units:
		var unit := UnitRegistry.create_unit(entry["class_id"], entry["level"])
		if unit:
			unit.unit_name = entry["unit_name"]
			pool.append(unit)
	return pool

func _add_squad() -> void:
	var sq := SquadData.new()
	sq.squad_id = "player_%d" % _squads.size()
	sq.faction = TerrainDefs.Faction.PLAYER
	_squads.append(sq)
	_active_squad_idx = _squads.size() - 1

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# Title bar
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 0)
	root.add_child(title_row)

	var title := Label.new()
	title.text = "ARMY BUILDER"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	root.add_child(HSeparator.new())

	# Body: left (squads) + right (roster)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# --- Left panel ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)

	# Squad tab row
	var tab_outer := HBoxContainer.new()
	tab_outer.add_theme_constant_override("separation", 4)
	left.add_child(tab_outer)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_outer.add_child(_tab_row)

	_new_squad_btn = Button.new()
	_new_squad_btn.text = "+ New Squad"
	_new_squad_btn.pressed.connect(_on_new_squad_pressed)
	tab_outer.add_child(_new_squad_btn)

	# Front/back labels
	var row_hdr := GridContainer.new()
	row_hdr.columns = 3
	row_hdr.add_theme_constant_override("h_separation", 6)
	left.add_child(row_hdr)
	for col_name in ["Col 1", "Col 2", "Col 3"]:
		var lbl := Label.new()
		lbl.text = col_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.modulate = Color(0.6, 0.6, 0.7)
		row_hdr.add_child(lbl)

	# Slot grid (3 cols × 2 rows)
	var slot_grid := GridContainer.new()
	slot_grid.columns = 3
	slot_grid.add_theme_constant_override("h_separation", 6)
	slot_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(slot_grid)

	_slot_btns = []
	for i in range(6):
		var btn := Button.new()
		btn.text = SLOT_IDS[i]
		btn.custom_minimum_size = Vector2(120, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func() -> void: _on_slot_pressed(idx))
		slot_grid.add_child(btn)
		_slot_btns.append(btn)

	# Row labels below grid
	var row_lbl_box := HBoxContainer.new()
	row_lbl_box.add_theme_constant_override("separation", 0)
	left.add_child(row_lbl_box)
	var front_tag := Label.new()
	front_tag.text = "← FRONT                            BACK →"
	front_tag.add_theme_font_size_override("font_size", 10)
	front_tag.modulate = Color(0.55, 0.65, 0.8)
	row_lbl_box.add_child(front_tag)

	# Divider
	body.add_child(VSeparator.new())

	# --- Right panel: roster ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)

	var roster_hdr := Label.new()
	roster_hdr.text = "ROSTER  (click to select, ★ = can lead)"
	roster_hdr.add_theme_font_size_override("font_size", 12)
	roster_hdr.modulate = Color(0.8, 0.8, 0.9)
	right.add_child(roster_hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	_roster_vbox = VBoxContainer.new()
	_roster_vbox.add_theme_constant_override("separation", 3)
	_roster_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_vbox)

	root.add_child(HSeparator.new())

	# Bottom bar
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.custom_minimum_size = Vector2(0, 48)
	root.add_child(bottom)

	_error_label = Label.new()
	_error_label.text = "Configure at least one squad."
	_error_label.modulate = Color(1.0, 0.38, 0.38)
	_error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_error_label)

	_start_btn = Button.new()
	_start_btn.text = "Start Battle"
	_start_btn.custom_minimum_size = Vector2(160, 40)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_pressed)
	bottom.add_child(_start_btn)

	# UnitDetailPopup (fixed position, shown on roster hover)
	_popup = UnitDetailPopup.new()
	_popup.custom_minimum_size = Vector2(260, 0)
	_popup.visible = false
	add_child(_popup)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _scenario:
		return
	_refresh_tabs()
	_refresh_slots()
	_refresh_roster()
	if _new_squad_btn:
		_new_squad_btn.disabled = _squads.size() >= _scenario.max_squads
	_validate()

func _refresh_tabs() -> void:
	for child in _tab_row.get_children():
		child.queue_free()
	for i in range(_squads.size()):
		var btn := Button.new()
		btn.text = "Squad %d" % (i + 1)
		if i == _active_squad_idx:
			btn.modulate = Color(1.0, 0.85, 0.3)
		var idx := i
		btn.pressed.connect(func() -> void: _active_squad_idx = idx; _refresh())
		_tab_row.add_child(btn)

func _refresh_slots() -> void:
	if _squads.is_empty():
		for i in range(6):
			_slot_btns[i].text = SLOT_IDS[i]
			_slot_btns[i].modulate = Color(1, 1, 1)
		return

	var sq := _squads[_active_squad_idx]
	var placed: Dictionary = {}
	for u in sq.units:
		placed[Vector2i(u.row, u.col)] = u

	for i in range(6):
		var coord := Vector2i(SLOT_COORDS[i][0], SLOT_COORDS[i][1])
		var btn := _slot_btns[i]
		if placed.has(coord):
			var u: UnitData = placed[coord]
			btn.text = u.unit_name
			btn.modulate = Color(0.55, 0.92, 0.55) if u.is_leader else Color(0.70, 0.82, 1.0)
		else:
			btn.text = SLOT_IDS[i]
			btn.modulate = Color(1.0, 1.0, 0.55) if _selected_unit else Color(1, 1, 1)

func _refresh_roster() -> void:
	for child in _roster_vbox.get_children():
		child.queue_free()
	for unit in _unassigned:
		var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id)
		var cls_name: String = cls.display_name if cls else unit.class_id.capitalize()
		var can_lead: bool = cls.can_lead if cls else false
		var btn := Button.new()
		btn.text = unit.unit_name
		btn.tooltip_text = "%s  %s Lv.%d%s" % [unit.unit_name, cls_name, unit.level, "  ★" if can_lead else ""]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.modulate = Color(1.0, 0.85, 0.3) if unit == _selected_unit else Color(1, 1, 1)
		var u := unit
		btn.pressed.connect(func() -> void: _on_roster_pressed(u))
		btn.mouse_entered.connect(func() -> void: _on_roster_hover(u))
		btn.mouse_exited.connect(func() -> void: _popup.visible = false)
		_roster_vbox.add_child(btn)

# ── Interactions ──────────────────────────────────────────────────────────────

func _on_roster_pressed(unit: UnitData) -> void:
	_selected_unit = unit if _selected_unit != unit else null
	_refresh()

func _on_roster_hover(unit: UnitData) -> void:
	_popup.show_unit(unit)
	_popup.global_position = Vector2(20, 120)

func _on_slot_pressed(slot_idx: int) -> void:
	if _squads.is_empty():
		return
	var sq := _squads[_active_squad_idx]
	var row: int = SLOT_COORDS[slot_idx][0]
	var col: int = SLOT_COORDS[slot_idx][1]

	var existing: UnitData = null
	for u in sq.units:
		if u.row == row and u.col == col:
			existing = u
			break

	if existing:
		sq.units.erase(existing)
		existing.row = 0
		existing.col = 0
		existing.is_leader = false
		_unassigned.append(existing)
		_auto_assign_leader(sq)
		_selected_unit = null
	elif _selected_unit:
		_selected_unit.row = row
		_selected_unit.col = col
		sq.units.append(_selected_unit)
		_unassigned.erase(_selected_unit)
		_auto_assign_leader(sq)
		_selected_unit = null

	_refresh()

func _on_new_squad_pressed() -> void:
	if _scenario and _squads.size() < _scenario.max_squads:
		_add_squad()
		_refresh()

func _on_start_pressed() -> void:
	if not _validate():
		return
	var non_empty: Array[SquadData] = []
	for sq in _squads:
		if not sq.units.is_empty():
			non_empty.append(sq)
	if GameState.campaign_run_active:
		GameState.configured_squads = non_empty
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	else:
		army_ready.emit(non_empty)

# ── Leader logic ──────────────────────────────────────────────────────────────

func _auto_assign_leader(sq: SquadData) -> void:
	for u in sq.units:
		u.is_leader = false
	# Prefer a hero leader (so the boosted unit fronts the squad and its class sets
	# the squad's movement type); fall back to any can_lead unit.
	for u in sq.units:
		var cls: ClassDefinition = UnitRegistry.get_class_def(u.class_id)
		if u.is_hero and cls and cls.can_lead:
			u.is_leader = true
			return
	for u in sq.units:
		var cls2: ClassDefinition = UnitRegistry.get_class_def(u.class_id)
		if cls2 and cls2.can_lead:
			u.is_leader = true
			return

# ── Validation ────────────────────────────────────────────────────────────────

func _validate() -> bool:
	var any_valid := false
	for sq in _squads:
		if sq.units.is_empty():
			continue
		var has_leader := false
		for u in sq.units:
			if u.is_leader:
				has_leader = true
				break
		if not has_leader:
			_show_error("A squad has units but no leader.")
			return false
		any_valid = true
	if not any_valid:
		_show_error("Configure at least one squad.")
		return false
	_error_label.visible = false
	_start_btn.disabled = false
	return true

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
	_start_btn.disabled = true
