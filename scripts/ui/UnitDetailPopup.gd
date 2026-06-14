class_name UnitDetailPopup
extends Panel

var _vbox: VBoxContainer = null

const DAMAGE_TYPE_NAMES: Array = ["Physical", "Fire", "Cold", "Thunder", "Holy", "Dark"]

func _ready() -> void:
	visible = false
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	_vbox = vbox

func show_unit(unit: UnitData) -> void:
	for child in _vbox.get_children():
		child.free()

	var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id)
	var cls_name: String = cls.display_name if cls else unit.class_id.capitalize()

	# Header
	var star: String = "* " if unit.is_leader else ""
	var hdr := Label.new()
	hdr.text = "%s%s  —  Lv.%d" % [star, cls_name, unit.level]
	hdr.add_theme_font_size_override("font_size", 15)
	hdr.modulate = Color(0.94, 0.75, 0.25)
	_vbox.add_child(hdr)

	var name_lbl := Label.new()
	name_lbl.text = ("★ HERO  " + unit.unit_name) if unit.is_hero else unit.unit_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.modulate = Color(1.0, 0.84, 0.0) if unit.is_hero else Color(0.78, 0.78, 0.88)
	_vbox.add_child(name_lbl)

	var color_box := ColorRect.new()
	color_box.color = cls.placeholder_color if cls else Color(0.35, 0.35, 0.45)
	color_box.custom_minimum_size = Vector2(0, 36)
	_vbox.add_child(color_box)

	_vbox.add_child(HSeparator.new())

	# Stats grid (4 cols: label|val|label|val)
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 10)
	_vbox.add_child(sg)
	_stat(sg, "HP",  "%d/%d" % [unit.hp, unit.max_hp])
	_stat(sg, "STR", str(unit.strength))
	_stat(sg, "AGI", str(unit.agility))
	_stat(sg, "INT", str(unit.intelligence))
	_stat(sg, "DEF", str(unit.defense))
	_stat(sg, "RES", str(unit.resistance))

	# XP bar
	var xp_row := HBoxContainer.new()
	_vbox.add_child(xp_row)
	var xl := Label.new()
	xl.text = "XP: "
	xl.add_theme_font_size_override("font_size", 11)
	xp_row.add_child(xl)
	var xb := ProgressBar.new()
	xb.min_value = 0.0
	xb.max_value = float(maxi(unit.xp_to_next, 1))
	xb.value = float(unit.xp)
	xb.show_percentage = false
	xb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xb.modulate = Color(0.35, 0.65, 1.0)
	xp_row.add_child(xb)
	var xv := Label.new()
	xv.text = " %d/%d" % [unit.xp, unit.xp_to_next]
	xv.add_theme_font_size_override("font_size", 10)
	xp_row.add_child(xv)

	if cls:
		_vbox.add_child(HSeparator.new())

		var atk_hdr := Label.new()
		atk_hdr.text = "ATTACKS"
		atk_hdr.add_theme_font_size_override("font_size", 11)
		_vbox.add_child(atk_hdr)

		for atk in cls.front_attacks:
			_atk_line("Front", atk as AttackDefinition)
		for atk in cls.back_attacks:
			_atk_line("Back", atk as AttackDefinition)

		if not cls.skills.is_empty():
			_vbox.add_child(HSeparator.new())
			var skill_hdr := Label.new()
			skill_hdr.text = "SKILLS"
			skill_hdr.add_theme_font_size_override("font_size", 11)
			_vbox.add_child(skill_hdr)
			for sk in cls.skills:
				_skill_line(sk)

		if not cls.promotions.is_empty():
			_vbox.add_child(HSeparator.new())
			var pr: PromotionRequirement = cls.promotions[0] as PromotionRequirement
			var pl := Label.new()
			pl.add_theme_font_size_override("font_size", 11)
			pl.text = "Promotion: → %s at Lv.%d" % [pr.target_class_id.capitalize(), pr.required_level]
			if unit.level >= pr.required_level:
				pl.modulate = Color(0.94, 0.75, 0.25)
				pl.text = "★ " + pl.text + " (READY)"
			_vbox.add_child(pl)

	_vbox.add_child(HSeparator.new())

	var cb := Button.new()
	cb.text = "Close"
	cb.pressed.connect(func(): visible = false)
	_vbox.add_child(cb)

	visible = true

func _stat(grid: GridContainer, label: String, value: String) -> void:
	var lbl := Label.new()
	lbl.text = label + ":"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.78, 0.78, 0.88)
	grid.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 11)
	grid.add_child(val)

func _skill_line(skill) -> void:
	var lbl := Label.new()
	lbl.text = "  %s: %s" % [skill.display_name, skill.description]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(lbl)

func _atk_line(row_label: String, atk: AttackDefinition) -> void:
	var dt_idx: int = int(atk.damage_type)
	var dt_name: String = DAMAGE_TYPE_NAMES[dt_idx] if dt_idx < DAMAGE_TYPE_NAMES.size() else "???"
	var lbl := Label.new()
	lbl.text = "  %s: %s ×%d (%s)" % [row_label, atk.attack_name, atk.hits, dt_name]
	lbl.add_theme_font_size_override("font_size", 10)
	_vbox.add_child(lbl)
