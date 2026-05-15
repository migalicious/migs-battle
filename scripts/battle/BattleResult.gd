class_name BattleResult
extends Resource

@export var attacker_squad_id: String = ""
@export var defender_squad_id: String = ""

@export var attacker_unit_states: Array[UnitData] = []
@export var defender_unit_states: Array[UnitData] = []

@export var attacker_xp: int = 0
@export var defender_xp: int = 0

@export var attacker_wiped: bool = false
@export var defender_wiped: bool = false

@export var action_log: Array[BattleAction] = []
