class_name ItemDefinition
extends Resource

@export var item_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var cost: int = 0

enum ItemType { PASSIVE, CONSUMABLE }
@export var item_type: ItemType = ItemType.PASSIVE

@export var hp_bonus: int = 0
@export var str_bonus: int = 0
@export var def_bonus: int = 0
@export var res_bonus: int = 0
@export var agi_bonus: int = 0
@export var int_bonus: int = 0

@export var heal_percent: float = 0.0
