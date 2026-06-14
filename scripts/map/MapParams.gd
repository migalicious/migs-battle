class_name MapParams
extends Resource

@export var width: int = 32
@export var height: int = 32
@export var cell_size: float = 2.0
@export var map_seed: int = 0

@export var water_threshold: float = 0.30
@export var mountain_threshold: float = 0.72
@export var forest_coverage: float = 0.20

@export var num_towns: int = 6
@export var num_castles: int = 2   # legacy total; superseded by castles_per_faction
@export var castles_per_faction: int = 1   # secondary deploy-strongholds each faction owns at spawn
@export var active_factions: Array[int] = [0, 1]

# Default town-liberation reward (granted when the player captures a non-stronghold town).
@export var town_liberation_gold: int = 0
@export var town_liberation_unit: Dictionary = {}   # {class_id, level, is_hero} or empty
