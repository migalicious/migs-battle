class_name DiplomacyManager
extends Node

const _DiplomacyEvent = preload("res://scripts/diplomacy/DiplomacyEvent.gd")

var _pending_events: Array = []
var _fired_events: Array = []   # event_id strings already triggered this map
var _map_mgr: MapManager = null
var _active_popup: Control = null   # alliance offer popup while shown


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	_map_mgr = get_tree().current_scene.get_node_or_null("MapManager") as MapManager
	_load_scenario_events()
	GameState.faction_relation_changed.connect(_on_relation_changed)


func _load_scenario_events() -> void:
	var idx := GameState.current_scenario_idx
	match idx:
		2:  # "Uneasy Allies" — Player starts allied with Iron Pact
			var betrayal := _DiplomacyEvent.new()
			betrayal.event_type = _DiplomacyEvent.EventType.BETRAYAL
			betrayal.from_faction = TerrainDefs.Faction.ENEMY_B
			betrayal.to_faction = TerrainDefs.Faction.PLAYER
			betrayal.trigger_condition = "player_ahead"
			betrayal.description = "The Iron Pact grows fearful of your power. They withdraw their support."
			betrayal.event_id = "s2_betrayal"
			_pending_events.append(betrayal)

			var offer := _DiplomacyEvent.new()
			offer.event_type = _DiplomacyEvent.EventType.ALLIANCE_OFFER
			offer.from_faction = TerrainDefs.Faction.ENEMY_A
			offer.to_faction = TerrainDefs.Faction.PLAYER
			offer.trigger_condition = "player_behind"
			offer.description = "Vanguard proposes a ceasefire. With Iron Pact as a common threat, perhaps we need not be enemies."
			offer.event_id = "s2_vanguard_offer"
			_pending_events.append(offer)

		4:  # "The Shadow Rises" — Shadow Order appears; may offer terms if player struggles
			var shadow_offer := _DiplomacyEvent.new()
			shadow_offer.event_type = _DiplomacyEvent.EventType.ALLIANCE_OFFER
			shadow_offer.from_faction = TerrainDefs.Faction.ENEMY_C
			shadow_offer.to_faction = TerrainDefs.Faction.PLAYER
			shadow_offer.trigger_condition = "player_behind"
			shadow_offer.description = "The Shadow Order proposes terms. Will you accept their dark bargain?"
			shadow_offer.event_id = "s4_shadow_offer"
			_pending_events.append(shadow_offer)

		5:  # "The Final March" — Enemies form a desperate pact if player dominates
			var pact := _DiplomacyEvent.new()
			pact.event_type = _DiplomacyEvent.EventType.ENEMY_ALLIANCE
			pact.from_faction = TerrainDefs.Faction.ENEMY_A
			pact.to_faction = TerrainDefs.Faction.ENEMY_B
			pact.trigger_condition = "player_ahead"
			pact.description = "Vanguard and Iron Pact forge a desperate alliance against you."
			pact.event_id = "s5_pact"
			_pending_events.append(pact)


func _process(_delta: float) -> void:
	if GameState.current_phase != GameState.Phase.OVERWORLD:
		return
	if _active_popup and is_instance_valid(_active_popup):
		return  # wait for player to dismiss popup
	for event in _pending_events:
		var ev = event as _DiplomacyEvent
		if _already_fired(ev.event_id):
			continue
		if _condition_met(ev):
			_fire_event(ev)
			break  # fire at most one event per tick to avoid races


func _already_fired(event_id: String) -> bool:
	return _fired_events.has(event_id)


func _condition_met(event) -> bool:
	var ev = event as _DiplomacyEvent
	match ev.trigger_condition:
		"player_ahead":
			return _player_town_fraction() > 0.6
		"player_behind":
			return _player_town_fraction() < 0.3
		_:
			if ev.trigger_condition.begins_with("timer_"):
				var t := int(ev.trigger_condition.split("_")[1])
				return Time.get_ticks_msec() / 1000.0 > float(t)
	return false


func _fire_event(event) -> void:
	var ev = event as _DiplomacyEvent
	_fired_events.append(ev.event_id)
	match ev.event_type:
		_DiplomacyEvent.EventType.BETRAYAL:
			GameState.set_relation(ev.from_faction, ev.to_faction, GameState.Relation.HOSTILE)
		_DiplomacyEvent.EventType.ENEMY_ALLIANCE:
			GameState.set_relation(ev.from_faction, ev.to_faction, GameState.Relation.ALLIED)
		_DiplomacyEvent.EventType.ALLIANCE_OFFER:
			_show_alliance_popup(ev)


func _on_relation_changed(f_a: int, f_b: int, new_relation: int) -> void:
	if GameState.current_phase != GameState.Phase.OVERWORLD:
		return
	var name_a: String = TerrainDefs.FACTION_NAMES.get(f_a, "Unknown")
	var name_b: String = TerrainDefs.FACTION_NAMES.get(f_b, "Unknown")
	if new_relation == int(GameState.Relation.HOSTILE):
		_show_banner(name_a + " has betrayed " + name_b + "!")
	elif new_relation == int(GameState.Relation.ALLIED):
		_show_banner(name_a + " and " + name_b + " forge an alliance!")


func _show_banner(text: String) -> void:
	var hud := get_tree().current_scene.get_node_or_null("HUD") as CanvasLayer
	if not hud:
		return
	var panel := Panel.new()
	panel.size = Vector2(520, 52)
	panel.position = Vector2((get_viewport().size.x - 520) / 2.0, 48)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(lbl)
	hud.add_child(panel)
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(panel.queue_free)


func _show_alliance_popup(event) -> void:
	var ev = event as _DiplomacyEvent
	var hud := get_tree().current_scene.get_node_or_null("HUD") as CanvasLayer
	if not hud:
		return
	# NOTE: deliberately do NOT pause the tree. The overworld is real-time; a modal
	# full-pause froze every squad until the offer was answered, which (a) stalled
	# automated play / the win-rate harness and (b) is heavy-handed UX for a side
	# event. The offer panel below stays on screen and answerable while the world
	# keeps running — answer it whenever; ignoring it simply leaves relations as-is.

	var panel := Panel.new()
	panel.size = Vector2(480, 180)
	panel.position = Vector2(
		(get_viewport().size.x - 480) / 2.0,
		(get_viewport().size.y - 180) / 2.0)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "DIPLOMACY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = ev.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(desc)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)

	var accept_btn := Button.new()
	accept_btn.text = "Accept Alliance"
	accept_btn.custom_minimum_size = Vector2(160, 36)
	accept_btn.pressed.connect(func():
		GameState.set_relation(ev.from_faction, ev.to_faction, GameState.Relation.ALLIED)
		panel.queue_free()
		_active_popup = null)
	hbox.add_child(accept_btn)

	var refuse_btn := Button.new()
	refuse_btn.text = "Refuse"
	refuse_btn.custom_minimum_size = Vector2(120, 36)
	refuse_btn.pressed.connect(func():
		panel.queue_free()
		_active_popup = null)
	hbox.add_child(refuse_btn)

	vbox.add_child(hbox)
	panel.add_child(vbox)
	hud.add_child(panel)
	_active_popup = panel


func _player_town_fraction() -> float:
	if not _map_mgr:
		return 0.0
	var towns := _map_mgr.get_towns()
	if towns.is_empty():
		return 0.0
	var player_count := 0
	for t in towns:
		if (t as TownNode).faction == TerrainDefs.Faction.PLAYER:
			player_count += 1
	return float(player_count) / float(towns.size())
