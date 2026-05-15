class_name MapCell
extends StaticBody3D

var grid_x: int = 0
var grid_z: int = 0
var terrain_type: TerrainDefs.TerrainType = TerrainDefs.TerrainType.PLAINS

func setup(gx: int, gz: int, terrain: TerrainDefs.TerrainType, cell_size: float) -> void:
	grid_x = gx
	grid_z = gz
	terrain_type = terrain

	var box_h  := TerrainDefs.get_box_height(terrain)
	var ctr_y  := TerrainDefs.get_center_y(terrain)
	var color  := _terrain_color(terrain)
	var gap    := cell_size * 0.98   # tiny visual gap between cells

	var mesh := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size = Vector3(gap, box_h, gap)
	mesh.mesh = box
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.position.y = ctr_y
	add_child(mesh)

	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(gap, box_h, gap)
	col.shape = shape
	col.position.y = ctr_y
	add_child(col)

	if terrain == TerrainDefs.TerrainType.FOREST:
		_add_trees(cell_size, TerrainDefs.get_top_y(terrain))

func get_top_y() -> float:
	return TerrainDefs.get_top_y(terrain_type)

func _terrain_color(t: TerrainDefs.TerrainType) -> Color:
	match t:
		TerrainDefs.TerrainType.WATER:    return Color("#3a6ea5")
		TerrainDefs.TerrainType.PLAINS:   return Color("#c8d45a")
		TerrainDefs.TerrainType.GRASS:    return Color("#4a8c3f")
		TerrainDefs.TerrainType.FOREST:   return Color("#2d5a27")
		TerrainDefs.TerrainType.MOUNTAIN: return Color("#8a8a8a")
		TerrainDefs.TerrainType.ROAD:     return Color("#c2a86a")
		_:                                return Color.WHITE

func _add_trees(cell_size: float, base_y: float) -> void:
	var offsets := [
		Vector3(-cell_size * 0.22, 0.0, -cell_size * 0.22),
		Vector3( cell_size * 0.22, 0.0,  cell_size * 0.22),
		Vector3(-cell_size * 0.10, 0.0,  cell_size * 0.18),
	]
	for off in offsets:
		var tree     := MeshInstance3D.new()
		var cyl      := CylinderMesh.new()
		cyl.top_radius    = 0.0
		cyl.bottom_radius = 0.18
		cyl.height        = 0.45
		tree.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#1a7a14")
		tree.material_override = mat
		tree.position = off + Vector3(0.0, base_y + 0.225, 0.0)
		add_child(tree)
