extends Node

const _ItemDef = preload("res://scripts/items/ItemDefinition.gd")

var _items: Dictionary = {}

func _ready() -> void:
	_build_default_items()

func get_item(item_id: String):
	return _items.get(item_id, null)

func get_all_items() -> Array:
	return _items.values()

func _build_default_items() -> void:
	_reg("iron_shield",  "Iron Shield",   "Boosts defense.",          80,  0, 0, 0, 3, 0, 0, 0, 0.0)
	_reg("power_ring",   "Power Ring",    "Boosts strength.",        100,  0, 0, 4, 0, 0, 0, 0, 0.0)
	_reg("silver_mail",  "Silver Mail",   "Heavy armor.",            120,  0, 0, 0, 5, 2, 0, 0, 0.0)
	_reg("mage_robe",    "Mage Robe",     "Arcane vestment.",        110,  0, 0, 0, 0, 5, 0, 2, 0.0)
	_reg("speed_boots",  "Speed Boots",   "Increases agility.",       90,  0, 0, 0, 0, 0, 3, 0, 0.0)
	_reg("healing_herb", "Healing Herb",  "Heals 30% HP at battle.", 60,  1, 0, 0, 0, 0, 0, 0, 0.3)
	_reg("elixir",       "Elixir",        "Fully restores HP.",      150,  1, 0, 0, 0, 0, 0, 0, 1.0)

func _reg(id: String, dname: String, desc: String, cost: int,
		itype: int,
		hp: int, str_b: int, def_b: int, res_b: int, agi_b: int, int_b: int,
		heal: float) -> void:
	var item = _ItemDef.new()
	item.item_id = id; item.display_name = dname; item.description = desc
	item.cost = cost; item.item_type = itype
	item.hp_bonus = hp; item.str_bonus = str_b; item.def_bonus = def_b
	item.res_bonus = res_b; item.agi_bonus = agi_b; item.int_bonus = int_b
	item.heal_percent = heal
	_items[id] = item
