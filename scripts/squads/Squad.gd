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

# Stuck-detection tuning (see _physics_process).
const STUCK_STOP_TIME := 0.5    # game-time seconds of zero progress before reacting
const ARRIVAL_RADIUS := 2.0     # "close enough" to the destination to treat a stall as arrival
const MAX_REPATH_TRIES := 4     # open-ground re-path attempts before giving up and stopping
const BLOCK_RANGE := 1.6        # a hostile within this distance is treated as physically blocking

var _is_selected: bool = false
var _is_moving: bool = false
var _destination: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _last_progress_pos: Vector3 = Vector3.ZERO
var _repath_tries: int = 0
var _is_flying: bool = false
var _is_aquatic: bool = false
var _path_line: MeshInstance3D = null

# Post-battle recoil (see apply_battle_recoil / _physics_process). After a battle both squads get
# a brief invulnerability window so they can't instantly re-collide while still stacked; the loser
# also slides away along _knockback_dir.
var _invuln_time: float = 0.0
var _knockback_time: float = 0.0
var _knockback_dir: Vector3 = Vector3.ZERO
var _last_heading: Vector3 = Vector3.ZERO   # last non-zero move direction; used to aim knockback

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
			_is_aquatic = cls.movement_type == TerrainDefs.MovementType.AQUATIC

	# Recalculate speed for starting terrain
	data.recalculate_speed(TerrainDefs.TerrainType.PLAINS)

	_update_label()

func _update_label() -> void:
	if not squad_data or not _label:
		return
	var leader := squad_data.get_leader()
	_label.text = leader.unit_name if leader else "???"

func _process(delta: float) -> void:
	if is_garrisoned and squad_data:
		_heal_garrison(delta)
	if _is_moving and _path_line:
		_update_path_line()

func _heal_garrison(delta: float) -> void:
	if _garrison_contested():
		return  # no free healing while a hostile squad is besieging the town
	for unit in squad_data.units:
		var u := unit as UnitData
		if not u.is_alive or u.hp >= u.max_hp:
			continue
		var heal := int(float(u.max_hp) * GameBalance.GARRISON_HEAL_RATE * delta)
		if heal > 0:
			u.hp = mini(u.max_hp, u.hp + heal)
			u.is_wounded = float(u.hp) / float(maxi(u.max_hp, 1)) < 0.25

func _garrison_contested() -> bool:
	if not is_instance_valid(garrison_town):
		return false
	for f in GameState.active_factions:
		if not GameState.are_hostile(faction, f):
			continue
		for sq in GameState.get_squads_by_faction(f):
			if is_instance_valid(sq) and not sq.in_battle \
					and sq.global_position.distance_to(garrison_town.global_position) < 2.5:
				return true
	return false

func _physics_process(delta: float) -> void:
	# Post-battle recoil takes priority over everything else. Tick the invuln window down, and while
	# the loser is being knocked back, slide it along _knockback_dir and skip nav/stuck logic so the
	# pathfinder doesn't immediately fight the slide.
	if _invuln_time > 0.0:
		_invuln_time = maxf(0.0, _invuln_time - delta)
	if _knockback_time > 0.0:
		_knockback_time = maxf(0.0, _knockback_time - delta)
		velocity = _knockback_dir * (GameBalance.KNOCKBACK_DIST / GameBalance.KNOCKBACK_TIME)
		move_and_slide()
		return

	if is_garrisoned:
		velocity = Vector3.ZERO
		return
	if not _is_moving or not squad_data:
		velocity = Vector3.ZERO
		return

	if _is_flying or _is_aquatic:
		var dir := _destination - global_position
		dir.y = 0.0
		if dir.length() < 0.3:
			_stop_moving()
			return
		velocity = dir.normalized() * squad_data.move_speed
	else:
		if _is_on_impassable_terrain():
			# Off the navmesh — move directly toward destination to escape
			var dir := _destination - global_position
			dir.y = 0.0
			if dir.length() < 0.3:
				_stop_moving()
				return
			velocity = dir.normalized() * maxf(squad_data.move_speed, 1.5)
		elif _nav_agent.is_navigation_finished():
			_stop_moving()
			return
		else:
			var next_pos := _nav_agent.get_next_path_position()
			var dir := next_pos - global_position
			dir.y = 0.0
			if dir.length() > 0.05:
				velocity = dir.normalized() * squad_data.move_speed
			else:
				velocity = Vector3.ZERO

	# Remember which way we're heading — the only record of movement direction, used to aim the
	# loser's knockback away from the winner's line of advance.
	if velocity.length() > 0.05:
		_last_heading = Vector3(velocity.x, 0.0, velocity.z).normalized()

	move_and_slide()
	_update_terrain_speed()

	# Stuck detection. A squad stops making progress for one of two reasons:
	#   (1) it's pressed up against a hostile body — most importantly a town's garrison,
	#       which sits on the objective. This MUST become a battle; relying on the
	#       DetectionArea's area_entered alone proved unreliable (a body-block after the
	#       areas were already overlapping fires no fresh enter event), so a parked squad
	#       could sit on an enemy HQ forever without fighting.
	#   (2) a transient nav/terrain hitch on a long open path (common on big 48x48 maps).
	#       The old code treated this as an "arrival" and halted the squad in open country,
	#       far short of its objective, so it never reached anything to fight or capture.
	# So: if a hostile is blocking, force the engagement. Otherwise re-path and keep
	# pushing, only finally stopping (→ squad_arrived → capture/garrison logic) once we've
	# exhausted retries or are genuinely at the destination.
	if global_position.distance_to(_last_progress_pos) > 0.06:
		_last_progress_pos = global_position
		_stuck_time = 0.0
		_repath_tries = 0
	else:
		_stuck_time += delta
		if _stuck_time > STUCK_STOP_TIME:
			_stuck_time = 0.0
			var foe := _blocking_hostile()
			if foe:
				squad_collided_with_enemy.emit(self, foe)
				_stop_moving()
			elif global_position.distance_to(_destination) <= ARRIVAL_RADIUS \
					or _repath_tries >= MAX_REPATH_TRIES:
				_repath_tries = 0
				_stop_moving()
			else:
				_repath_tries += 1
				if not _is_flying and not _is_aquatic and _nav_agent:
					_nav_agent.target_position = _destination

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
	_last_progress_pos = global_position
	_stuck_time = 0.0
	_repath_tries = 0
	if not _is_flying and not _is_aquatic and _nav_agent:
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

func is_moving() -> bool:
	return _is_moving

func get_destination() -> Vector3:
	return _destination

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

# Nearest hostile squad physically blocking us (within BLOCK_RANGE), if any — used by
# stuck detection to force a battle when wedged against an enemy (e.g. a town garrison).
func _blocking_hostile() -> Squad:
	if in_battle or is_invulnerable():
		return null
	var best: Squad = null
	var best_d := BLOCK_RANGE * BLOCK_RANGE
	for f in GameState.active_factions:
		if not GameState.are_hostile(faction, f):
			continue
		for sq in GameState.get_squads_by_faction(f):
			if not is_instance_valid(sq) or sq.in_battle or sq.is_invulnerable():
				continue
			var d := global_position.distance_squared_to(sq.global_position)
			if d < best_d:
				best_d = d
				best = sq
	return best

# True during the brief post-battle window in which this squad cannot be drawn into a new battle.
func is_invulnerable() -> bool:
	return _invuln_time > 0.0

# Apply post-battle recoil. Both participants call this; the loser passes a non-zero direction to be
# slid away from the winner's advance, the winner passes Vector3.ZERO (invulnerability only).
func apply_battle_recoil(knockback_dir: Vector3) -> void:
	_invuln_time = GameBalance.BATTLE_INVULN_TIME
	# A garrisoned squad (player healing in a town) stays anchored to its tile — invuln only, no slide.
	if knockback_dir != Vector3.ZERO and not is_garrisoned:
		_knockback_dir = knockback_dir.normalized()
		_knockback_time = GameBalance.KNOCKBACK_TIME
		_is_moving = false   # drop the prior move order so it doesn't reassert mid-slide

func _is_on_impassable_terrain() -> bool:
	if not map_manager or not squad_data:
		return false
	var grid := map_manager.world_to_grid(global_position)
	var terrain := map_manager.get_terrain(grid.x, grid.y)
	return TerrainDefs.get_speed(squad_data.get_movement_type(), terrain) == 0.0

func _update_terrain_speed() -> void:
	if not squad_data or not map_manager:
		return
	var grid := map_manager.world_to_grid(global_position)
	var terrain := map_manager.get_terrain(grid.x, grid.y)
	var mult := TerrainDefs.get_speed(squad_data.get_movement_type(), terrain)
	if mult > 0.0:
		squad_data.recalculate_speed(terrain)

func _faction_color(f: int) -> Color:
	return TerrainDefs.FACTION_COLORS.get(f, Color.WHITE)

func _on_area_entered(area: Area3D) -> void:
	if in_battle or is_invulnerable():
		return
	var other := area.get_parent() as Squad
	if other and GameState.are_hostile(faction, other.faction) \
			and not other.in_battle and not other.is_invulnerable():
		squad_collided_with_enemy.emit(self, other)
