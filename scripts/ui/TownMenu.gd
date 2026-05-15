class_name TownMenu
extends Panel

signal deploy_requested(squad_data: SquadData, town: TownNode)
signal closed()

var _current_town: TownNode = null
var _reserve_squads: Array = []

var _title_label: Label
var _type_label: Label
var _garrison_label: Label
var _deploy_container: VBoxContainer
var _close_btn: Button

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_title_label)

	_type_label = Label.new()
	_type_label.add_theme_font_size_override("font_size", 11)
	_type_label.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(_type_label)

	vbox.add_child(HSeparator.new())

	_garrison_label = Label.new()
	_garrison_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_garrison_label)

	vbox.add_child(HSeparator.new())

	var deploy_header := Label.new()
	deploy_header.text = "Reserve Squads:"
	deploy_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(deploy_header)

	_deploy_container = VBoxContainer.new()
	vbox.add_child(_deploy_container)

	vbox.add_child(HSeparator.new())

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(_close_btn)

func open(town: TownNode, reserve: Array) -> void:
	_current_town = town
	_reserve_squads = reserve
	_refresh()
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if not _current_town or not _current_town.town_data:
		return

	_title_label.text = _current_town.town_data.display_name \
		if _current_town.town_data.display_name != "" \
		else "Town"

	var type_names: Array = ["Town", "Castle", "HQ"]
	var t_idx: int = int(_current_town.town_data.town_type)
	_type_label.text = "Type: " + (type_names[t_idx] if t_idx < type_names.size() else "???")

	if _current_town.garrisoned_squad:
		var leader := _current_town.garrisoned_squad.squad_data.get_leader()
		_garrison_label.text = "Garrison: " + (leader.unit_name if leader else "???")
	else:
		_garrison_label.text = "Garrison: Empty"

	# Rebuild deploy buttons
	for c in _deploy_container.get_children():
		c.queue_free()

	if _reserve_squads.is_empty():
		var no_lbl := Label.new()
		no_lbl.text = "(No reserve squads)"
		no_lbl.add_theme_font_size_override("font_size", 10)
		_deploy_container.add_child(no_lbl)
	else:
		for rd in _reserve_squads:
			var squad_data := rd as SquadData
			if not squad_data:
				continue
			var leader := squad_data.get_leader()
			var btn := Button.new()
			btn.text = "Deploy: " + (leader.unit_name if leader else "???")
			btn.pressed.connect(_on_deploy_pressed.bind(squad_data))
			_deploy_container.add_child(btn)

func _on_deploy_pressed(squad_data: SquadData) -> void:
	deploy_requested.emit(squad_data, _current_town)
	close()

func _on_close_pressed() -> void:
	close()
