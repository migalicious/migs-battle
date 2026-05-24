class_name CampaignDef
extends Resource

const _ScenarioDef = preload("res://scripts/campaign/ScenarioDef.gd")

@export var campaign_name: String = "The Black March"
@export var scenarios: Array = []          # Array of ScenarioDef (untyped for parse safety)
@export var starting_units: Array = []     # Array of Dictionary {class_id, unit_name, level}
@export var starting_gold: int = 150

static func build_default() -> CampaignDef:
	var c := CampaignDef.new()
	c.campaign_name = "The Black March"
	c.starting_gold = 150

	c.starting_units = [
		{"class_id": "knight",  "unit_name": "Roland",  "level": 4},
		{"class_id": "archer",  "unit_name": "Sylvia",  "level": 3},
		{"class_id": "mage",    "unit_name": "Merlin",  "level": 3},
		{"class_id": "fighter", "unit_name": "Aldric",  "level": 2},
		{"class_id": "fighter", "unit_name": "Bors",    "level": 2},
		{"class_id": "archer",  "unit_name": "Isolde",  "level": 2},
	]

	c.scenarios = [
		_make(0, "Border Skirmish",
			"A small border dispute. Test your forces against the Vanguard.",
			112233, 24, 24, 4, 1, [0, 1], "hostile_all", ["hq_capture"]),
		_make(1, "The River Crossing",
			"Push across the river and claim the enemy's keep.",
			445566, 32, 32, 6, 2, [0, 1], "hostile_all", ["hq_capture", "all_strongholds"]),
		_make(2, "Uneasy Allies",
			"The Iron Pact offers unlikely aid against a common enemy. Trust them — for now.",
			778899, 32, 32, 7, 2, [0, 1, 2], "alliance_b", ["hq_capture"]),
		_make(3, "Three Kingdoms",
			"The alliance is shattered. Every faction fights for total control.",
			101010, 48, 48, 9, 3, [0, 1, 2], "three_way", ["all_strongholds"]),
		_make(4, "The Shadow Rises",
			"A new power emerges from the east. Crush them before they consolidate.",
			202020, 48, 48, 8, 3, [0, 1, 3], "hostile_all", ["hq_capture"]),
		_make(5, "The Final March",
			"The last stand. Your army against the world.",
			303030, 48, 48, 10, 4, [0, 1, 2, 3], "free_for_all", ["all_strongholds"]),
	]
	return c

static func _make(idx: int, sname: String, desc: String,
		seed: int, w: int, h: int, towns: int, castles: int,
		factions: Array, preset: String, wins: Array) -> ScenarioDef:
	var s := _ScenarioDef.new()
	s.scenario_idx = idx
	s.scenario_name = sname
	s.description = desc
	s.map_seed = seed
	s.map_width = w
	s.map_height = h
	s.num_towns = towns
	s.num_castles = castles
	for f in factions:
		s.active_factions.append(int(f))
	s.faction_preset = preset
	for wc in wins:
		s.win_conditions.append(str(wc))
	return s
