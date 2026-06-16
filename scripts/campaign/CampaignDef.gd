class_name CampaignDef
extends Resource

const _ScenarioDef = preload("res://scripts/campaign/ScenarioDef.gd")

@export var campaign_name: String = "The Black March"
@export var scenarios: Array = []          # Array of ScenarioDef (untyped for parse safety)
@export var starting_units: Array = []     # Array of Dictionary {class_id, unit_name, level}
@export var starting_gold: int = 150

# Instance method: populate this CampaignDef with the default "The Black March" campaign data.
# Callers: _CampaignDef.new().build_default()
func build_default() -> void:
	campaign_name = "The Black March"
	starting_gold = 300   # afford gear + a deploy or two early (Phase 4 first pass)

	# 3 named heroes (squad leaders) + base-stat filler so the player opens with ~2 squads.
	starting_units = [
		{"class_id": "knight", "unit_name": "Roland", "level": 7, "is_hero": true},
		{"class_id": "archer", "unit_name": "Sylvia", "level": 5, "is_hero": true},
		{"class_id": "mage",   "unit_name": "Merlin", "level": 5, "is_hero": true},
		{"class_id": "fighter", "unit_name": "Garrett", "level": 4},
		{"class_id": "fighter", "unit_name": "Dell",    "level": 3},
		{"class_id": "archer",  "unit_name": "Wynn",    "level": 3},
	]

	# First-pass difficulty curve (Recruit -> Warlord-ish ramp). Tuned against the
	# win-rate harness; all_strongholds maps (S1/S3/S5) are harder by win condition,
	# so their density is kept modest. _diff(level_bonus, stat_mult, roamers, castles, garrison, tier)
	# Difficulty curve, retuned against the win-rate harness (2026-06-15). The opener was
	# the hardest map (a 6-unit roster vs a 2-strong garrison) while the late game is
	# trivial (the player outgrows the ramp). LESSON FROM TUNING: hardening the mid/late
	# scenarios does NOT lower the win rate cleanly — the autoplayer assaults garrisons
	# piecemeal, so a tougher garrison just produces unbreakable STALEMATES (stalls), not
	# closer fights. So we only EASE the early maps here (a clean, safe lever) and leave
	# S3-S5 at their original values. Making the finale genuinely hard needs the
	# autoplayer to concentrate force first (see playtest_bridge memory).
	scenarios = [
		_make(0, "Border Skirmish",
			"A small border dispute. Test your forces against the Vanguard.",
			112233, 24, 24, 4, 1, [0, 1], "hostile_all", ["hq_capture"],
			[{"class_id": "cleric", "unit_name": "Mira", "level": 4, "is_hero": true}],
			_diff("Skirmish", 0, 0.85, 2, 1, 1, 0)),
		_make(1, "The River Crossing",
			"Push across the river and claim the enemy's keep.",
			445566, 32, 32, 6, 2, [0, 1], "hostile_all", ["hq_capture", "all_strongholds"],
			[{"class_id": "gryphon_rider", "unit_name": "Aquila", "level": 5, "is_hero": true}],
			_diff("Crossing", 0, 0.88, 2, 1, 2, 0)),
		_make(2, "Uneasy Allies",
			"The Iron Pact offers unlikely aid against a common enemy. Trust them — for now.",
			778899, 32, 32, 7, 2, [0, 1, 2], "alliance_b", ["hq_capture"],
			[{"class_id": "sea_knight", "unit_name": "Nerin", "level": 5, "is_hero": true}],
			# Left at 0.95 (≈100% in the harness, i.e. easy). Even a 0.02 stat bump dropped
			# it to ~33% — the autoplayer can't survive a harder S2, so this can't be made
			# "harder" cleanly until autoplayer tactics improve. Stays a breather mission.
			_diff("Allies", 0, 0.95, 2, 1, 2, 1)),
		_make(3, "Three Kingdoms",
			"The alliance is shattered. Every faction fights for total control.",
			101010, 48, 48, 5, 2, [0, 1, 2], "three_way", ["all_strongholds"],
			[{"class_id": "paladin",  "unit_name": "Garran", "level": 6, "is_hero": true},
			 {"class_id": "sorcerer", "unit_name": "Vesna",  "level": 6, "is_hero": true}],
			_diff("Kingdoms", 0, 0.98, 2, 1, 2, 1)),
		_make(4, "The Shadow Rises",
			"A new power emerges from the east. Crush them before they consolidate.",
			202020, 48, 48, 8, 3, [0, 1, 3], "hostile_all", ["hq_capture"],
			[{"class_id": "witch",   "unit_name": "Hilda", "level": 6, "is_hero": true},
			 {"class_id": "cavalry", "unit_name": "Brunn", "level": 6, "is_hero": true}],
			_diff("Shadow", 1, 1.00, 2, 1, 2, 1)),
		_make(5, "The Final March",
			"The last stand. Your army against the world.",
			303030, 48, 48, 10, 4, [0, 1, 2, 3], "free_for_all", ["all_strongholds"],
			[],
			_diff("Final", 1, 1.05, 2, 1, 2, 2)),
	]

func _diff(name: String, level_bonus: int, stat_mult: float, roamers: int,
		castles: int, garrison: int, tier: int) -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.display_name = name
	c.enemy_level_bonus = level_bonus
	c.enemy_stat_mult = stat_mult
	c.roamers_per_faction = roamers
	c.castles_per_faction = castles
	c.garrison_size = garrison
	c.template_tier = tier
	return c

func _make(idx: int, sname: String, desc: String,
		map_seed_val: int, w: int, h: int, towns: int, castles: int,
		factions: Array, preset: String, wins: Array, rewards: Array = [],
		difficulty: DifficultyConfig = null):
	var s := _ScenarioDef.new()
	s.scenario_idx = idx
	s.scenario_name = sname
	s.description = desc
	s.map_seed = map_seed_val
	s.map_width = w
	s.map_height = h
	s.num_towns = towns
	s.num_castles = castles
	# Assign fresh arrays — ScenarioDef has non-empty defaults ([0,1] / ["hq_capture"]),
	# so appending here would DUPLICATE them (doubling factions -> duplicate HQ nodes,
	# and doubling/leaking win conditions onto every scenario).
	var fac: Array[int] = []
	for f in factions:
		fac.append(int(f))
	s.active_factions = fac
	s.faction_preset = preset
	var wc_arr: Array[String] = []
	for wc in wins:
		wc_arr.append(str(wc))
	s.win_conditions = wc_arr
	s.reward_units = rewards
	s.difficulty = difficulty
	return s
