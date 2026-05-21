class_name TownNode
extends StaticBody3D

signal town_captured(town: TownNode, new_faction: int)
signal town_selected(town: TownNode)

const TICK_INTERVAL: float = 3.0

var town_data: TownData
var faction: int = TerrainDefs.Faction.NEUTRAL
var _base_y: float = 0.0

# Capture state
var capture_ticks: int = 0
var occupying_squad: Squad = null
var tick_timer: float = 0.0

# Garrison state
var garrisoned_squad: Squad = null

# Stored material refs for tweening
var _base_mat: StandardMaterial3D = null
var _tower_mat: StandardMaterial3D = null
var _flag_mat: StandardMaterial3D = null

# Dynamic child nodes
var _garrison_indicator: MeshInstance3D = null
var _capture_label: Label3D = null

func setup(data: TownData, base_y: float) -> void:
	town_data = data
	faction = data.starting_faction
	_base_y = base_y
	_build_visuals()
	_add_select_area()

func _process(delta: float) -> void:
	if not town_data or not is_instance_valid(occupying_squad):
		occupying_squad = null
		return
	if occupying_squad.faction == faction:
		return  # friendly garrison — not capturing
	# Cancel if squad moved away
	if global_position.distance_to(occupying_squad.global_position) > 3.0:
		stop_capture()
		return
	tick_timer += delta
	if tick_timer >= TICK_INTERVAL:
		tick_timer = 0.0
		capture_ticks += 1
		_update_capture_label()
		if capture_ticks >= town_data.capture_turns:
			_complete_capture(occupying_squad.faction)

# ── Public API ────────────────────────────────────────────────────────────────

func begin_capture(squad: Squad) -> void:
	occupying_squad = squad
	capture_ticks = 0
	tick_timer = 0.0
	_update_capture_label()

func stop_capture() -> void:
	occupying_squad = null
	capture_ticks = 0
	tick_timer = 0.0
	_update_capture_label()

func set_garrison(squad: Squad) -> void:
	garrisoned_squad = squad
	occupying_squad = squad
	if _garrison_indicator:
		var mat := _garrison_indicator.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = _faction_color(squad.faction)
		_garrison_indicator.visible = true

func clear_garrison() -> void:
	if not is_instance_valid(garrisoned_squad) or garrisoned_squad == occupying_squad:
		occupying_squad = null
	garrisoned_squad = null
	if _garrison_indicator:
		_garrison_indicator.visible = false

func set_faction(new_faction: int) -> void:
	faction = new_faction
	if town_data:
		GameState.town_ownership[town_data.town_id] = new_faction
	_tween_colors(new_faction)
	emit_signal("town_captured", self, new_faction)

# ── Internal ──────────────────────────────────────────────────────────────────

func _complete_capture(new_faction: int) -> void:
	faction = new_faction
	occupying_squad = null
	capture_ticks = 0
	tick_timer = 0.0
	if town_data:
		GameState.town_ownership[town_data.town_id] = new_faction
	_update_capture_label()
	_tween_colors(new_faction)
	emit_signal("town_captured", self, new_faction)
	GameState.check_win_conditions()

func _build_visuals() -> void:
	var is_hq: bool = town_data.town_type == TerrainDefs.TownType.HQ
	var tower_h: float = 1.8 if is_hq else 1.2
	var base_w: float = 2.2 if is_hq else 1.5
	var base_h: float = 0.6 if is_hq else 0.4
	var fc := _faction_color(faction)

	# Base platform
	var base_mi := _make_box(Vector3(base_w, base_h, base_w), fc)
	base_mi.position.y = _base_y + base_h * 0.5
	add_child(base_mi)
	_base_mat = base_mi.get_surface_override_material(0) as StandardMaterial3D

	# Tower
	var tower_mi := _make_box(Vector3(0.6, tower_h, 0.6), fc.darkened(0.15))
	tower_mi.position.y = _base_y + base_h + tower_h * 0.5
	add_child(tower_mi)
	_tower_mat = tower_mi.get_surface_override_material(0) as StandardMaterial3D

	var tower_top_y: float = _base_y + base_h + tower_h

	# Flag cylinder
	var flag_mi := _make_cylinder(0.08, 0.08, 0.5, fc)
	flag_mi.position.y = tower_top_y + 0.25
	add_child(flag_mi)
	_flag_mat = flag_mi.get_surface_override_material(0) as StandardMaterial3D

	# Garrison indicator (hidden initially)
	var gar_box := BoxMesh.new()
	gar_box.size = Vector3(0.35, 0.35, 0.35)
	_garrison_indicator = MeshInstance3D.new()
	_garrison_indicator.mesh = gar_box
	var gar_mat := StandardMaterial3D.new()
	gar_mat.albedo_color = fc
	_garrison_indicator.set_surface_override_material(0, gar_mat)
	_garrison_indicator.position.y = tower_top_y + 0.2
	_garrison_indicator.visible = false
	add_child(_garrison_indicator)

	# Capture progress label (hidden initially)
	_capture_label = Label3D.new()
	_capture_label.pixel_size = 0.02
	_capture_label.font_size = 14
	_capture_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_capture_label.outline_modulate = Color.BLACK
	_capture_label.position = Vector3(0.0, tower_top_y + 1.2, 0.0)
	_capture_label.visible = false
	add_child(_capture_label)

func _add_select_area() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 1.6
	col.shape = shape
	col.position.y = _base_y + 0.8
	area.add_child(col)
	area.input_ray_pickable = true
	area.input_event.connect(_on_area_input)
	add_child(area)

func _on_area_input(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("town_selected", self)

func _update_capture_label() -> void:
	if not _capture_label:
		return
	if occupying_squad == null or occupying_squad.faction == faction:
		_capture_label.visible = false
		return
	_capture_label.visible = true
	_capture_label.text = "Capturing %d/%d" % [capture_ticks, town_data.capture_turns]

func _tween_colors(new_faction: int) -> void:
	var target := _faction_color(new_faction)
	var tween := create_tween()
	tween.set_parallel(true)
	if _base_mat:
		tween.tween_property(_base_mat, "albedo_color", target, 0.5)
	if _flag_mat:
		tween.tween_property(_flag_mat, "albedo_color", target, 0.5)
	if _tower_mat:
		tween.tween_property(_tower_mat, "albedo_color", target.darkened(0.15), 0.5)

func _faction_color(f: int) -> Color:
	match f:
		TerrainDefs.Faction.PLAYER: return Color(0.20, 0.40, 0.90)
		TerrainDefs.Faction.ENEMY:  return Color(0.90, 0.20, 0.20)
		_:                          return Color(0.55, 0.55, 0.55)

func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.set_surface_override_material(0, _mat(color))
	return m

func _make_cylinder(top_r: float, bot_r: float, height: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = height
	m.mesh = cyl
	m.set_surface_override_material(0, _mat(color))
	return m

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
