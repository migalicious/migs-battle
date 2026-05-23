extends Node3D

# Spawns one AIFaction node per enemy faction in GameState.active_factions.
# The scene already contains a hardcoded AIFaction node for ENEMY_A (faction=1).
# This script spawns additional nodes for ENEMY_B (2) and ENEMY_C (3) if active.

const _AIFactionScript = preload("res://scripts/ai/AIFaction.gd")

func _ready() -> void:
	for faction in GameState.active_factions:
		if faction <= TerrainDefs.Faction.ENEMY_A:
			continue  # Player and ENEMY_A are already in the scene
		var ai := Node.new()
		ai.set_script(_AIFactionScript)
		ai.name = "AIFaction_%d" % faction
		add_child(ai)
		# set controlled_faction AFTER add_child so it's read by the deferred _setup() call
		(ai as AIFaction).controlled_faction = faction
