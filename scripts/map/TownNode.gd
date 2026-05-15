class_name TownNode
extends StaticBody3D

signal town_captured(town: TownNode, new_faction: int)
signal town_selected(town: TownNode)

var town_data: TownData
var faction: int = TerrainDefs.Faction.NEUTRAL
var _base_y: float = 0.1

func setup(data: TownData, base_y: float) -> void:
	town_data = data
	faction   = data.starting_faction
	_base_y   = base_y
	_build_visuals()
	_add_select_area()

func set_faction(new_faction: int) -> void:
	faction = new_faction
	for c in get_children():
		c.queue_free()
	_build_visuals()
	_add_select_area()
	emit_signal("town_captured", self, new_faction)

func _build_visuals() -> void:
	var is_hq   := (town_data.town_type == TerrainDefs.TownType.HQ)
	var fc      := _faction_color()
	var tower_h := 1.8 if is_hq else 1.2

	# Base platform
	var base := _make_box(Vector3(1.5, 0.4, 1.5), fc)
	base.position.y = _base_y + 0.2
	add_child(base)

	# Tower
	var tower := _make_box(Vector3(0.6, tower_h, 0.6), fc.lightened(0.2))
	tower.position.y = _base_y + 0.4 + tower_h * 0.5
	add_child(tower)

	# Flag
	var flag := _make_cylinder(0.1, 0.1, 0.3, fc)
	flag.position.y = _base_y + 0.4 + tower_h + 0.15
	add_child(flag)

func _add_select_area() -> void:
	var area  := Area3D.new()
	var col   := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 1.6
	col.shape = shape
	col.position.y = _base_y + 0.8
	area.add_child(col)
	area.input_ray_pickable = true
	area.input_event.connect(_on_area_input)
	add_child(area)

func _on_area_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("town_selected", self)

func _faction_color() -> Color:
	match faction:
		TerrainDefs.Faction.PLAYER: return Color(0.20, 0.40, 0.90)
		TerrainDefs.Faction.ENEMY:  return Color(0.90, 0.20, 0.20)
		_:                          return Color(0.55, 0.55, 0.55)

func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m   := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh   = box
	m.material_override = _mat(color)
	return m

func _make_cylinder(top_r: float, bot_r: float, height: float, color: Color) -> MeshInstance3D:
	var m   := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = top_r
	cyl.bottom_radius = bot_r
	cyl.height        = height
	m.mesh   = cyl
	m.material_override = _mat(color)
	return m

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
