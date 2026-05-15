extends Node

signal battle_started(attacker: Resource, defender: Resource)
signal battle_ended(result: Resource)

func _ready() -> void:
	pass

func on_squads_collided(sq_a: Node, sq_b: Node) -> void:
	# TODO M7: pause tree, resolve battle, show BattleScene, apply result
	print("Battle triggered: %s vs %s" % [sq_a.name, sq_b.name])
