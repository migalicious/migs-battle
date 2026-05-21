class_name Squad
extends CharacterBody3D

signal squad_selected(squad: Squad)
signal squad_arrived(squad: Squad, destination: Vector3)
signal squad_collided_with_enemy(squad_a: Squad, squad_b: Squad)

var squad_data: SquadData = null
var faction: int = 0
var map_manager: MapManager = null  # set by SquadController after wire_squad

# Set by SquadController to prevent double-battle triggers
var in_battle: bool = false

# Garrison state
var is_garrisoned: bool = false
var garrison_town: TownNode = null

@onready var _nav_agent: NavigationAgent3D = $NavAgent
@onready var _label: Label3D = $Label3D
@onready var _highlight: MeshInstance3D = $HighlightRing
@onready var _mesh_inst: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision
@onready var _detection_area: Area3D = $DetectionArea

var _is_selected: bool = false
var _is_moving: bool = false
var _destination: Vector3 = Vector3.ZERO
var _is_flying: bool = false
var _path_line: MeshInstance3D = null

func _ready() -> void:
	# Capsule body mesh
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.35
	cap_mesh.height = 0.9
	_mesh_inst.mesh = cap_mesh
	_mesh_inst.position = Vector3(0.0, 0.45, 0.0)

	# Capsule collision shape
	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.35
	cap_shape.height = 0.9
	_collision.shape = cap_shape
	_collision.position = Vector3(0.0, 0.45, 0.0)

	# Highlight ring (hidden until selected)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.45
	ring_mesh.outer_radius = 0.65
	_highlight.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.85)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.set_surface_override_material(0, ring_mat)
	_highlight.position = Vector3(0.0, 0.05, 0.0)
	_highlight.visible = false

	# Label
	_label.pixel_size = 0.02
	_label.font_size = 14
	_label.position = Vector3(0.0, 1.2, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color.WHITE

	# Detection area sphere
	var area_col := $DetectionArea/AreaShape as CollisionShape3D
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	area_col.shape = sphere
	_detection_area.area_entered.connect(_on_area_entered)

	# Nav agent settings
	_nav_agent.path_desired_distance = 0.5
	_nav_agent.target_desired_distance = 0.5

	# Path line — thin box from squad to destination, shown while moving
	_path_line = MeshInstance3D.new()
	_path_line.mesh = BoxMesh.new()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_path_line.set_surface_override_material(0, line_mat)
	_path_line.visible = false
	add_child(_path_line)

func setup(data: SquadData) -> void:
	squad_data = data
	faction = data.faction

	# Faction-colored body material — unshaded so the color isn't darkened by scene lighting
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _faction_color(faction)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_inst.set_surface_override_material(0, mat)

	# Path line: lightened faction color
	var line_mat := _path_line.get_surface_override_material(0) as StandardMaterial3D
	if line_mat:
		var fc := _faction_color(faction)
		line_mat.albedo_color = Color(
			minf(fc.r * 0.6 + 0.4, 1.0),
			minf(fc.g * 0.6 + 0.4, 1.0),
			minf(fc.b * 0.6 + 0.4, 1.0),
			0.65)

	# Determine flying movement from leader class
	var leader := data.get_leader()
	if leader:
		var cls := UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
		if cls:
			_is_flying = cls.movement_type == TerrainDefs.MovementType.FLYING

	# Recalculate speed for starting terrain
	data.recalculate_speed(TerrainDefs.TerrainType.PLAINS)

	_update_label()

func _update_label() -> void:
	if not squad_data or not _label:
		return
	var leader := squad_data.get_leader()
	_label.text = leader.unit_name if leader else "???"

func _process(_delta: float) -> void:
	if _is_moving and _path_line:
		_update_path_line()

func _physics_process(_delta: float) -> void:
	if is_garrisoned:
		velocity = Vector3.ZERO
		return
	if not _is_moving or not squad_data:
		velocity = Vector3.ZERO
		return

	if _is_flying:
		var dir := _destination - global_position
		dir.y = 0.0
		if dir.length() < 0.3:
			_stop_moving()
			return
		velocity = dir.normalized() * squad_data.move_speed
	else:
		if _nav_agent.is_navigation_finished():
			_stop_moving()
			return
		var next_pos := _nav_agent.get_next_path_position()
		var dir := next_pos - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			velocity = dir.normalized() * squad_data.move_speed
		else:
			velocity = Vector3.ZERO

	move_and_slide()
	_update_terrain_speed()

func _stop_moving() -> void:
	_is_moving = false
	velocity = Vector3.ZERO
	if _path_line:
		_path_line.visible = false
	squad_arrived.emit(self, _destination)

func _update_path_line() -> void:
	var start := Vector3(global_position.x, 0.08, global_position.z)
	var end   := Vector3(_destination.x,    0.08, _destination.z)
	var diff  := end - start
	var length := diff.length()
	if length < 0.2:
		_path_line.visible = false
		return
	_path_line.visible = true
	var box := _path_line.mesh as BoxMesh
	box.size = Vector3(0.15, 0.05, length)
	_path_line.global_position = (start + end) * 0.5
	var dir := diff / length
	_path_line.global_basis = Basis.looking_at(dir, Vector3.UP)

func set_destination(world_pos: Vector3) -> void:
	_destination = Vector3(world_pos.x, global_position.y, world_pos.z)
	_is_moving = true
	if not _is_flying and _nav_agent:
		_nav_agent.target_position = _destination

func select_squad() -> void:
	_is_selected = true
	_highlight.visible = true
	squad_selected.emit(self)

func deselect_squad() -> void:
	_is_selected = false
	_highlight.visible = false

func is_selected() -> bool:
	return _is_selected

func garrison_at(town: TownNode) -> void:
	is_garrisoned = true
	garrison_town = town
	_is_moving = false
	velocity = Vector3.ZERO
	if _path_line:
		_path_line.visible = false

func ungarrison() -> void:
	is_garrisoned = false
	garrison_town = null

func retreat_to(world_pos: Vector3) -> void:
	global_position = Vector3(world_pos.x, 0.5, world_pos.z)
	_is_moving = false
	is_garrisoned = false
	garrison_town = null
	if _path_line:
		_path_line.visible = false

func _update_terrain_speed() -> void:
	if not squad_data or not map_manager:
		return
	var grid := map_manager.world_to_grid(global_position)
	var terrain := map_manager.get_terrain(grid.x, grid.y)
	squad_data.recalculate_speed(terrain)

func _faction_color(f: int) -> Color:
	if f == TerrainDefs.Faction.PLAYER:
		return Color(0.20, 0.40, 0.90)
	if f == TerrainDefs.Faction.ENEMY:
		return Color(1.0, 0.2, 0.2)
	return Color.WHITE

func _on_area_entered(area: Area3D) -> void:
	if in_battle:
		return
	var other := area.get_parent() as Squad
	if other and other.faction != faction and not other.in_battle:
		squad_collided_with_enemy.emit(self, other)
