class_name TerrainDefs

enum TerrainType {
	PLAINS,
	GRASS,
	FOREST,
	MOUNTAIN,
	WATER,
	ROAD
}

enum MovementType {
	INFANTRY,
	CAVALRY,
	FLYING,
	AQUATIC
}

enum DamageType {
	PHYSICAL,
	FIRE,
	COLD,
	THUNDER,
	HOLY,
	DARK
}

enum TownType {
	TOWN,
	CASTLE,
	HQ
}

enum Faction {
	NEUTRAL = -1,
	PLAYER = 0,
	ENEMY = 1
}

enum TargetRow {
	FRONT,
	BACK,
	ANY
}

# Speed in world-units/second for each (MovementType, TerrainType) pair.
# FLYING ignores terrain and always uses its base speed (handled in Squad.gd).
const SPEED_TABLE: Dictionary = {
	MovementType.INFANTRY: {
		TerrainType.PLAINS:   3.0,
		TerrainType.GRASS:    2.5,
		TerrainType.FOREST:   1.5,
		TerrainType.MOUNTAIN: 1.0,
		TerrainType.WATER:    0.5,
		TerrainType.ROAD:     4.0,
	},
	MovementType.CAVALRY: {
		TerrainType.PLAINS:   5.0,
		TerrainType.GRASS:    4.0,
		TerrainType.FOREST:   2.0,
		TerrainType.MOUNTAIN: 1.5,
		TerrainType.WATER:    0.5,
		TerrainType.ROAD:     6.0,
	},
	MovementType.FLYING: {
		TerrainType.PLAINS:   4.0,
		TerrainType.GRASS:    4.0,
		TerrainType.FOREST:   4.0,
		TerrainType.MOUNTAIN: 4.0,
		TerrainType.WATER:    4.0,
		TerrainType.ROAD:     4.0,
	},
	MovementType.AQUATIC: {
		TerrainType.PLAINS:   0.5,
		TerrainType.GRASS:    0.5,
		TerrainType.FOREST:   0.5,
		TerrainType.MOUNTAIN: 0.5,
		TerrainType.WATER:    4.0,
		TerrainType.ROAD:     0.5,
	},
}

static func get_speed(movement_type: MovementType, terrain: TerrainType) -> float:
	return SPEED_TABLE[movement_type][terrain]
