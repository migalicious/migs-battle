class_name TownMenu
extends Panel

signal deploy_requested(squad_data: SquadData, town: TownNode)
signal ungarrison_requested(town: TownNode)
signal closed()

var _current_town: TownNode = null
var _title_lbl: Label = null
var _owner_lbl: Label = null
var _body_vbox: VBoxContainer = null

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 15)
	outer.add_child(_title_lbl)

	_owner_lbl = Label.new()
	_owner_lbl.add_theme_font_size_override("font_size", 11)
	_owner_lbl.modulate = Color(0.78, 0.78, 0.88)
	outer.add_child(_owner_lbl)

	outer.add_child(HSeparator.new())

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 6)
	outer.add_child(_body_vbox)

# ── Public API ────────────────────────────────────────────────────────────────

func open(town: TownNode, reserve: Array) -> void:
	_current_town = town
	_fill_header()
	_build_friendly_body(reserve)
	visible = true

func open_info(town: TownNode) -> void:
	_current_town = town
	_fill_header()
	_build_readonly_body()
	visible = true

func close() -> void:
	visible = false
	closed.emit()

# ── Header ────────────────────────────────────────────────────────────────────

func _fill_header() -> void:
	if not _current_town or not _current_town.town_data:
		return
	var td := _current_town.town_data
	var type_names: Array = ["Town", "Castle", "HQ"]
	var t_idx: int = int(td.town_type)
	var type_str: String = type_names[t_idx] if t_idx < type_names.size() else "???"
	var display: String = td.display_name if td.display_name != "" else "Town"
	_title_lbl.text = display + "  [" + type_str + "]"

	var faction_id: int = GameState.town_ownership.get(td.town_id, TerrainDefs.Faction.NEUTRAL)
	var faction_name: String
	match faction_id:
		TerrainDefs.Faction.PLAYER: faction_name = "Player"
		TerrainDefs.Faction.ENEMY:  faction_name = "Enemy"
		_: faction_name = "Neutral"
	_owner_lbl.text = "Owner: " + faction_name

# ── Friendly body (interactive) ───────────────────────────────────────────────

func _build_friendly_body(reserve: Array) -> void:
	for c in _body_vbox.get_children():
		c.free()

	var gar_lbl := Label.new()
	gar_lbl.add_theme_font_size_override("font_size", 11)
	if _current_town.garrisoned_squad:
		var leader := _current_town.garrisoned_squad.squad_data.get_leader()
		gar_lbl.text = "Garrison: " + (leader.unit_name if leader else "???")
	else:
		gar_lbl.text = "Garrison: Empty"
	_body_vbox.add_child(gar_lbl)

	if _current_town.garrisoned_squad:
		var ug_btn := Button.new()
		ug_btn.text = "Ungarrison"
		ug_btn.pressed.connect(_on_ungarrison_pressed)
		_body_vbox.add_child(ug_btn)

	_body_vbox.add_child(HSeparator.new())

	var reserve_hdr := Label.new()
	reserve_hdr.text = "Reserve Squads:"
	reserve_hdr.add_theme_font_size_override("font_size", 11)
	_body_vbox.add_child(reserve_hdr)

	if reserve.is_empty():
		var no_lbl := Label.new()
		no_lbl.text = "(No reserve squads)"
		no_lbl.add_theme_font_size_override("font_size", 10)
		_body_vbox.add_child(no_lbl)
	else:
		for rd in reserve:
			var squad_data := rd as SquadData
			if not squad_data:
				continue
			var leader := squad_data.get_leader()
			var alive_count := squad_data.get_alive_units().size()
			var btn := Button.new()
			btn.text = "Deploy: %s  (%d units)" % [
				leader.unit_name if leader else "???", alive_count]
			btn.pressed.connect(_on_deploy_pressed.bind(squad_data))
			_body_vbox.add_child(btn)

	_body_vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	_body_vbox.add_child(close_btn)

# ── Read-only body (enemy / neutral view) ────────────────────────────────────

func _build_readonly_body() -> void:
	for c in _body_vbox.get_children():
		c.free()

	var gar_lbl := Label.new()
	gar_lbl.add_theme_font_size_override("font_size", 11)
	if _current_town.garrisoned_squad:
		var leader := _current_town.garrisoned_squad.squad_data.get_leader()
		gar_lbl.text = "Garrison: " + (leader.unit_name if leader else "???")
	else:
		gar_lbl.text = "Garrison: Empty"
	_body_vbox.add_child(gar_lbl)

	if _current_town.occupying_squad != null:
		var cap_lbl := Label.new()
		cap_lbl.add_theme_font_size_override("font_size", 11)
		cap_lbl.text = "Capture: %d/%d ticks" % [
			_current_town.capture_ticks,
			_current_town.town_data.capture_turns]
		_body_vbox.add_child(cap_lbl)

	_body_vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	_body_vbox.add_child(close_btn)

# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_deploy_pressed(squad_data: SquadData) -> void:
	deploy_requested.emit(squad_data, _current_town)
	close()

func _on_ungarrison_pressed() -> void:
	ungarrison_requested.emit(_current_town)
	close()

func _on_close_pressed() -> void:
	close()
