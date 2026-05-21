extends Node

const PORT := 6560

var _server: TCPServer = null
var _client: StreamPeerTCP = null
var _buf: String = ""

func _ready() -> void:
	if not OS.is_debug_build():
		return
	_server = TCPServer.new()
	if _server.listen(PORT) != OK:
		push_warning("DebugServer: could not listen on port %d" % PORT)
		return
	print("[DebugServer] Listening on 127.0.0.1:%d" % PORT)

func _process(_delta: float) -> void:
	if not _server or not _server.is_listening():
		return
	# Poll client to refresh its connection status
	if _client:
		_client.poll()
		var st := _client.get_status()
		if st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
			_client = null
			_buf = ""
	# Accept a new connection whenever the current slot is free
	if _server.is_connection_available() and \
			(not _client or _client.get_status() != StreamPeerTCP.STATUS_CONNECTED):
		_client = _server.take_connection()
		_client.poll()
		_buf = ""
	if not _client or _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var avail := _client.get_available_bytes()
	if avail > 0:
		var res := _client.get_data(avail)
		if res[0] == OK:
			_buf += (res[1] as PackedByteArray).get_string_from_utf8()
			_process_buffer()

func _process_buffer() -> void:
	while "\n" in _buf:
		var nl := _buf.find("\n")
		var line := _buf.substr(0, nl).strip_edges()
		_buf = _buf.substr(nl + 1)
		if line.length() > 0:
			_handle(line)

func _handle(raw: String) -> void:
	var cmd: Variant = JSON.parse_string(raw)
	if not cmd is Dictionary:
		_send({"error": "invalid json"})
		return
	var d := cmd as Dictionary
	match d.get("action", ""):
		"click":
			_mouse_click(Vector2(float(d.get("x", 0)), float(d.get("y", 0))), MOUSE_BUTTON_LEFT)
			_send({"ok": true})
		"right_click":
			_mouse_click(Vector2(float(d.get("x", 0)), float(d.get("y", 0))), MOUSE_BUTTON_RIGHT)
			_send({"ok": true})
		"move_mouse":
			_mouse_move(Vector2(float(d.get("x", 0)), float(d.get("y", 0))))
			_send({"ok": true})
		"key":
			_key_event(int(d.get("keycode", 0)), bool(d.get("pressed", true)))
			_send({"ok": true})
		"screenshot":
			_take_screenshot(str(d.get("path", "/tmp/migs_screenshot.png")))
		"press_button":
			var text := str(d.get("text", ""))
			var btn := _find_button(get_tree().current_scene, text)
			if btn:
				btn.emit_signal("pressed")
				_send({"ok": true})
			else:
				_send({"error": "button not found: %s" % text})
		"set_option":
			var node_name := str(d.get("node", ""))
			var value: int = int(d.get("value", 0))
			var ob := _find_node_by_class(get_tree().current_scene, "OptionButton", node_name) as OptionButton
			if ob:
				ob.selected = value
				ob.item_selected.emit(value)
				_send({"ok": true})
			else:
				_send({"error": "OptionButton not found: %s" % node_name})
		"set_line_edit":
			var node_name := str(d.get("node", ""))
			var text := str(d.get("text", ""))
			var le := _find_node_by_class(get_tree().current_scene, "LineEdit", node_name) as LineEdit
			if le:
				le.text = text
				le.text_changed.emit(text)
				_send({"ok": true})
			else:
				_send({"error": "LineEdit not found: %s" % node_name})
		"scene_tree":
			_send({"tree": _dump_tree(get_tree().current_scene, 0)})
		"state":
			_send(_build_state())
		_:
			_send({"error": "unknown action: %s" % d.get("action", "")})

func _mouse_click(pos: Vector2, button: int) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button as MouseButton
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = button as MouseButton
	release.pressed = false
	release.position = pos
	release.global_position = pos
	Input.parse_input_event(release)

func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

func _key_event(keycode: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode as Key
	ev.pressed = pressed
	ev.echo = false
	Input.parse_input_event(ev)

func _take_screenshot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		_send({"ok": true, "path": path})
	else:
		_send({"error": "save failed (err %d)" % err, "path": path})

func _build_state() -> Dictionary:
	var scene := get_tree().current_scene
	var vp := get_viewport()
	return {
		"scene": str(scene.name) if scene else "",
		"phase": GameState.current_phase,
		"map_seed": GameState.map_seed,
		"player_squads": GameState.player_squads.size(),
		"enemy_squads": GameState.enemy_squads.size(),
		"reserve_squads": GameState.reserve_squads.size(),
		"active_conditions": GameState.active_conditions,
		"town_ownership": GameState.town_ownership,
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"viewport_size": [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y],
		"content_scale": DisplayServer.screen_get_scale(),
	}

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var result := _find_button(child, text)
		if result:
			return result
	return null

func _find_node_by_class(node: Node, cls: String, hint: String) -> Node:
	if node.get_class() == cls and (hint.is_empty() or node.name.contains(hint)):
		return node
	for child in node.get_children():
		var result := _find_node_by_class(child, cls, hint)
		if result:
			return result
	return null

func _dump_tree(node: Node, depth: int) -> Array:
	if depth > 6:
		return []
	var entry := {"name": str(node.name), "class": node.get_class(), "children": []}
	if node is Button:
		entry["text"] = (node as Button).text
	elif node is Label:
		entry["text"] = (node as Label).text
	elif node is OptionButton:
		entry["selected"] = (node as OptionButton).selected
	elif node is LineEdit:
		entry["text"] = (node as LineEdit).text
	for child in node.get_children():
		(entry["children"] as Array).append(_dump_tree(child, depth + 1))
	return [entry]

func _send(data: Dictionary) -> void:
	if _client and _client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_client.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())
