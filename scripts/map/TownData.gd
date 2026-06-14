class_name TownData
extends Resource

@export var town_id: String = ""
@export var display_name: String = ""
@export var town_type: TerrainDefs.TownType = TerrainDefs.TownType.TOWN
@export var starting_faction: int = -1   # -1 = neutral, 0 = player, 1 = enemy
@export var capture_turns: int = 3

@export var grid_x: int = 0
@export var grid_z: int = 0

@export var income: int = 0
@export var has_aquatic_recruit: bool = false

# Town liberation reward (granted once when the PLAYER captures a non-stronghold town).
@export var liberation_gold: int = 0
@export var liberation_unit: Dictionary = {}   # {class_id, level, is_hero} or empty
var liberation_claimed: bool = false

# Strongholds (HQ + CASTLE) are deploy-capable; plain towns are not. all_strongholds
# win condition counts strongholds only; towns are optional liberate-for-reward objectives.
func is_stronghold() -> bool:
	return town_type == TerrainDefs.TownType.HQ or town_type == TerrainDefs.TownType.CASTLE
