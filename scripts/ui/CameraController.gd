extends Camera3D

const PAN_SPEED  := 15.0
const ZOOM_SPEED := 2.0
const MIN_HEIGHT := 5.0
const MAX_HEIGHT := 60.0

func _process(delta: float) -> void:
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    pan.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  pan.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): pan.x += 1.0
	if pan != Vector3.ZERO:
		global_position += pan.normalized() * PAN_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			position.y = max(MIN_HEIGHT, position.y - ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			position.y = min(MAX_HEIGHT, position.y + ZOOM_SPEED)
