class_name UnitData
extends Resource

# Identity
@export var unit_name: String = ""
@export var class_id: String = ""
@export var faction: int = 0

# Grid position within squad (set by SquadData)
@export var row: int = 0   # 0 = front, 1 = back
@export var col: int = 0   # 0, 1, 2

# Current stats
@export var hp: int = 0
@export var max_hp: int = 0
@export var strength: int = 0
@export var agility: int = 0
@export var intelligence: int = 0
@export var defense: int = 0
@export var resistance: int = 0

# Progression
@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next: int = 100

# State flags
@export var is_alive: bool = true
@export var is_leader: bool = false
@export var is_hero: bool = false   # named, stat-boosted unit meant to lead a squad
@export var is_wounded: bool = false
@export var held_item: String = ""

# Populated by UnitRegistry after creation; not serialized
var class_def: ClassDefinition
