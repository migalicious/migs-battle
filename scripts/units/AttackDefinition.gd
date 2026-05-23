class_name AttackDefinition
extends Resource

@export var attack_name: String = ""
@export var damage_type: TerrainDefs.DamageType = TerrainDefs.DamageType.PHYSICAL
@export var hits: int = 1
@export var power_multiplier: float = 1.0
@export var targets_row: TerrainDefs.TargetRow = TerrainDefs.TargetRow.FRONT
@export var hits_all_in_column: bool = false
@export var hits_all_in_row: bool = false
@export var condition_id: String = ""
@export var is_heal: bool = false
