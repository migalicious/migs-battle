class_name LevelSystem

static func try_level_up(unit: UnitData) -> bool:
	if unit.xp >= unit.xp_to_next:
		unit.xp -= unit.xp_to_next
		unit.level += 1
		unit.xp_to_next = 100 * unit.level
		apply_stat_growth(unit)
		return true
	return false

static func apply_stat_growth(unit: UnitData) -> void:
	var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id) as ClassDefinition
	if cls:
		cls.apply_stat_growth(unit)

static func check_promotion(unit: UnitData) -> String:
	var cls: ClassDefinition = UnitRegistry.get_class_def(unit.class_id) as ClassDefinition
	if not cls:
		return ""
	for promo in cls.promotions:
		if unit.level >= promo.required_level:
			return promo.target_class_id
	return ""

static func apply_promotion(unit: UnitData, new_class_id: String) -> void:
	var new_cls: ClassDefinition = UnitRegistry.get_class_def(new_class_id) as ClassDefinition
	if not new_cls:
		push_error("Unknown promotion target: " + new_class_id)
		return
	unit.class_id = new_class_id
	unit.class_def = new_cls
	# Stats never decrease on promotion
	unit.max_hp = max(unit.max_hp, new_cls.base_hp)
	unit.hp = unit.max_hp
	unit.strength = max(unit.strength, new_cls.base_strength)
	unit.agility = max(unit.agility, new_cls.base_agility)
	unit.intelligence = max(unit.intelligence, new_cls.base_intelligence)
	unit.defense = max(unit.defense, new_cls.base_defense)
	unit.resistance = max(unit.resistance, new_cls.base_resistance)
