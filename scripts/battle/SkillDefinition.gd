class_name SkillDefinition
extends Resource

@export var skill_id: String = ""
@export var display_name: String = ""
@export var description: String = ""

enum SkillCondition {
	ALWAYS,
	HP_BELOW_50,
	HP_ABOVE_75,
	FIRST_ROUND,
	LAST_ROUND,
	ALLY_DEAD,
	ENEMY_FRONT_EMPTY,
}

enum SkillEffect {
	BONUS_DAMAGE,
	DAMAGE_MULTIPLIER,
	HEAL_SELF,
	HEAL_ALLY,
	GUARD,
	EXTRA_ATTACK,
}

@export var condition: SkillCondition = SkillCondition.ALWAYS
@export var effect: SkillEffect = SkillEffect.BONUS_DAMAGE
@export var power: float = 1.0
@export var heal_percent: float = 0.0
@export var damage_reduction: float = 0.0
