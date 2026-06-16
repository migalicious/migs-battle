class_name DifficultyConfig
extends Resource

# Mode-agnostic difficulty configuration: the concrete enemy levers the AI reads.
# Used by the campaign (per-scenario, to shape its curve), the random-map flow, and
# any future mode. Set the active one on GameState.active_difficulty before a map loads.

@export var display_name: String = "Veteran"

# Enemy unit strength
@export var enemy_level_bonus: int = 0      # ADDED to each template unit's level (crosses real thresholds)
@export var enemy_stat_mult: float = 1.0    # TRUE multiplier applied to every stat of a created enemy unit
@export var template_tier: int = 1          # which AI squad templates spawn: 0 early .. 3 lategame

# Enemy density (per faction)
@export var roamers_per_faction: int = 3    # roaming patrol squads
@export var castles_per_faction: int = 1    # secondary deploy-strongholds each faction holds
@export var garrison_size: int = 2          # units stationed in each stronghold garrison

# Enemy economy
@export var reinforce_gold_threshold: int = 200   # gold the AI needs to spawn a reinforcement

# ── Named presets ───────────────────────────────────────────────────────────────

static func recruit() -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.display_name = "Recruit"
	c.enemy_level_bonus = -1
	c.enemy_stat_mult = 0.90
	c.template_tier = 0
	c.roamers_per_faction = 2
	c.castles_per_faction = 1
	c.garrison_size = 2
	c.reinforce_gold_threshold = 300
	return c

static func veteran() -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.display_name = "Veteran"
	c.enemy_level_bonus = 0
	c.enemy_stat_mult = 1.0
	c.template_tier = 1
	c.roamers_per_faction = 3
	c.castles_per_faction = 1
	c.garrison_size = 2
	c.reinforce_gold_threshold = 200
	return c

static func warlord() -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.display_name = "Warlord"
	c.enemy_level_bonus = 2
	c.enemy_stat_mult = 1.15
	c.template_tier = 2
	c.roamers_per_faction = 4
	c.castles_per_faction = 2
	c.garrison_size = 3
	c.reinforce_gold_threshold = 150
	return c

# Ordered presets (for UI pickers).
static func presets() -> Array:
	return [recruit(), veteran(), warlord()]

static func default() -> DifficultyConfig:
	return veteran()

# Build a copy of `base` with field overrides (for per-scenario campaign tuning).
static func with_overrides(base: DifficultyConfig, overrides: Dictionary) -> DifficultyConfig:
	var c := base.duplicate() as DifficultyConfig
	for k in overrides:
		c.set(k, overrides[k])
	return c
