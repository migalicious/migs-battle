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
@export var num_castles: int = 2   # includes the HQs
@export var active_factions: Array[int] = [0, 1]
