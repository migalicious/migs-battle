class_name BattleAction
extends Resource

enum ActionType { ATTACK, HEAL, SKILL, MISS, KILL }

@export var action_type: ActionType = ActionType.ATTACK
@export var actor_unit_id: String = ""
@export var target_unit_id: String = ""
@export var damage_dealt: int = 0
@export var attack_name: String = ""
