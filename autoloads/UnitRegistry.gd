extends Node

var _classes: Dictionary = {}

func _ready() -> void:
	_load_or_build_classes()

func _load_or_build_classes() -> void:
	var dir := DirAccess.open("res://data/classes/")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var res := ResourceLoader.load("res://data/classes/" + fname)
				var cls := res as ClassDefinition
				if cls and cls.class_id != "":
					_classes[cls.class_id] = cls
			fname = dir.get_next()
		dir.list_dir_end()

	if _classes.is_empty():
		_build_default_classes()
		_save_classes()

func get_class_def(class_id: String) -> ClassDefinition:
	return _classes.get(class_id, null) as ClassDefinition

func create_unit(class_id: String, level: int) -> UnitData:
	var cls := get_class_def(class_id)
	if not cls:
		push_error("UnitRegistry: unknown class_id '%s'" % class_id)
		return null

	var unit := UnitData.new()
	unit.class_id  = class_id
	unit.level     = 1
	unit.max_hp    = cls.base_hp
	unit.hp        = cls.base_hp
	unit.strength  = cls.base_strength
	unit.agility   = cls.base_agility
	unit.intelligence = cls.base_intelligence
	unit.defense   = cls.base_defense
	unit.resistance = cls.base_resistance
	unit.xp        = 0
	unit.xp_to_next = 100
	unit.is_alive  = true
	unit.class_def = cls

	for i in range(level - 1):
		unit.level += 1
		unit.xp_to_next = 100 * unit.level
		cls.apply_stat_growth(unit)

	return unit

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _atk(aname: String, dtype: TerrainDefs.DamageType, hits: int,
		power: float, trow: TerrainDefs.TargetRow,
		all_col := false, all_row := false) -> AttackDefinition:
	var a := AttackDefinition.new()
	a.attack_name = aname
	a.damage_type = dtype
	a.hits = hits
	a.power_multiplier = power
	a.targets_row = trow
	a.hits_all_in_column = all_col
	a.hits_all_in_row = all_row
	return a

func _promo(target: String, req_level: int) -> PromotionRequirement:
	var p := PromotionRequirement.new()
	p.target_class_id = target
	p.required_level  = req_level
	return p

func _reg(cls: ClassDefinition) -> void:
	_classes[cls.class_id] = cls

func _build_default_classes() -> void:
	var P := TerrainDefs.DamageType.PHYSICAL
	var FIRE := TerrainDefs.DamageType.FIRE
	var COLD := TerrainDefs.DamageType.COLD
	var HOLY := TerrainDefs.DamageType.HOLY
	var DARK := TerrainDefs.DamageType.DARK
	var FR := TerrainDefs.TargetRow.FRONT
	var BK := TerrainDefs.TargetRow.BACK
	var ANY := TerrainDefs.TargetRow.ANY
	var INF := TerrainDefs.MovementType.INFANTRY
	var CAV := TerrainDefs.MovementType.CAVALRY
	var FLY := TerrainDefs.MovementType.FLYING

	# --- Fighter ---
	var fighter := ClassDefinition.new()
	fighter.class_id = "fighter"; fighter.display_name = "Fighter"
	fighter.placeholder_color = Color(0.47, 0.53, 0.60)
	fighter.base_hp = 22; fighter.base_strength = 7; fighter.base_agility = 6
	fighter.base_intelligence = 3; fighter.base_defense = 6; fighter.base_resistance = 3
	fighter.hp_growth = Vector2i(4,6); fighter.str_growth = Vector2i(2,4)
	fighter.agi_growth = Vector2i(2,3); fighter.int_growth = Vector2i(1,2)
	fighter.def_growth = Vector2i(2,3); fighter.res_growth = Vector2i(1,2)
	fighter.movement_type = INF; fighter.base_move_speed = 3.0; fighter.can_lead = false
	fighter.front_attacks = [_atk("Slash", P, 2, 1.0, FR)]
	fighter.back_attacks  = [_atk("Slash", P, 1, 0.8, FR)]
	fighter.promotions    = [_promo("knight",4), _promo("archer",4), _promo("mage",4)]
	_reg(fighter)

	# --- Knight ---
	var knight := ClassDefinition.new()
	knight.class_id = "knight"; knight.display_name = "Knight"
	knight.placeholder_color = Color(1.0, 0.84, 0.0)
	knight.base_hp = 28; knight.base_strength = 8; knight.base_agility = 5
	knight.base_intelligence = 3; knight.base_defense = 9; knight.base_resistance = 4
	knight.hp_growth = Vector2i(5,7); knight.str_growth = Vector2i(3,5)
	knight.agi_growth = Vector2i(1,3); knight.int_growth = Vector2i(1,2)
	knight.def_growth = Vector2i(3,4); knight.res_growth = Vector2i(1,2)
	knight.movement_type = INF; knight.base_move_speed = 3.0; knight.can_lead = true
	knight.front_attacks = [_atk("Slash", P, 2, 1.1, FR)]
	knight.back_attacks  = [_atk("Slash", P, 1, 0.9, FR)]
	knight.promotions    = [_promo("paladin",15), _promo("cavalry",8), _promo("gryphon_rider",10)]
	_reg(knight)

	# --- Paladin ---
	var paladin := ClassDefinition.new()
	paladin.class_id = "paladin"; paladin.display_name = "Paladin"
	paladin.placeholder_color = Color(1.0, 1.0, 1.0)
	paladin.base_hp = 35; paladin.base_strength = 10; paladin.base_agility = 6
	paladin.base_intelligence = 5; paladin.base_defense = 12; paladin.base_resistance = 7
	paladin.hp_growth = Vector2i(6,8); paladin.str_growth = Vector2i(3,5)
	paladin.agi_growth = Vector2i(2,3); paladin.int_growth = Vector2i(2,3)
	paladin.def_growth = Vector2i(3,5); paladin.res_growth = Vector2i(2,3)
	paladin.movement_type = INF; paladin.base_move_speed = 3.0; paladin.can_lead = true
	paladin.front_attacks = [_atk("Slash", P, 3, 1.2, FR)]
	paladin.back_attacks  = [_atk("Holy Light", HOLY, 1, 1.0, ANY)]
	paladin.promotions    = []
	_reg(paladin)

	# --- Archer ---
	var archer := ClassDefinition.new()
	archer.class_id = "archer"; archer.display_name = "Archer"
	archer.placeholder_color = Color(0.55, 0.35, 0.20)
	archer.base_hp = 20; archer.base_strength = 6; archer.base_agility = 8
	archer.base_intelligence = 4; archer.base_defense = 5; archer.base_resistance = 5
	archer.hp_growth = Vector2i(3,5); archer.str_growth = Vector2i(2,3)
	archer.agi_growth = Vector2i(3,4); archer.int_growth = Vector2i(1,2)
	archer.def_growth = Vector2i(1,2); archer.res_growth = Vector2i(2,3)
	archer.movement_type = INF; archer.base_move_speed = 3.0; archer.can_lead = true
	archer.front_attacks = [_atk("Shot", P, 2, 0.9, FR)]
	archer.back_attacks  = [_atk("Shot", P, 2, 1.0, BK)]
	archer.promotions    = []
	_reg(archer)

	# --- Mage ---
	var mage := ClassDefinition.new()
	mage.class_id = "mage"; mage.display_name = "Mage"
	mage.placeholder_color = Color(0.60, 0.20, 0.80)
	mage.base_hp = 16; mage.base_strength = 3; mage.base_agility = 5
	mage.base_intelligence = 9; mage.base_defense = 3; mage.base_resistance = 8
	mage.hp_growth = Vector2i(2,4); mage.str_growth = Vector2i(1,2)
	mage.agi_growth = Vector2i(1,2); mage.int_growth = Vector2i(4,6)
	mage.def_growth = Vector2i(1,2); mage.res_growth = Vector2i(3,4)
	mage.movement_type = INF; mage.base_move_speed = 3.0; mage.can_lead = true
	mage.front_attacks = [_atk("Staff", P, 1, 0.6, FR)]
	mage.back_attacks  = [_atk("Magic", FIRE, 2, 1.2, FR)]
	mage.promotions    = [_promo("sorcerer", 12)]
	_reg(mage)

	# --- Sorcerer ---
	var sorcerer := ClassDefinition.new()
	sorcerer.class_id = "sorcerer"; sorcerer.display_name = "Sorcerer"
	sorcerer.placeholder_color = Color(0.35, 0.10, 0.50)
	sorcerer.base_hp = 20; sorcerer.base_strength = 4; sorcerer.base_agility = 5
	sorcerer.base_intelligence = 13; sorcerer.base_defense = 4; sorcerer.base_resistance = 12
	sorcerer.hp_growth = Vector2i(3,5); sorcerer.str_growth = Vector2i(1,2)
	sorcerer.agi_growth = Vector2i(1,2); sorcerer.int_growth = Vector2i(5,7)
	sorcerer.def_growth = Vector2i(1,2); sorcerer.res_growth = Vector2i(4,5)
	sorcerer.movement_type = INF; sorcerer.base_move_speed = 3.0; sorcerer.can_lead = true
	sorcerer.front_attacks = [_atk("Staff", P, 1, 0.6, FR)]
	sorcerer.back_attacks  = [_atk("Arcane Blast", DARK, 2, 1.5, FR, true)]
	sorcerer.promotions    = []
	_reg(sorcerer)

	# --- Cavalry ---
	var cavalry := ClassDefinition.new()
	cavalry.class_id = "cavalry"; cavalry.display_name = "Cavalry"
	cavalry.placeholder_color = Color(0.82, 0.72, 0.55)
	cavalry.base_hp = 32; cavalry.base_strength = 9; cavalry.base_agility = 9
	cavalry.base_intelligence = 3; cavalry.base_defense = 8; cavalry.base_resistance = 4
	cavalry.hp_growth = Vector2i(5,7); cavalry.str_growth = Vector2i(3,4)
	cavalry.agi_growth = Vector2i(3,5); cavalry.int_growth = Vector2i(1,2)
	cavalry.def_growth = Vector2i(2,3); cavalry.res_growth = Vector2i(1,2)
	cavalry.movement_type = CAV; cavalry.base_move_speed = 4.5; cavalry.can_lead = true
	cavalry.front_attacks = [_atk("Lance Charge", P, 2, 1.3, FR)]
	cavalry.back_attacks  = [_atk("Slash", P, 1, 0.8, FR)]
	cavalry.promotions    = []
	_reg(cavalry)

	# --- Gryphon Rider ---
	var gryphon := ClassDefinition.new()
	gryphon.class_id = "gryphon_rider"; gryphon.display_name = "Gryphon Rider"
	gryphon.placeholder_color = Color(0.53, 0.81, 0.98)
	gryphon.base_hp = 26; gryphon.base_strength = 8; gryphon.base_agility = 10
	gryphon.base_intelligence = 4; gryphon.base_defense = 6; gryphon.base_resistance = 6
	gryphon.hp_growth = Vector2i(4,6); gryphon.str_growth = Vector2i(2,4)
	gryphon.agi_growth = Vector2i(3,5); gryphon.int_growth = Vector2i(1,3)
	gryphon.def_growth = Vector2i(2,3); gryphon.res_growth = Vector2i(2,3)
	gryphon.movement_type = FLY; gryphon.base_move_speed = 2.8; gryphon.can_lead = true
	gryphon.front_attacks = [_atk("Talon", P, 2, 1.0, FR)]
	gryphon.back_attacks  = [_atk("Wind Blade", COLD, 1, 1.1, ANY)]
	gryphon.promotions    = []
	_reg(gryphon)

func _save_classes() -> void:
	for class_id: String in _classes:
		var path := "res://data/classes/%s.tres" % class_id
		var result := ResourceSaver.save(_classes[class_id], path)
		if result != OK:
			push_warning("UnitRegistry: failed to save %s (error %d)" % [path, result])
