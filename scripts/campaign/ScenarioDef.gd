class_name ScenarioDef
extends Resource

@export var scenario_idx: int = 0
@export var scenario_name: String = ""
@export var description: String = ""
@export var map_seed: int = 0
@export var map_width: int = 32
@export var map_height: int = 32
@export var num_towns: int = 6
@export var num_castles: int = 2   # legacy; superseded by castles_per_faction
@export var castles_per_faction: int = 1   # legacy fallback; difficulty config drives this now
@export var difficulty: DifficultyConfig = null   # per-scenario enemy tuning (null => default preset)
@export var active_factions: Array[int] = [0, 1]

# Default reward when the player liberates (captures) a non-stronghold town: a gold
# bounty + a base-stat filler unit (coastal towns override with a merfolk in MapManager).
@export var town_liberation_gold: int = 75
@export var town_liberation_unit: Dictionary = {"class_id": "fighter", "level": 3, "unit_name": "Townsguard"}
@export var faction_preset: String = "hostile_all"
@export var win_conditions: Array[String] = ["hq_capture"]
@export var special_objectives: Array[String] = []
@export var starting_gold: int = 100
@export var reward_units: Array = []  # Array of {class_id, unit_name, level}
@export var enemy_difficulty_mult: float = 1.0
