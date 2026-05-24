extends Node3D

# Spawns one AIFaction node per enemy faction in GameState.active_factions.
# The scene already contains a hardcoded AIFaction node for ENEMY_A (faction=1).
# This script spawns additional nodes for ENEMY_B (2) and ENEMY_C (3) if active.

const _AIFactionScript = preload("res://scripts/ai/AIFaction.gd")
const _DIFFICULTY_MULTS := [1.0, 1.1, 1.2, 1.35, 1.5, 1.7]

func _ready() -> void:
	var diff_mult := _get_difficulty_mult()
	# Apply difficulty to the hardcoded ENEMY_A node already in the scene
	var enemy_a := get_node_or_null("AIFaction") as AIFaction
	if enemy_a:
		enemy_a.difficulty_mult = diff_mult
	for faction in GameState.active_factions:
		if faction <= TerrainDefs.Faction.ENEMY_A:
			continue  # Player and ENEMY_A are already in the scene
		var ai := Node.new()
		ai.set_script(_AIFactionScript)
		ai.name = "AIFaction_%d" % faction
		add_child(ai)
		(ai as AIFaction).difficulty_mult = diff_mult
		# set controlled_faction AFTER add_child so it's read by the deferred _setup() call
		(ai as AIFaction).controlled_faction = faction

func _get_difficulty_mult() -> float:
	if not GameState.campaign_run_active:
		return 1.0
	var idx := clampi(GameState.current_scenario_idx, 0, _DIFFICULTY_MULTS.size() - 1)
	return _DIFFICULTY_MULTS[idx]
