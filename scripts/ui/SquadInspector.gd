class_name SquadInspector
extends Panel

var _title_label: Label
var _slot_labels: Array = []
var _speed_label: Label
var _movement_label: Label

const MOVEMENT_NAMES: Array = ["Infantry", "Cavalry", "Flying", "Aquatic"]

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Squad"
	_title_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_title_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 2-column grid: front | back, 3 rows (one per column in the squad)
	var grid := GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)

	var fh := Label.new()
	fh.text = "  Front"
	fh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(fh)

	var bh := Label.new()
	bh.text = "  Back"
	bh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(bh)

	_slot_labels = []
	for _i in range(6):  # 3 squad-cols × 2 (front/back)
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(88, 52)
		grid.add_child(slot)

		var lbl := Label.new()
		lbl.text = "---"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 10)
		slot.add_child(lbl)
		_slot_labels.append(lbl)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	_speed_label = Label.new()
	_speed_label.text = "Speed: ---"
	_speed_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_speed_label)

	_movement_label = Label.new()
	_movement_label.text = "Movement: ---"
	_movement_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_movement_label)

func show_squad(data: SquadData) -> void:
	if not data:
		return
	visible = true

	var leader := data.get_leader()
	_title_label.text = "Squad: " + (leader.unit_name if leader else "???")

	# Slots: each row = one squad-column; left = front (row 0), right = back (row 1)
	var slot_idx: int = 0
	for sq_col in range(3):
		for row in range(2):
			var lbl: Label = _slot_labels[slot_idx]
			var unit := data.get_unit_at(row, sq_col)
			if unit and unit.is_alive:
				var cls_display := unit.class_id.capitalize()
				lbl.text = "%s L%d\n%d/%d" % [cls_display, unit.level, unit.hp, unit.max_hp]
				if unit.is_leader:
					lbl.text = "* " + lbl.text
			else:
				lbl.text = "---"
			slot_idx += 1

	_speed_label.text = "Speed: %.1f u/s" % data.move_speed

	var mt_idx: int = int(data.movement_type)
	var mt_name: String = MOVEMENT_NAMES[mt_idx] if mt_idx < MOVEMENT_NAMES.size() else "???"
	_movement_label.text = "Movement: " + mt_name

func hide_inspector() -> void:
	visible = false
