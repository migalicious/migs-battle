class_name SquadData
extends Resource

@export var squad_id: String = ""
@export var faction: int = 0
@export var units: Array[UnitData] = []

# Derived at runtime — call recalculate_speed() after any unit change
var move_speed: float = 0.0
var movement_type: TerrainDefs.MovementType = TerrainDefs.MovementType.INFANTRY

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

func recalculate_speed(terrain: TerrainDefs.TerrainType) -> void:
	var leader := get_leader()
	if leader:
		var leader_cls: ClassDefinition = UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
		if leader_cls:
			movement_type = leader_cls.movement_type

	var min_speed := INF
	for u in get_alive_units():
		var cls: ClassDefinition = UnitRegistry.get_class_def(u.class_id) as ClassDefinition
		if cls:
			var spd := TerrainDefs.get_speed(cls.movement_type, terrain)
			min_speed = min(min_speed, spd)
	move_speed = min_speed if min_speed != INF else 0.0
