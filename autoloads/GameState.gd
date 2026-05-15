extends Node

signal faction_won(faction_id: int)

enum Phase { OVERWORLD, IN_BATTLE, VICTORY, DEFEAT }

var current_phase: Phase = Phase.OVERWORLD
var map_seed: int = 0
var town_ownership: Dictionary = {}  # town_id -> Faction value
var player_squads: Array = []
var enemy_squads: Array = []

func _ready() -> void:
	pass
