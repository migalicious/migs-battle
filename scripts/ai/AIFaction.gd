class_name AIFaction
extends Node

const _SQUAD_SCENE := preload("res://scenes/squads/Squad.tscn")

@export var controlled_faction: int = TerrainDefs.Faction.ENEMY_A

var tick_timer: float = 0.0

var _map_manager: MapManager = null
var _squad_controller: SquadController = null
var _diff: DifficultyConfig = null   # active difficulty config (enemy levers)

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	_map_manager = get_parent().get_node("MapManager") as MapManager
	_squad_controller = get_parent().get_node("Squads") as SquadController
	_diff = GameState.get_difficulty()
	if _map_manager and _squad_controller:
		_initial_spawn()

func _process(delta: float) -> void:
	if GameState.current_phase != GameState.Phase.OVERWORLD:
		return
	tick_timer += delta
	if tick_timer >= GameBalance.AI_TICK_INTERVAL:
		tick_timer = 0.0
		_run_ai_tick()

# ── Spawning ──────────────────────────────────────────────────────────────────

func _initial_spawn() -> void:
	var hq := _map_manager.get_hq(controlled_faction)
	if not hq:
		return
	var ti := 0

	# 1. Garrison the HQ so capturing it forces a battle (an undefended HQ could be
	#    walked in and taken with zero combat).
	_spawn_garrison(hq, "ai_%d_hqdef" % controlled_faction)

	# 2. Garrison the faction's secondary strongholds (castles it owns at spawn) so
	#    the player must fight through defended deploy-points, not just the HQ.
	for town in _map_manager.get_towns_by_faction(controlled_faction):
		var tn := town as TownNode
		if tn == hq or not tn.town_data.is_stronghold():
			continue
		_spawn_garrison(tn, "ai_%d_gar_%d" % [controlled_faction, ti])
		ti += 1

	# 3. Roaming patrols (additive to garrisons), spawned around the HQ so they
	#    spread out and the player runs into them mid-map. (The faction owns only
	#    its HQ + claimed castles at spawn, so roamers can't come from owned towns.)
	var roamers: int = _diff.roamers_per_faction if _diff else GameBalance.AI_MAX_ROAMERS
	for r in range(roamers):
		var data := _build_template(ti)
		data.squad_id = "ai_%d_%d" % [controlled_faction, ti]
		_equip_template_items(data, ti)
		var sq: Squad = _SQUAD_SCENE.instantiate() as Squad
		_squad_controller.add_child(sq)
		var ang := TAU * float(r) / float(maxi(1, roamers))
		sq.global_position = Vector3(
			hq.global_position.x + cos(ang) * 2.5, 0.5, hq.global_position.z + sin(ang) * 2.5)
		sq.setup(data)
		_squad_controller.wire_squad(sq)
		ti += 1

func _spawn_garrison(town: TownNode, squad_id: String) -> void:
	var gdata := _template_hq_garrison()
	gdata.squad_id = squad_id
	_equip_template_items(gdata, 0)
	var gsq: Squad = _SQUAD_SCENE.instantiate() as Squad
	_squad_controller.add_child(gsq)
	gsq.global_position = Vector3(town.global_position.x, 0.5, town.global_position.z)
	gsq.setup(gdata)
	_squad_controller.wire_squad(gsq)
	gsq.garrison_at(town)
	town.set_garrison(gsq)

# ── Tick Loop ─────────────────────────────────────────────────────────────────

func _run_ai_tick() -> void:
	for sq in GameState.get_squads_by_faction(controlled_faction):
		if not is_instance_valid(sq):
			continue
		if sq.in_battle or sq.is_garrisoned:
			continue
		var objective := _assign_objective(sq)
		_execute_objective(sq, objective)
	_consider_reinforcement()

func _assign_objective(squad: Squad) -> Dictionary:
	if _hq_under_threat():
		var hq := _map_manager.get_hq(controlled_faction)
		if hq:
			return {"type": "defend", "target": hq}

	# Cooperative: assist an allied faction whose HQ is under threat
	for faction in GameState.active_factions:
		if faction == controlled_faction:
			continue
		if GameState.get_relation(controlled_faction, faction) != GameState.Relation.ALLIED:
			continue
		if _faction_hq_under_threat(faction):
			var allied_hq := _map_manager.get_hq(faction)
			if allied_hq:
				return {"type": "assist_ally", "target": allied_hq}

	var lost := _find_recently_lost_town()
	if lost:
		return {"type": "recapture", "target": lost}

	var neutral := _find_nearest_town_with_faction(squad.global_position, TerrainDefs.Faction.NEUTRAL)
	if neutral:
		return {"type": "capture", "target": neutral}

	# Attack the nearest hostile faction's town
	var hostile_town := _find_nearest_hostile_town(squad.global_position)
	if hostile_town:
		return {"type": "attack", "target": hostile_town}

	return {"type": "patrol", "target": _find_patrol_target(squad)}

func _execute_objective(squad: Squad, objective: Dictionary) -> void:
	var target: Node = objective["target"] as Node
	if not is_instance_valid(target):
		return
	var base_pos: Vector3 = target.global_position
	var jitter := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	squad.set_destination(base_pos + jitter)

# ── Threat Detection ──────────────────────────────────────────────────────────

func _hq_under_threat() -> bool:
	return _faction_hq_under_threat(controlled_faction)

func _faction_hq_under_threat(faction: int) -> bool:
	var hq := _map_manager.get_hq(faction)
	if not hq:
		return false
	for other_faction in GameState.active_factions:
		if not GameState.are_hostile(faction, other_faction):
			continue
		for sq in GameState.get_squads_by_faction(other_faction):
			if is_instance_valid(sq) and sq.global_position.distance_to(hq.global_position) < GameBalance.AI_THREAT_RADIUS:
				return true
	return false

# ── Town Finders ──────────────────────────────────────────────────────────────

func _find_recently_lost_town() -> TownNode:
	for town in _map_manager.get_towns():
		if town.town_data.starting_faction == controlled_faction \
		   and town.faction != controlled_faction:
			return town
	return null

func _find_nearest_town_with_faction(from: Vector3, faction: int) -> TownNode:
	var nearest: TownNode = null
	var nearest_dist := INF
	for town in _map_manager.get_towns():
		if town.faction == faction:
			var dist := from.distance_to(town.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = town
	return nearest

func _find_nearest_hostile_town(from: Vector3) -> TownNode:
	var nearest: TownNode = null
	var nearest_dist := INF
	for town in _map_manager.get_towns():
		if GameState.are_hostile(controlled_faction, town.faction):
			var dist := from.distance_to(town.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = town
	return nearest

func _find_patrol_target(_squad: Squad) -> TownNode:
	var friendly := _map_manager.get_towns_by_faction(controlled_faction)
	if not friendly.is_empty():
		return friendly[randi() % friendly.size()]
	var hq := _map_manager.get_hq(controlled_faction)
	if hq:
		return hq
	var all_towns := _map_manager.get_towns()
	if not all_towns.is_empty():
		return all_towns[randi() % all_towns.size()]
	return null

# ── Squad Templates ───────────────────────────────────────────────────────────

func _allowed_templates() -> Array[int]:
	var tier := _diff.template_tier if _diff else 1
	if tier <= 0:
		return [1, 3]         # B(4u) + D(3u) — early
	elif tier == 1:
		return [0, 1, 3]      # + A(5u) — mid-early
	elif tier == 2:
		return [4, 1, 2, 3]   # E(brutes) replaces A; C(paladin) enters — mid-late
	else:
		return [5, 1, 4, 2]   # F(cavalry) + E(brutes) as primary; B + C as support — late

func _build_template(template_idx: int) -> SquadData:
	var allowed := _allowed_templates()
	var t := allowed[template_idx % allowed.size()]
	match t:
		0: return _template_a()
		1: return _template_b()
		2: return _template_c()
		3: return _template_d()
		4: return _template_e()
		_: return _template_f()

func _template_a() -> SquadData:
	var d := SquadData.new()
	d.faction = controlled_faction
	_add(d, "knight",  "Commander",  0, 0, true,  5)
	_add(d, "fighter", "Soldier",    0, 1, false, 3)
	_add(d, "fighter", "Grunt",      0, 2, false, 3)
	_add(d, "archer",  "Bowman",     1, 0, false, 3)
	_add(d, "archer",  "Scout",      1, 1, false, 3)
	return d

func _template_b() -> SquadData:
	var d := SquadData.new()
	d.faction = controlled_faction
	_add(d, "knight", "Dark Knight",  0, 0, true,  5)
	_add(d, "knight", "Iron Guard",   0, 1, false, 5)
	_add(d, "mage",   "Shadow Mage",  1, 0, false, 4)
	_add(d, "mage",   "Hex Caster",   1, 1, false, 4)
	return d

func _template_c() -> SquadData:
	var d := SquadData.new()
	d.faction = controlled_faction
	_add(d, "paladin", "Paladin Lord",  0, 0, true,  6)
	_add(d, "knight",  "Heavy Knight",  0, 1, false, 6)
	_add(d, "knight",  "Iron Guard",    0, 2, false, 6)
	_add(d, "archer",  "Veteran Bow",   1, 0, false, 6)
	_add(d, "mage",    "Battle Mage",   1, 1, false, 5)
	return d

func _template_d() -> SquadData:
	var d := SquadData.new()
	d.faction = controlled_faction
	_add(d, "cavalry", "Scout Captain", 0, 0, true,  4)
	_add(d, "cavalry", "Rider",         0, 1, false, 4)
	_add(d, "archer",  "Marksman",      1, 0, false, 3)
	return d

func _template_e() -> SquadData:
	var d := SquadData.new()
	d.faction = controlled_faction
	_add(d, "warrior", "War Chief",   0, 0, true,  6)
	_add(d, "warrior", "Enforcer",    0, 1, false, 6)
	_add(d, "fighter", "Brute",       0, 2, false, 5)
	_add(d, "archer",  "Sniper",      1, 0, false, 5)
	_add(d, "mage",    "Battle Mage", 1, 1, false, 5)
	return d

func _template_hq_garrison() -> SquadData:
	# Stronghold defender. Size from the difficulty config (a knight leader + archers).
	# Kept modest so an assault stays winnable (a garrison heals between assaults).
	var d := SquadData.new()
	d.faction = controlled_faction
	var size: int = _diff.garrison_size if _diff else 2
	_add(d, "knight", "HQ Guard", 0, 0, true, 4)
	var slots := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)]
	for i in range(mini(maxi(0, size - 1), slots.size())):
		_add(d, "archer", "HQ Sentry", slots[i].x, slots[i].y, false, 3)
	return d

func _template_f() -> SquadData:
	var d := SquadData.new()
	d.faction = controlled_faction
	_add(d, "cavalry", "Lance Lord",   0, 0, true,  8)
	_add(d, "cavalry", "Outrider",     0, 1, false, 7)
	_add(d, "cavalry", "Charger",      0, 2, false, 6)
	_add(d, "archer",  "Horse Bow",    1, 0, false, 6)
	_add(d, "mage",    "Vanguard Hex", 1, 1, false, 5)
	return d

func _add(data: SquadData, class_id: String, uname: String, row: int, col: int, is_leader: bool, level: int) -> void:
	var eff_level := maxi(1, level + _diff.enemy_level_bonus)
	var unit := UnitRegistry.create_unit(class_id, eff_level)
	if not unit:
		return
	# True all-stats multiplier (unlike the old fractional level-mult, this scales actual stats).
	var m := _diff.enemy_stat_mult
	if m != 1.0:
		unit.max_hp       = maxi(1, int(unit.max_hp * m))
		unit.hp           = unit.max_hp
		unit.strength     = maxi(1, int(unit.strength * m))
		unit.agility      = maxi(1, int(unit.agility * m))
		unit.intelligence = maxi(1, int(unit.intelligence * m))
		unit.defense      = maxi(1, int(unit.defense * m))
		unit.resistance   = maxi(1, int(unit.resistance * m))
	unit.unit_name = uname
	unit.row = row
	unit.col = col
	unit.faction = controlled_faction
	unit.is_leader = is_leader
	data.units.append(unit)

# ── AI Item Assignment ────────────────────────────────────────────────────────

func _equip_template_items(data: SquadData, template_idx: int) -> void:
	for u in data.units:
		var cls := UnitRegistry.get_class_def(u.class_id) as ClassDefinition
		if not cls:
			continue
		match template_idx % 4:
			0, 3:  # A/D: light items
				if u.row == 0 or u.is_leader:
					u.held_item = _pick_item(["iron_shield", "speed_boots"])
			1:  # B: magic users
				if u.class_id in ["mage", "sorcerer", "witch", "cleric"]:
					u.held_item = _pick_item(["mage_robe", "silver_mail"])
				elif u.row == 0:
					u.held_item = "silver_mail"
			2:  # C: heavy — leader gets power_ring + silver_mail split
				if u.is_leader:
					u.held_item = "power_ring"
				elif u.row == 0:
					u.held_item = "silver_mail"

func _pick_item(options: Array) -> String:
	return options[randi() % options.size()] as String

# ── AI Reinforcement ──────────────────────────────────────────────────────────

func _consider_reinforcement() -> void:
	var current_count := GameState.get_squads_by_faction(controlled_faction).size()
	if current_count >= GameBalance.AI_MAX_SQUADS:
		return
	var reinforce_cost: int = _diff.reinforce_gold_threshold if _diff else GameBalance.AI_REINFORCE_GOLD_THRESHOLD
	if GameState.enemy_gold < reinforce_cost:
		return
	var spawn_town := _find_unoccupied_friendly_town()
	if not spawn_town:
		return
	GameState.enemy_gold -= GameBalance.AI_REINFORCE_GOLD_THRESHOLD
	var template_idx := randi() % 4
	var data := _build_template(template_idx)
	data.squad_id = "ai_%d_reinf_%d" % [controlled_faction, Time.get_ticks_msec()]
	_equip_template_items(data, template_idx)
	var sq: Squad = _SQUAD_SCENE.instantiate() as Squad
	_squad_controller.add_child(sq)
	sq.global_position = Vector3(spawn_town.global_position.x, 0.5, spawn_town.global_position.z + 2.0)
	sq.setup(data)
	_squad_controller.wire_squad(sq)

func _find_unoccupied_friendly_town() -> TownNode:
	for town in _map_manager.get_towns_by_faction(controlled_faction):
		if not town.town_data.is_stronghold():
			continue  # reinforcements deploy only from strongholds
		if not is_instance_valid(town.garrisoned_squad):
			var occupied := false
			for sq in GameState.get_squads_by_faction(controlled_faction):
				if is_instance_valid(sq) and sq.global_position.distance_to(town.global_position) < 2.0:
					occupied = true
					break
			if not occupied:
				return town
	return null
