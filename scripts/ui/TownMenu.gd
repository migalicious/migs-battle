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
	_owner_lbl.text = "Owner: " + TerrainDefs.FACTION_NAMES.get(faction_id, "Unknown")

# ── Friendly body (interactive) ───────────────────────────────────────────────

func _build_friendly_body(reserve: Array) -> void:
	for c in _body_vbox.get_children():
		c.queue_free()

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
			var cost := _squad_deploy_cost(squad_data)
			var btn := Button.new()
			btn.text = "Deploy: %s  (%d units)  %dg" % [
				leader.unit_name if leader else "???", alive_count, cost]
			btn.pressed.connect(_on_deploy_pressed.bind(squad_data))
			_body_vbox.add_child(btn)

	_body_vbox.add_child(HSeparator.new())

	if _current_town.town_data and _current_town.town_data.has_aquatic_recruit:
		var recruit_cost := 120
		var recruit_btn := Button.new()
		recruit_btn.text = "Recruit Merfolk  (%dg)" % recruit_cost
		recruit_btn.disabled = GameState.player_gold < recruit_cost
		recruit_btn.pressed.connect(_on_recruit_merfolk.bind(recruit_cost))
		_body_vbox.add_child(recruit_btn)
		_body_vbox.add_child(HSeparator.new())

	var shop_btn := Button.new()
	shop_btn.text = "Shop"
	shop_btn.pressed.connect(_on_shop_pressed)
	_body_vbox.add_child(shop_btn)

	_body_vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	_body_vbox.add_child(close_btn)

# ── Read-only body (enemy / neutral view) ────────────────────────────────────

func _build_readonly_body() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()

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

func _squad_deploy_cost(squad: SquadData) -> int:
	var total := 0
	for unit in squad.get_alive_units():
		var cls := UnitRegistry.get_class_def(unit.class_id) as ClassDefinition
		if cls:
			total += cls.deploy_cost
	return total

func _get_all_player_units() -> Array:
	var result: Array = []
	for sq in GameState.player_squads:
		if sq is Squad:
			for u in (sq as Squad).squad_data.get_alive_units():
				result.append(u)
	for sd in GameState.reserve_squads:
		if sd is SquadData:
			for u in (sd as SquadData).get_alive_units():
				result.append(u)
	return result

# ── Shop ──────────────────────────────────────────────────────────────────────

func _on_shop_pressed() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()
	call_deferred("_build_shop_body")

func _build_shop_body() -> void:
	var gold_lbl := Label.new()
	gold_lbl.text = "SHOP    Gold: %d" % GameState.player_gold
	gold_lbl.add_theme_font_size_override("font_size", 13)
	_body_vbox.add_child(gold_lbl)
	_body_vbox.add_child(HSeparator.new())

	for item in ItemRegistry.get_all_items():
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s  %dg" % [item.display_name, item.cost]
		lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(lbl)
		var cnt: int = GameState.player_inventory.get(item.item_id, 0)
		if cnt > 0:
			var cnt_lbl := Label.new()
			cnt_lbl.text = "x%d" % cnt
			row.add_child(cnt_lbl)
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.disabled = GameState.player_gold < item.cost
		buy_btn.pressed.connect(_on_buy_pressed.bind(item.item_id, item.cost))
		row.add_child(buy_btn)
		_body_vbox.add_child(row)

	_body_vbox.add_child(HSeparator.new())

	var equip_hdr := Label.new()
	equip_hdr.text = "EQUIP"
	equip_hdr.add_theme_font_size_override("font_size", 11)
	_body_vbox.add_child(equip_hdr)

	var unit_opt := OptionButton.new()
	unit_opt.name = "UnitOption"
	var all_units := _get_all_player_units()
	for u in all_units:
		unit_opt.add_item(u.unit_name)
	_body_vbox.add_child(unit_opt)

	var item_opt := OptionButton.new()
	item_opt.name = "ItemOption"
	item_opt.add_item("(none)")
	for iid in GameState.player_inventory.keys():
		if (GameState.player_inventory[iid] as int) > 0:
			var itm = ItemRegistry.get_item(iid)
			if itm:
				item_opt.add_item(itm.display_name)
	_body_vbox.add_child(item_opt)

	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.pressed.connect(_on_equip_pressed.bind(unit_opt, item_opt, all_units))
	_body_vbox.add_child(equip_btn)

	_body_vbox.add_child(HSeparator.new())

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func() -> void:
		for c in _body_vbox.get_children(): c.queue_free()
		call_deferred("_build_friendly_body", GameState.reserve_squads))
	_body_vbox.add_child(back_btn)

func _on_buy_pressed(item_id: String, cost: int) -> void:
	if GameState.player_gold < cost:
		return
	GameState.player_gold -= cost
	GameState.gold_changed.emit(TerrainDefs.Faction.PLAYER, GameState.player_gold)
	GameState.player_inventory[item_id] = GameState.player_inventory.get(item_id, 0) + 1
	for c in _body_vbox.get_children(): c.queue_free()
	call_deferred("_build_shop_body")

func _on_equip_pressed(unit_opt: OptionButton, item_opt: OptionButton, all_units: Array) -> void:
	if all_units.is_empty() or item_opt.selected == 0:
		return
	var unit: UnitData = all_units[unit_opt.selected]
	if unit.held_item != "":
		GameState.player_inventory[unit.held_item] = GameState.player_inventory.get(unit.held_item, 0) + 1
	var inv_keys := GameState.player_inventory.keys()
	var non_empty_keys: Array = []
	for k in inv_keys:
		if (GameState.player_inventory[k] as int) > 0:
			non_empty_keys.append(k)
	var sel_idx := item_opt.selected - 1
	if sel_idx < 0 or sel_idx >= non_empty_keys.size():
		return
	var chosen_id: String = non_empty_keys[sel_idx]
	unit.held_item = chosen_id
	GameState.player_inventory[chosen_id] = (GameState.player_inventory[chosen_id] as int) - 1
	for c in _body_vbox.get_children(): c.queue_free()
	call_deferred("_build_shop_body")

# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_recruit_merfolk(cost: int) -> void:
	if GameState.player_gold < cost:
		return
	GameState.player_gold -= cost
	GameState.gold_changed.emit(TerrainDefs.Faction.PLAYER, GameState.player_gold)
	var unit := UnitRegistry.create_unit("merfolk", 1)
	unit.unit_name = "Merfolk"
	unit.is_leader = true
	var sd := SquadData.new()
	sd.squad_id = "merfolk_%d" % Time.get_ticks_msec()
	sd.units = [unit]
	sd.recalculate_speed(TerrainDefs.TerrainType.PLAINS)
	GameState.reserve_squads.append(sd)
	close()

func _on_deploy_pressed(squad_data: SquadData) -> void:
	deploy_requested.emit(squad_data, _current_town)
	close()

func _on_ungarrison_pressed() -> void:
	ungarrison_requested.emit(_current_town)
	close()

func _on_close_pressed() -> void:
	close()
