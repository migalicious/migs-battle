class_name ClassDefinition
extends Resource

@export var class_id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export var placeholder_color: Color = Color.WHITE

# Base stats at level 1
@export var base_hp: int = 20
@export var base_strength: int = 5
@export var base_agility: int = 5
@export var base_intelligence: int = 5
@export var base_defense: int = 5
@export var base_resistance: int = 5

# Stat growth per level (flat range: randi_range(min, max))
@export var hp_growth: Vector2i = Vector2i(3, 5)
@export var str_growth: Vector2i = Vector2i(1, 3)
@export var agi_growth: Vector2i = Vector2i(1, 3)
@export var int_growth: Vector2i = Vector2i(1, 2)
@export var def_growth: Vector2i = Vector2i(1, 3)
@export var res_growth: Vector2i = Vector2i(1, 2)

@export var movement_type: TerrainDefs.MovementType = TerrainDefs.MovementType.INFANTRY
@export var base_move_speed: float = 3.0
@export var can_lead: bool = false
@export var deploy_cost: int = 0

@export var front_attacks: Array[AttackDefinition] = []
@export var back_attacks: Array[AttackDefinition] = []
@export var skills: Array = []
@export var promotions: Array[PromotionRequirement] = []

func apply_stat_growth(unit: UnitData) -> void:
	unit.max_hp += randi_range(hp_growth.x, hp_growth.y)
	unit.strength += randi_range(str_growth.x, str_growth.y)
	unit.agility += randi_range(agi_growth.x, agi_growth.y)
	unit.intelligence += randi_range(int_growth.x, int_growth.y)
	unit.defense += randi_range(def_growth.x, def_growth.y)
	unit.resistance += randi_range(res_growth.x, res_growth.y)
	if unit.is_hero:
		# Heroes gain a small extra amount each level, pulling further ahead over time.
		unit.max_hp += 2
		unit.strength += 1
		unit.agility += 1
		unit.intelligence += 1
		unit.defense += 1
		unit.resistance += 1
	unit.hp = unit.max_hp
