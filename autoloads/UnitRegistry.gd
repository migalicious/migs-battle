extends Node

const _SkillDef = preload("res://scripts/battle/SkillDefinition.gd")

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

func _skill(sid: String, dname: String, desc: String, cond: int, eff: int,
		power: float = 1.0, heal: float = 0.0, dmg_red: float = 0.0,
		stat_tgt: String = "", stat_amt: int = 0) -> Resource:
	var s := _SkillDef.new()
	s.skill_id = sid; s.display_name = dname; s.description = desc
	s.condition = cond as _SkillDef.SkillCondition; s.effect = eff as _SkillDef.SkillEffect
	s.power = power; s.heal_percent = heal; s.damage_reduction = dmg_red
	s.stat_target = stat_tgt; s.stat_amount = stat_amt
	return s

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

func _atk_heal(aname: String, dtype: TerrainDefs.DamageType, power: float) -> AttackDefinition:
	var a := _atk(aname, dtype, 1, power, TerrainDefs.TargetRow.ANY)
	a.is_heal = true
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
	fighter.movement_type = INF; fighter.base_move_speed = 3.0; fighter.can_lead = false; fighter.deploy_cost = 50
	fighter.front_attacks = [_atk("Slash", P, 2, 1.0, FR)]
	fighter.back_attacks  = [_atk("Slash", P, 1, 0.8, FR)]
	fighter.skills        = [_skill("grit", "Grit", "When wounded, reduces incoming damage.", 1, 4, 1.0, 0.0, 0.2)]
	fighter.promotions    = [_promo("knight",5), _promo("archer",4), _promo("mage",4), _promo("warrior",6), _promo("witch",4)]
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
	knight.movement_type = INF; knight.base_move_speed = 3.0; knight.can_lead = true; knight.deploy_cost = 80
	knight.front_attacks = [_atk("Slash", P, 2, 1.1, FR)]
	knight.back_attacks  = [_atk("Slash", P, 1, 0.9, FR)]
	knight.skills        = [_skill("shield_bash", "Shield Bash", "Bonus hit on the first round.", 3, 0, 0.5)]
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
	paladin.movement_type = INF; paladin.base_move_speed = 3.0; paladin.can_lead = true; paladin.deploy_cost = 130
	paladin.front_attacks = [_atk("Slash", P, 3, 1.2, FR)]
	paladin.back_attacks  = [_atk("Holy Light", HOLY, 1, 1.0, ANY)]
	paladin.skills        = [_skill("holy_aura", "Holy Aura", "Heals lowest-HP ally each round.", 0, 3, 1.0, 0.10)]
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
	archer.movement_type = INF; archer.base_move_speed = 3.0; archer.can_lead = true; archer.deploy_cost = 60
	archer.front_attacks = [_atk("Shot", P, 2, 0.9, FR)]
	archer.back_attacks  = [_atk("Shot", P, 2, 1.0, BK)]
	archer.skills        = [_skill("eagle_eye", "Eagle Eye", "30% more damage when HP > 75%.", 2, 1, 1.3)]
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
	mage.movement_type = INF; mage.base_move_speed = 3.0; mage.can_lead = true; mage.deploy_cost = 70
	mage.front_attacks = [_atk("Staff", P, 1, 0.6, FR)]
	mage.back_attacks  = [_atk("Magic", FIRE, 2, 1.2, ANY)]
	mage.skills        = [_skill("mana_surge", "Mana Surge", "Extra magic attack on the final round.", 4, 5, 1.0)]
	mage.promotions    = [_promo("sorcerer", 12), _promo("cleric", 8)]
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
	sorcerer.movement_type = INF; sorcerer.base_move_speed = 3.0; sorcerer.can_lead = true; sorcerer.deploy_cost = 120
	sorcerer.front_attacks = [_atk("Staff", P, 1, 0.6, FR)]
	sorcerer.back_attacks  = [_atk("Arcane Blast", DARK, 2, 1.5, FR, true)]
	sorcerer.skills        = [_skill("drain_life", "Drain Life", "Restores 8% HP after each attack.", 0, 2, 1.0, 0.08)]
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
	cavalry.movement_type = CAV; cavalry.base_move_speed = 4.5; cavalry.can_lead = true; cavalry.deploy_cost = 100
	cavalry.front_attacks = [_atk("Lance Charge", P, 2, 1.3, FR)]
	cavalry.back_attacks  = [_atk("Slash", P, 1, 0.8, FR)]
	cavalry.skills        = [_skill("momentum", "Momentum", "50% more damage on the charge.", 3, 1, 1.5)]
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
	gryphon.movement_type = FLY; gryphon.base_move_speed = 2.8; gryphon.can_lead = true; gryphon.deploy_cost = 110
	gryphon.front_attacks = [_atk("Talon", P, 2, 1.0, FR)]
	gryphon.back_attacks  = [_atk("Wind Blade", COLD, 1, 1.1, ANY)]
	gryphon.skills        = [_skill("swoop", "Swoop", "Bonus strike when the enemy front row is gone.", 6, 0, 0.8)]
	gryphon.promotions    = []
	_reg(gryphon)

	# --- Cleric ---
	var cleric := ClassDefinition.new()
	cleric.class_id = "cleric"; cleric.display_name = "Cleric"
	cleric.placeholder_color = Color(1.0, 0.9, 0.6)
	cleric.base_hp = 18; cleric.base_strength = 3; cleric.base_agility = 5
	cleric.base_intelligence = 7; cleric.base_defense = 4; cleric.base_resistance = 10
	cleric.hp_growth = Vector2i(3,5); cleric.str_growth = Vector2i(1,2)
	cleric.agi_growth = Vector2i(1,2); cleric.int_growth = Vector2i(3,5)
	cleric.def_growth = Vector2i(1,2); cleric.res_growth = Vector2i(3,4)
	cleric.movement_type = INF; cleric.base_move_speed = 3.0; cleric.can_lead = true; cleric.deploy_cost = 75
	cleric.front_attacks = [_atk("Staff", P, 1, 0.5, FR)]
	cleric.back_attacks  = [_atk_heal("Heal", HOLY, 1.5)]
	cleric.skills        = [_skill("devoted", "Devoted", "Heals lowest-HP ally each round.", 0, 3, 1.0, 0.12)]
	cleric.promotions    = []
	_reg(cleric)

	# --- Warrior ---
	var warrior := ClassDefinition.new()
	warrior.class_id = "warrior"; warrior.display_name = "Warrior"
	warrior.placeholder_color = Color(0.7, 0.2, 0.15)
	warrior.base_hp = 30; warrior.base_strength = 10; warrior.base_agility = 7
	warrior.base_intelligence = 2; warrior.base_defense = 7; warrior.base_resistance = 3
	warrior.hp_growth = Vector2i(5,7); warrior.str_growth = Vector2i(3,5)
	warrior.agi_growth = Vector2i(2,3); warrior.int_growth = Vector2i(1,2)
	warrior.def_growth = Vector2i(2,4); warrior.res_growth = Vector2i(1,2)
	warrior.movement_type = INF; warrior.base_move_speed = 3.0; warrior.can_lead = true; warrior.deploy_cost = 90
	warrior.front_attacks = [_atk("Heavy Strike", P, 2, 1.4, FR)]
	warrior.back_attacks  = [_atk("Throw", P, 1, 0.9, ANY)]
	warrior.skills        = [_skill("berserk", "Berserk", "50% more damage when wounded.", 1, 1, 1.5)]
	warrior.promotions    = [_promo("berserker", 12)]
	_reg(warrior)

	# --- Berserker ---
	var berserker := ClassDefinition.new()
	berserker.class_id = "berserker"; berserker.display_name = "Berserker"
	berserker.placeholder_color = Color(0.9, 0.1, 0.1)
	berserker.base_hp = 40; berserker.base_strength = 14; berserker.base_agility = 9
	berserker.base_intelligence = 2; berserker.base_defense = 8; berserker.base_resistance = 3
	berserker.hp_growth = Vector2i(6,8); berserker.str_growth = Vector2i(4,6)
	berserker.agi_growth = Vector2i(2,4); berserker.int_growth = Vector2i(1,2)
	berserker.def_growth = Vector2i(2,3); berserker.res_growth = Vector2i(1,2)
	berserker.movement_type = INF; berserker.base_move_speed = 3.0; berserker.can_lead = true; berserker.deploy_cost = 140
	berserker.front_attacks = [_atk("Rampage", P, 2, 1.3, FR)]
	berserker.back_attacks  = [_atk("War Cry", P, 1, 1.0, FR, false, true)]
	berserker.skills        = [_skill("bloodlust", "Bloodlust", "Restores 5% HP after each attack.", 0, 2, 1.0, 0.05)]
	berserker.promotions    = []
	_reg(berserker)

	# --- Witch ---
	var witch := ClassDefinition.new()
	witch.class_id = "witch"; witch.display_name = "Witch"
	witch.placeholder_color = Color(0.5, 0.0, 0.6)
	witch.base_hp = 15; witch.base_strength = 3; witch.base_agility = 6
	witch.base_intelligence = 10; witch.base_defense = 3; witch.base_resistance = 9
	witch.hp_growth = Vector2i(2,4); witch.str_growth = Vector2i(1,2)
	witch.agi_growth = Vector2i(2,3); witch.int_growth = Vector2i(4,6)
	witch.def_growth = Vector2i(1,2); witch.res_growth = Vector2i(3,4)
	witch.movement_type = INF; witch.base_move_speed = 3.0; witch.can_lead = true; witch.deploy_cost = 70
	witch.front_attacks = [_atk("Hex", DARK, 1, 0.7, FR)]
	witch.back_attacks  = [_atk("Curse Bolt", DARK, 2, 1.1, ANY)]
	witch.skills        = [_skill("weaken", "Weaken", "Lowers enemy defense after each hit.", 0, 7, 1.0, 0.0, 0.0, "defense", -3)]
	witch.promotions    = [_promo("sorcerer", 12)]
	_reg(witch)

	# --- Merfolk ---
	var merfolk := ClassDefinition.new()
	merfolk.class_id = "merfolk"; merfolk.display_name = "Merfolk"
	merfolk.placeholder_color = Color(0.0, 0.7, 0.8)
	merfolk.base_hp = 24; merfolk.base_strength = 8; merfolk.base_agility = 8
	merfolk.base_intelligence = 5; merfolk.base_defense = 6; merfolk.base_resistance = 7
	merfolk.hp_growth = Vector2i(4,6); merfolk.str_growth = Vector2i(2,4)
	merfolk.agi_growth = Vector2i(2,4); merfolk.int_growth = Vector2i(1,3)
	merfolk.def_growth = Vector2i(2,3); merfolk.res_growth = Vector2i(2,3)
	merfolk.movement_type = TerrainDefs.MovementType.AQUATIC; merfolk.base_move_speed = 3.0; merfolk.can_lead = true; merfolk.deploy_cost = 95
	merfolk.front_attacks = [_atk("Trident", P, 2, 1.1, FR)]
	merfolk.back_attacks  = [_atk("Tidal Wave", COLD, 1, 1.0, FR, false, true)]
	merfolk.skills        = [_skill("tide_turn", "Tide Turn", "Bonus strike when the enemy front row is gone.", 6, 0, 0.7)]
	merfolk.promotions    = [_promo("sea_knight", 12)]
	_reg(merfolk)

	# --- Sea Knight ---
	var sea_knight := ClassDefinition.new()
	sea_knight.class_id = "sea_knight"; sea_knight.display_name = "Sea Knight"
	sea_knight.placeholder_color = Color(0.0, 0.45, 0.6)
	sea_knight.base_hp = 34; sea_knight.base_strength = 11; sea_knight.base_agility = 9
	sea_knight.base_intelligence = 6; sea_knight.base_defense = 9; sea_knight.base_resistance = 9
	sea_knight.hp_growth = Vector2i(5,7); sea_knight.str_growth = Vector2i(3,5)
	sea_knight.agi_growth = Vector2i(2,4); sea_knight.int_growth = Vector2i(2,3)
	sea_knight.def_growth = Vector2i(3,4); sea_knight.res_growth = Vector2i(2,3)
	sea_knight.movement_type = TerrainDefs.MovementType.AQUATIC; sea_knight.base_move_speed = 3.0; sea_knight.can_lead = true; sea_knight.deploy_cost = 130
	sea_knight.front_attacks = [_atk("Coral Blade", P, 2, 1.3, FR)]
	sea_knight.back_attacks  = [_atk("Storm Surge", COLD, 1, 1.3, ANY)]
	sea_knight.skills        = [_skill("deep_current", "Deep Current", "Gains +4 AGI when fighting on water.", 7, 6, 1.0, 0.0, 0.0, "agility", 4)]
	sea_knight.promotions    = []
	_reg(sea_knight)

func _save_classes() -> void:
	for class_id: String in _classes:
		var path := "res://data/classes/%s.tres" % class_id
		var result := ResourceSaver.save(_classes[class_id], path)
		if result != OK:
			push_warning("UnitRegistry: failed to save %s (error %d)" % [path, result])
