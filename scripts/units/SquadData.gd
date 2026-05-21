class_name SquadData
extends Resource

@export var squad_id: String = ""
@export var faction: int = 0
@export var units: Array[UnitData] = []

var move_speed: float = 0.0

func get_unit_at(row: int, col: int) -> UnitData:
	for u in units:
		if u.row == row and u.col == col:
			return u
	return null

func get_leader() -> UnitData:
	for u in units:
		if u.is_leader:
			return u
	return units[0] if units.size() > 0 else null

func get_alive_units() -> Array[UnitData]:
	var result: Array[UnitData] = []
	for u in units:
		if u.is_alive:
			result.append(u)
	return result

func get_movement_type() -> TerrainDefs.MovementType:
	var leader := get_leader()
	if not leader:
		return TerrainDefs.MovementType.INFANTRY
	var cls: ClassDefinition = UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
	return cls.movement_type if cls else TerrainDefs.MovementType.INFANTRY

func recalculate_speed(terrain: TerrainDefs.TerrainType) -> void:
	var leader := get_leader()
	if not leader:
		move_speed = 0.0
		return
	var leader_cls: ClassDefinition = UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
	if not leader_cls:
		move_speed = 0.0
		return

	var mv_type := leader_cls.movement_type
	var multiplier := TerrainDefs.get_speed(mv_type, terrain)
	if multiplier == 0.0:
		move_speed = 0.0
		return

	var min_base := INF
	for u in get_alive_units():
		var cls: ClassDefinition = UnitRegistry.get_class_def(u.class_id) as ClassDefinition
		if cls:
			min_base = min(min_base, cls.base_move_speed)
	move_speed = (min_base * multiplier) if min_base != INF else 0.0
