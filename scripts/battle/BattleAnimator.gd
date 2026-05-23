class_name BattleAnimator
extends CanvasLayer

signal battle_completed()

const DELAY: float = 0.35

var _attacker: SquadData = null
var _defender: SquadData = null
var _result: BattleResult = null

# Maps unit_name -> ColorRect (the class-colored box for that unit slot)
var _atk_slots: Dictionary = {}
var _def_slots: Dictionary = {}

var _log_rtl: RichTextLabel = null
var _banner_lbl: Label = null
var _continue_btn: Button = null

func start(attacker: SquadData, defender: SquadData, result: BattleResult) -> void:
	_attacker = attacker
	_defender = defender
	_result = result
	_build_ui()
	call_deferred("_play")

# ── UI Construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 0.90)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left  = -380.0
	panel.offset_right = 380.0
	panel.offset_top   = -280.0
	panel.offset_bottom = 280.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "-- BATTLE --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# Side-by-side grids
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var atk_col := VBoxContainer.new()
	hbox.add_child(atk_col)
	var atk_hdr := Label.new()
	atk_hdr.text = "Attacker"
	atk_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	atk_col.add_child(atk_hdr)
	atk_col.add_child(_build_grid(_attacker, _atk_slots))

	var vs_lbl := Label.new()
	vs_lbl.text = "VS"
	vs_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(vs_lbl)

	var def_col := VBoxContainer.new()
	hbox.add_child(def_col)
	var def_hdr := Label.new()
	def_hdr.text = "Defender"
	def_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	def_col.add_child(def_hdr)
	def_col.add_child(_build_grid(_defender, _def_slots))

	# Action log
	_log_rtl = RichTextLabel.new()
	_log_rtl.bbcode_enabled = true
	_log_rtl.custom_minimum_size = Vector2(0.0, 110.0)
	_log_rtl.scroll_following = true
	_log_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log_rtl)

	# Result banner
	_banner_lbl = Label.new()
	_banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_lbl.add_theme_font_size_override("font_size", 20)
	_banner_lbl.visible = false
	vbox.add_child(_banner_lbl)

	# Continue button
	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.visible = false
	_continue_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(_continue_btn)

func _build_grid(squad: SquadData, slots: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	# Row 0 = front, row 1 = back
	for row in [0, 1]:
		for col in [0, 1, 2]:
			var unit := squad.get_unit_at(row, col)
			var container := _make_slot(unit)
			if unit and unit.is_alive:
				# First child of container is the ColorRect box
				slots[unit.unit_name] = container.get_child(0) as ColorRect
			grid.add_child(container)
	return grid

func _make_slot(unit: UnitData) -> Control:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(96.0, 78.0)

	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(96.0, 50.0)
	if unit and unit.is_alive:
		var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id)
		box.color = cls.placeholder_color if cls else Color(0.4, 0.4, 0.4)
	else:
		box.color = Color(0.22, 0.22, 0.22)
	container.add_child(box)

	var name_lbl := Label.new()
	name_lbl.text = unit.unit_name if unit else "---"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.clip_text = true
	name_lbl.custom_minimum_size = Vector2(96.0, 0.0)
	container.add_child(name_lbl)

	if unit and unit.is_alive:
		var hp_bar := ProgressBar.new()
		hp_bar.min_value = 0.0
		hp_bar.max_value = float(unit.max_hp)
		hp_bar.value = float(unit.hp)
		hp_bar.show_percentage = false
		hp_bar.custom_minimum_size = Vector2(96.0, 10.0)
		container.add_child(hp_bar)
		box.set_meta("hp_bar", hp_bar)
		box.set_meta("unit_hp", unit.hp)
		box.set_meta("unit_max_hp", unit.max_hp)

	return container

# ── Playback ──────────────────────────────────────────────────────────────────

func _play() -> void:
	await _animate_battle()
	_show_result()

func _animate_battle() -> void:
	for action in _result.action_log:
		await get_tree().create_timer(DELAY).timeout
		_process_action(action as BattleAction)

func _process_action(action: BattleAction) -> void:
	var all_slots: Dictionary = {}
	all_slots.merge(_atk_slots)
	all_slots.merge(_def_slots)
	var box: ColorRect = all_slots.get(action.target_unit_id, null) as ColorRect

	match action.action_type:
		BattleAction.ActionType.ATTACK:
			_log_line("[color=white]%s — %s hits %s for %d![/color]" % [
				action.actor_unit_id, action.attack_name, action.target_unit_id, action.damage_dealt])
			if box:
				_show_damage_number(box, str(action.damage_dealt), Color(1.0, 0.45, 0.1))
				_update_hp(box, -action.damage_dealt)
		BattleAction.ActionType.MISS:
			_log_line("[color=gray]%s — %s misses %s![/color]" % [
				action.actor_unit_id, action.attack_name, action.target_unit_id])
			if box:
				_show_damage_number(box, "MISS", Color(1.0, 1.0, 0.3))
		BattleAction.ActionType.KILL:
			_log_line("[color=red]%s — %s defeats %s![/color]" % [
				action.actor_unit_id, action.attack_name, action.target_unit_id])
			if box:
				_show_damage_number(box, str(action.damage_dealt), Color(1.0, 0.1, 0.1))
				_update_hp(box, -action.damage_dealt)
				_grey_out_slot(box)
		BattleAction.ActionType.SKILL:
			if action.damage_dealt > 0:
				_log_line("[color=orange]%s — %s hits %s for %d![/color]" % [
					action.actor_unit_id, action.attack_name, action.target_unit_id, action.damage_dealt])
				if box:
					_show_damage_number(box, str(action.damage_dealt), Color(1.0, 0.6, 0.0))
					_update_hp(box, -action.damage_dealt)
			else:
				_log_line("[color=#c080ff]%s — %s: %s![/color]" % [
					action.actor_unit_id, action.attack_name, action.description])
				if box:
					_show_damage_number(box, action.description + "!", Color(0.75, 0.5, 1.0))
		BattleAction.ActionType.ROUND_START:
			_log_line("[color=#888888]── %s ──[/color]" % action.attack_name)
		BattleAction.ActionType.HEAL:
			_log_line("[color=green]%s — %s restores %d HP to %s![/color]" % [
				action.actor_unit_id, action.attack_name, action.damage_dealt, action.target_unit_id])
			var heal_box: ColorRect = all_slots.get(action.target_unit_id, null) as ColorRect
			if heal_box:
				_show_damage_number(heal_box, "+%d" % action.damage_dealt, Color(0.2, 1.0, 0.3))
				_update_hp(heal_box, action.damage_dealt)
		_:
			pass

func _log_line(bbcode: String) -> void:
	if _log_rtl:
		_log_rtl.append_text(bbcode + "\n")

func _update_hp(box: ColorRect, delta: int) -> void:
	if not box.has_meta("hp_bar"):
		return
	var bar: ProgressBar = box.get_meta("hp_bar") as ProgressBar
	var cur := int(box.get_meta("unit_hp")) + delta
	cur = maxi(0, cur)
	box.set_meta("unit_hp", cur)
	if bar:
		bar.value = float(cur)
		var max_hp: int = box.get_meta("unit_max_hp", 1) as int
		var frac := float(cur) / float(maxi(max_hp, 1))
		if frac > 0.5:
			bar.modulate = Color(0.2, 0.85, 0.2)
		elif frac > 0.25:
			bar.modulate = Color(0.9, 0.75, 0.1)
		else:
			bar.modulate = Color(0.9, 0.2, 0.2)

func _show_damage_number(box: ColorRect, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.z_index = 10
	lbl.position = Vector2(8.0, 8.0)
	box.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position", lbl.position + Vector2(0.0, -26.0), 0.55)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.55)
	tween.tween_callback(lbl.queue_free)

func _grey_out_slot(box: ColorRect) -> void:
	var tween := create_tween()
	tween.tween_property(box, "color", Color(0.18, 0.18, 0.18), 0.3)
	var parent := box.get_parent()
	if parent:
		var tween2 := create_tween()
		tween2.tween_property(parent, "modulate:a", 0.45, 0.3)

func _show_result() -> void:
	var winner_text: String
	if _result.attacker_wiped and _result.defender_wiped:
		winner_text = "Draw — both sides broken!"
	elif _result.defender_wiped:
		winner_text = "Attacker wins!"
	elif _result.attacker_wiped:
		winner_text = "Defender wins!"
	else:
		winner_text = "Both sides survive."

	# Count surviving player-side units to compute per-unit XP
	var player_xp: int = 0
	var player_survivors: int = 0
	if _attacker.faction == TerrainDefs.Faction.PLAYER:
		for u in _result.attacker_unit_states:
			if u.is_alive:
				player_survivors += 1
		if player_survivors > 0:
			player_xp = int(float(_result.attacker_xp) / float(player_survivors))
	elif _defender.faction == TerrainDefs.Faction.PLAYER:
		for u in _result.defender_unit_states:
			if u.is_alive:
				player_survivors += 1
		if player_survivors > 0:
			player_xp = int(float(_result.defender_xp) / float(player_survivors))

	var banner := winner_text
	if player_xp > 0:
		banner += "\nXP: +%d per unit" % player_xp
	for ev in _result.level_up_events:
		var unit_name: String = ev["unit_name"]
		var lvl: int = ev["new_level"]
		var promo: String = ev["promoted_to"]
		if promo != "":
			banner += "\n%s → Level %d! Promoted to %s!" % [unit_name, lvl, promo]
		else:
			banner += "\n%s → Level %d!" % [unit_name, lvl]
	_banner_lbl.text = banner
	_banner_lbl.visible = true
	_continue_btn.visible = true

func _on_continue_pressed() -> void:
	battle_completed.emit()
