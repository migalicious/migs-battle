class_name CampaignTransitionScreen
extends Control

const _RECRUIT_NAMES := [
	"Amara", "Brennan", "Caspian", "Delia", "Edric", "Faye", "Gareth", "Hana",
	"Ivor", "Jenna", "Kelan", "Lyra", "Maren", "Nolan", "Oryn", "Petra",
	"Quen", "Rook", "Sable", "Taren", "Ulric", "Vera", "Wynn", "Xander",
	"Yara", "Zephyr", "Alden", "Bryn", "Caius", "Dwyn",
]

var _selected_unit: UnitData = null
var _roster_vbox: VBoxContainer = null
var _shop_vbox: VBoxContainer = null
var _recruit_cls_opt: OptionButton = null
var _gold_lbl: Label = null
var _injured_lbl: Label = null
var _heal_all_btn: Button = null
var _feedback_lbl: Label = null

func _ready() -> void:
	_build_ui()
	_refresh_all()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = "CAMPAIGN ADVANCE — Scenario %d Complete" % GameState.current_scenario_idx
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 22)
	root.add_child(title_lbl)
	root.add_child(HSeparator.new())

	# Main body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# ── Left panel ────────────────────────────────────────────────────────────
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)

	# Roster section
	var army_hdr := Label.new()
	army_hdr.text = "YOUR ARMY  (click to select for item equip)"
	army_hdr.add_theme_font_size_override("font_size", 13)
	army_hdr.modulate = Color(0.8, 0.8, 0.9)
	left.add_child(army_hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	_roster_vbox = VBoxContainer.new()
	_roster_vbox.add_theme_constant_override("separation", 3)
	_roster_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_vbox)

	# Heal row
	var heal_row := HBoxContainer.new()
	heal_row.add_theme_constant_override("separation", 8)
	left.add_child(heal_row)

	_injured_lbl = Label.new()
	_injured_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_row.add_child(_injured_lbl)

	_heal_all_btn = Button.new()
	_heal_all_btn.pressed.connect(_on_heal_all_pressed)
	heal_row.add_child(_heal_all_btn)

	left.add_child(HSeparator.new())

	# Shop section
	var shop_hdr := Label.new()
	shop_hdr.text = "SHOP  (10% discount — select a unit first to equip)"
	shop_hdr.add_theme_font_size_override("font_size", 13)
	shop_hdr.modulate = Color(0.8, 0.8, 0.9)
	left.add_child(shop_hdr)

	_shop_vbox = VBoxContainer.new()
	_shop_vbox.add_theme_constant_override("separation", 3)
	left.add_child(_shop_vbox)

	left.add_child(HSeparator.new())

	# Recruit section
	var recruit_hdr := Label.new()
	recruit_hdr.text = "RECRUIT"
	recruit_hdr.add_theme_font_size_override("font_size", 13)
	recruit_hdr.modulate = Color(0.8, 0.8, 0.9)
	left.add_child(recruit_hdr)

	var recruit_row := HBoxContainer.new()
	recruit_row.add_theme_constant_override("separation", 8)
	left.add_child(recruit_row)

	_recruit_cls_opt = OptionButton.new()
	_recruit_cls_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_recruit_options()
	recruit_row.add_child(_recruit_cls_opt)

	var recruit_btn := Button.new()
	recruit_btn.text = "Recruit"
	recruit_btn.pressed.connect(_on_recruit_pressed)
	recruit_row.add_child(recruit_btn)

	# ── Divider ───────────────────────────────────────────────────────────────
	body.add_child(VSeparator.new())

	# ── Right panel ───────────────────────────────────────────────────────────
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)

	var next_hdr := Label.new()
	next_hdr.text = "NEXT SCENARIO"
	next_hdr.add_theme_font_size_override("font_size", 16)
	next_hdr.modulate = Color(1.0, 0.85, 0.3)
	right.add_child(next_hdr)

	var next_name := Label.new()
	next_name.text = "Scenario %d" % (GameState.current_scenario_idx + 1)
	next_name.add_theme_font_size_override("font_size", 14)
	right.add_child(next_name)

	var next_desc := Label.new()
	next_desc.text = "A new challenge awaits.\nPrepare your forces."
	next_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_ADAPTIVE
	next_desc.modulate = Color(0.75, 0.75, 0.75)
	right.add_child(next_desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	# ── Footer ────────────────────────────────────────────────────────────────
	root.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.custom_minimum_size = Vector2(0.0, 48.0)
	root.add_child(footer)

	_feedback_lbl = Label.new()
	_feedback_lbl.modulate = Color(1.0, 0.45, 0.1)
	_feedback_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feedback_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_feedback_lbl)

	_gold_lbl = Label.new()
	_gold_lbl.add_theme_font_size_override("font_size", 16)
	_gold_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_gold_lbl)

	var advance_btn := Button.new()
	advance_btn.text = "Advance →"
	advance_btn.custom_minimum_size = Vector2(140.0, 40.0)
	advance_btn.pressed.connect(_on_advance_pressed)
	footer.add_child(advance_btn)

# ── Data Refresh ──────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_refresh_roster()
	_refresh_heal_row()
	_refresh_shop()
	_refresh_gold()

func _refresh_roster() -> void:
	for c in _roster_vbox.get_children():
		c.queue_free()
	for u in GameState.persistent_roster:
		_roster_vbox.add_child(_make_unit_row(u))

func _make_unit_row(u: UnitData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var cls: ClassDefinition = UnitRegistry.get_class_def(u.class_id)
	var cls_name: String = cls.display_name if cls else u.class_id.capitalize()

	var name_lbl := Label.new()
	name_lbl.text = "%s  [%s Lv.%d]" % [u.unit_name, cls_name, u.level]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if u == _selected_unit:
		name_lbl.modulate = Color(1.0, 0.85, 0.3)
	row.add_child(name_lbl)

	var hp_frac: float = float(u.hp) / float(maxi(u.max_hp, 1))
	var hp_str: String
	if hp_frac >= 1.0:
		hp_str = "♥♥♥"
	elif hp_frac >= 0.5:
		hp_str = "♥♥"
	else:
		hp_str = "♥"
	var hp_lbl := Label.new()
	hp_lbl.text = hp_str
	hp_lbl.modulate = Color(0.2, 1.0, 0.3) if hp_frac >= 0.5 else Color(1.0, 0.3, 0.3)
	row.add_child(hp_lbl)

	if u.is_wounded:
		var w_lbl := Label.new()
		w_lbl.text = "~"
		w_lbl.modulate = Color(1.0, 0.6, 0.0)
		row.add_child(w_lbl)

	var select_btn := Button.new()
	select_btn.text = "Select" if u != _selected_unit else "✓"
	select_btn.custom_minimum_size = Vector2(58.0, 0.0)
	var uc := u
	select_btn.pressed.connect(func() -> void: _on_unit_selected(uc))
	row.add_child(select_btn)

	if hp_frac < 1.0:
		var heal_btn := Button.new()
		heal_btn.text = "Heal (%dg)" % GameBalance.BETWEEN_MAP_RECOVER_COST
		heal_btn.disabled = GameState.player_gold < GameBalance.BETWEEN_MAP_RECOVER_COST
		var uc2 := u
		heal_btn.pressed.connect(func() -> void: _on_heal_unit(uc2))
		row.add_child(heal_btn)

	return row

func _refresh_heal_row() -> void:
	var injured := _count_injured()
	var cost := injured * GameBalance.BETWEEN_MAP_RECOVER_COST
	_injured_lbl.text = "%d unit(s) below full HP" % injured
	_heal_all_btn.text = "Heal All (%dg)" % cost
	_heal_all_btn.disabled = injured == 0 or GameState.player_gold < cost

func _count_injured() -> int:
	var n := 0
	for u in GameState.persistent_roster:
		if float(u.hp) / float(maxi(u.max_hp, 1)) < 1.0:
			n += 1
	return n

func _refresh_shop() -> void:
	for c in _shop_vbox.get_children():
		c.queue_free()
	for item in ItemRegistry.get_all_items():
		_shop_vbox.add_child(_make_shop_row(item))

func _make_shop_row(item) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var info_lbl := Label.new()
	var discounted := int(float(item.cost) * 0.9)
	info_lbl.text = "%s — %s" % [item.display_name, item.description]
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.clip_text = true
	row.add_child(info_lbl)

	var buy_btn := Button.new()
	buy_btn.text = "Buy (%dg)" % discounted
	buy_btn.disabled = GameState.player_gold < discounted
	var it := item
	buy_btn.pressed.connect(func() -> void: _on_buy_item(it))
	row.add_child(buy_btn)

	return row

func _build_recruit_options() -> void:
	_recruit_cls_opt.clear()
	for cls_def in UnitRegistry.get_all_class_defs():
		var cls := cls_def as ClassDefinition
		if not cls or cls.deploy_cost <= 0:
			continue
		_recruit_cls_opt.add_item("%s (%dg)" % [cls.display_name, cls.deploy_cost])
		_recruit_cls_opt.set_item_metadata(_recruit_cls_opt.item_count - 1, cls.class_id)

func _refresh_gold() -> void:
	_gold_lbl.text = "Gold: %d" % GameState.player_gold

# ── Interactions ──────────────────────────────────────────────────────────────

func _on_unit_selected(u: UnitData) -> void:
	_selected_unit = u if _selected_unit != u else null
	_refresh_roster()
	_refresh_shop()

func _on_heal_unit(u: UnitData) -> void:
	if GameState.player_gold < GameBalance.BETWEEN_MAP_RECOVER_COST:
		return
	GameState.player_gold -= GameBalance.BETWEEN_MAP_RECOVER_COST
	GameState.apply_between_map_recovery(u)
	_refresh_all()
	_show_feedback("")

func _on_heal_all_pressed() -> void:
	var injured := _count_injured()
	var cost := injured * GameBalance.BETWEEN_MAP_RECOVER_COST
	if GameState.player_gold < cost:
		return
	GameState.player_gold -= cost
	for u in GameState.persistent_roster:
		if float(u.hp) / float(maxi(u.max_hp, 1)) < 1.0:
			GameState.apply_between_map_recovery(u)
	_refresh_all()

func _on_buy_item(item) -> void:
	var discounted := int(float(item.cost) * 0.9)
	if GameState.player_gold < discounted:
		_show_feedback("Not enough gold!")
		return
	if not _selected_unit:
		_show_feedback("Select a unit to receive the item.")
		return
	if _selected_unit.held_item != "":
		_show_feedback("%s already holds an item." % _selected_unit.unit_name)
		return
	GameState.player_gold -= discounted
	_selected_unit.held_item = item.item_id
	_show_feedback("%s equipped %s." % [_selected_unit.unit_name, item.display_name])
	_refresh_all()

func _on_recruit_pressed() -> void:
	if _recruit_cls_opt.item_count == 0:
		return
	var idx: int = _recruit_cls_opt.selected
	var class_id: String = _recruit_cls_opt.get_item_metadata(idx) as String
	var cls := UnitRegistry.get_class_def(class_id) as ClassDefinition
	if not cls:
		return
	if GameState.player_gold < cls.deploy_cost:
		_show_feedback("Not enough gold to recruit %s." % cls.display_name)
		return
	GameState.player_gold -= cls.deploy_cost
	var unit := UnitRegistry.create_unit(class_id, 1)
	unit.unit_name = _pick_recruit_name()
	unit.faction = TerrainDefs.Faction.PLAYER
	GameState.persistent_roster.append(unit)
	_show_feedback("Recruited %s the %s!" % [unit.unit_name, cls.display_name])
	_refresh_all()

func _pick_recruit_name() -> String:
	var existing: Array = []
	for u in GameState.persistent_roster:
		existing.append(u.unit_name)
	var candidates: Array = []
	for n in _RECRUIT_NAMES:
		if not existing.has(n):
			candidates.append(n)
	if candidates.is_empty():
		return "Recruit_%d" % GameState.persistent_roster.size()
	return candidates[randi() % candidates.size()]

func _on_advance_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/ArmyBuilderScreen.tscn")

func _show_feedback(msg: String) -> void:
	_feedback_lbl.text = msg
