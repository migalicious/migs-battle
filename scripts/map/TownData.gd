class_name TownData
extends Resource

@export var town_id: String = ""
@export var display_name: String = ""
@export var town_type: TerrainDefs.TownType = TerrainDefs.TownType.TOWN
@export var starting_faction: int = -1   # -1 = neutral, 0 = player, 1 = enemy
@export var is_deploy_point: bool = true
@export var capture_turns: int = 3

@export var grid_x: int = 0
@export var grid_z: int = 0

@export var income: int = 0
@export var has_aquatic_recruit: bool = false
