extends Node

var _classes: Dictionary = {}  # class_id -> ClassDefinition

func _ready() -> void:
	pass

func get_class_def(class_id: String) -> Resource:
	return _classes.get(class_id, null)

func create_unit(_class_id: String, _level: int) -> Resource:
	return null
