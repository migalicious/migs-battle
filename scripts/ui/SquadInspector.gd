class_name SquadInspector
extends Panel

const SLOT_SIZE := Vector2(80.0, 80.0)
const MOVEMENT_NAMES: Array = ["Infantry", "Cavalry", "Flying", "Aquatic"]

var _header_lbl: Label = null
var _class_lbl: Label = null
var _slots: Array[Control] = []
var _speed_lbl: Label = null
var _movement_lbl: Label = null
var _popup: UnitDetailPopup = null

func _ready() -> void:
	_build_ui()
	visible = false
	call_deferred("_link_popup")

func _link_popup() -> void:
	var parent := get_parent()
	if parent and parent.has_node("UnitDetailPopup"):
		_popup = parent.get_node("UnitDetailPopup") as UnitDetailPopup

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Leader name header
	_header_lbl = Label.new()
	_header_lbl.text = "No squad selected"
	_header_lbl.add_theme_font_size_override("font_size", 14)
	_header_lbl.modulate = Color(0.94, 0.75, 0.25)
	vbox.add_child(_header_lbl)

	# Class + level subheader
	_class_lbl = Label.new()
	_class_lbl.add_theme_font_size_override("font_size", 11)
	_class_lbl.modulate = Color(0.78, 0.78, 0.88)
	vbox.add_child(_class_lbl)

	vbox.add_child(HSeparator.new())

	# Row labels (FRONT / BACK above the 3-col grid)
	var row_hdr := HBoxContainer.new()
	vbox.add_child(row_hdr)
	var front_hdr := Label.new()
	front_hdr.text = "FRONT"
	front_hdr.add_theme_font_size_override("font_size", 10)
	front_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_hdr.add_child(front_hdr)
	var back_hdr := Label.new()
	back_hdr.text = "BACK"
	back_hdr.add_theme_font_size_override("font_size", 10)
	back_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row_hdr.add_child(back_hdr)

	# 2 rows × 3 cols grid (row=0 front, row=1 back; cols 0-2 = squad cols)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	_slots = []
	for _i in range(6):
		var slot := _make_slot()
		_slots.append(slot)
		grid.add_child(slot)

	vbox.add_child(HSeparator.new())

	_movement_lbl = Label.new()
	_movement_lbl.text = "Movement: ---"
	_movement_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_movement_lbl)

	_speed_lbl = Label.new()
	_speed_lbl.text = "Speed: ---"
	_speed_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_speed_lbl)

func _make_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.clip_contents = true
	slot.gui_input.connect(_on_slot_input.bind(slot))

	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.18, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bg)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(content)

	slot.set_meta("bg", bg)
	slot.set_meta("content", content)
	slot.set_meta("unit_data", null)
	return slot

func _populate_slot(slot: Control, unit: UnitData) -> void:
	var bg: ColorRect = slot.get_meta("bg") as ColorRect
	var content: VBoxContainer = slot.get_meta("content") as VBoxContainer

	for child in content.get_children():
		child.free()

	slot.set_meta("unit_data", null)

	if not unit or not unit.is_alive:
		bg.color = Color(0.18, 0.18, 0.22)
		return

	slot.set_meta("unit_data", unit)

	var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id) as ClassDefinition
	bg.color = cls.placeholder_color if cls else Color(0.35, 0.35, 0.45)

	# Top row: star | spacer | level
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(top_row)

	var star_lbl := Label.new()
	star_lbl.text = "*" if unit.is_leader else " "
	star_lbl.add_theme_font_size_override("font_size", 11)
	star_lbl.modulate = Color(0.94, 0.75, 0.25)
	star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(star_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)

	if unit.is_wounded:
		var wound_lbl := Label.new()
		wound_lbl.text = "~"
		wound_lbl.add_theme_font_size_override("font_size", 11)
		wound_lbl.modulate = Color(0.9, 0.55, 0.1)
		wound_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_row.add_child(wound_lbl)

	var lv_lbl := Label.new()
	lv_lbl.text = "L%d" % unit.level
	lv_lbl.add_theme_font_size_override("font_size", 9)
	lv_lbl.modulate = Color(0.85, 0.85, 0.85)
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(lv_lbl)

	# Class name (expands to fill remaining space)
	var cls_lbl := Label.new()
	cls_lbl.text = unit.class_id.capitalize()
	cls_lbl.add_theme_font_size_override("font_size", 9)
	cls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cls_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cls_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cls_lbl.clip_text = true
	cls_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cls_lbl)

	# HP bar pinned to bottom
	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0.0
	hp_bar.max_value = float(unit.max_hp)
	hp_bar.value = float(unit.hp)
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(0, 12)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_frac := float(unit.hp) / float(unit.max_hp) if unit.max_hp > 0 else 0.0
	if hp_frac > 0.5:
		hp_bar.modulate = Color(0.2, 0.85, 0.2)
	elif hp_frac > 0.25:
		hp_bar.modulate = Color(0.9, 0.75, 0.1)
	else:
		hp_bar.modulate = Color(0.9, 0.2, 0.2)
	content.add_child(hp_bar)

func show_squad(data: SquadData) -> void:
	if not data:
		return
	visible = true

	var leader := data.get_leader()
	if leader:
		_header_lbl.text = "* " + leader.unit_name
		var cls_def: ClassDefinition = UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
		var cls_name: String = cls_def.display_name if cls_def else leader.class_id.capitalize()
		_class_lbl.text = "%s  Lv.%d" % [cls_name, leader.level]
	else:
		_header_lbl.text = "Unknown Squad"
		_class_lbl.text = ""

	# Row 0 (front): slots 0-2; Row 1 (back): slots 3-5
	for sq_col in range(3):
		_populate_slot(_slots[sq_col],     data.get_unit_at(0, sq_col))
		_populate_slot(_slots[3 + sq_col], data.get_unit_at(1, sq_col))

	var mt_idx: int = int(data.get_movement_type())
	_movement_lbl.text = "Movement: " + (MOVEMENT_NAMES[mt_idx] if mt_idx < MOVEMENT_NAMES.size() else "???")
	_speed_lbl.text = "Speed: %.1f u/s" % data.move_speed

func hide_inspector() -> void:
	visible = false

func _on_slot_input(event: InputEvent, slot: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var unit: UnitData = slot.get_meta("unit_data") as UnitData
			if unit and _popup:
				_popup.show_unit(unit)
