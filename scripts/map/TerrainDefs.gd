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

# Speed multiplier for (MovementType, TerrainType). Multiply against unit's base_move_speed.
# 0.0 = impassable — squad cannot enter, navmesh excludes this terrain.
const SPEED_TABLE: Dictionary = {
	MovementType.INFANTRY: {
		TerrainType.PLAINS:   1.0,
		TerrainType.GRASS:    0.9,
		TerrainType.FOREST:   0.6,
		TerrainType.MOUNTAIN: 0.3,
		TerrainType.WATER:    0.0,
		TerrainType.ROAD:     1.3,
	},
	MovementType.CAVALRY: {
		TerrainType.PLAINS:   1.2,
		TerrainType.GRASS:    1.0,
		TerrainType.FOREST:   0.4,
		TerrainType.MOUNTAIN: 0.2,
		TerrainType.WATER:    0.0,
		TerrainType.ROAD:     1.5,
	},
	MovementType.FLYING: {
		TerrainType.PLAINS:   0.8,
		TerrainType.GRASS:    0.8,
		TerrainType.FOREST:   0.8,
		TerrainType.MOUNTAIN: 0.7,
		TerrainType.WATER:    0.7,
		TerrainType.ROAD:     0.8,
	},
	MovementType.AQUATIC: {
		TerrainType.PLAINS:   0.5,
		TerrainType.GRASS:    0.5,
		TerrainType.FOREST:   0.4,
		TerrainType.MOUNTAIN: 0.3,
		TerrainType.WATER:    1.2,
		TerrainType.ROAD:     0.5,
	},
}

# Returns the speed multiplier for the given movement and terrain combination.
static func get_speed(movement_type: MovementType, terrain: TerrainType) -> float:
	return SPEED_TABLE[movement_type][terrain]

# Per-terrain visual data: [box_height, center_y, navmesh_top_y]
const TERRAIN_VISUAL: Dictionary = {
	TerrainType.WATER:    [0.1,  -0.05, 0.0],
	TerrainType.PLAINS:   [0.2,  0.0,   0.1],
	TerrainType.GRASS:    [0.2,  0.0,   0.1],
	TerrainType.FOREST:   [0.5,  0.15,  0.4],
	TerrainType.MOUNTAIN: [1.2,  0.5,   1.1],
	TerrainType.ROAD:     [0.25, 0.025, 0.15],
}

static func get_box_height(terrain: TerrainType) -> float:
	return TERRAIN_VISUAL[terrain][0]

static func get_center_y(terrain: TerrainType) -> float:
	return TERRAIN_VISUAL[terrain][1]

static func get_top_y(terrain: TerrainType) -> float:
	return TERRAIN_VISUAL[terrain][2]
