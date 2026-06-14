extends Node

const PORT := 6560
const _ItemDef = preload("res://scripts/items/ItemDefinition.gd")

var _server: TCPServer = null
var _client: StreamPeerTCP = null
var _buf: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay active even when tree is paused (e.g. alliance popup)
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
			# Search from root, not current_scene: modal UI (battle result screen,
			# popups) is added under the SceneTree root, a sibling of current_scene.
			var btn := _find_button(get_tree().root, text)
			if btn:
				if btn.disabled:
					_send({"error": "button is disabled: %s" % text})
				else:
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
			_send({"tree": _dump_tree(get_tree().root, 0)})
		"state":
			_send(_build_state())
		"towns":
			var map_mgr := get_tree().current_scene.get_node_or_null("MapManager") as MapManager
			if not map_mgr:
				_send({"towns": []})
			else:
				var arr := []
				for t in map_mgr.get_towns():
					var sp := get_viewport().get_camera_3d().unproject_position(t.global_position)
					arr.append({"id": t.town_data.town_id, "wx": t.global_position.x, "wz": t.global_position.z, "sx": sp.x, "sy": sp.y,
						"type": int(t.town_data.town_type), "faction": int(t.faction),
						"has_aquatic_recruit": t.town_data.has_aquatic_recruit})
				_send({"towns": arr})
		"equip_item":
			var unit_name_eq := str(d.get("unit", ""))
			var item_id_eq := str(d.get("item", ""))
			var found_unit: UnitData = null
			for sq in GameState.player_squads:
				if sq is Squad:
					for u in (sq as Squad).squad_data.units:
						if u.unit_name == unit_name_eq:
							found_unit = u
			if not found_unit:
				for sd in GameState.reserve_squads:
					if sd is SquadData:
						for u in (sd as SquadData).units:
							if u.unit_name == unit_name_eq:
								found_unit = u
			if not found_unit:
				_send({"error": "unit not found: %s" % unit_name_eq})
			else:
				if found_unit.held_item != "":
					GameState.player_inventory[found_unit.held_item] = GameState.player_inventory.get(found_unit.held_item, 0) + 1
				found_unit.held_item = item_id_eq
				if item_id_eq != "" and GameState.player_inventory.has(item_id_eq):
					GameState.player_inventory[item_id_eq] = maxi(0, (GameState.player_inventory[item_id_eq] as int) - 1)
				_send({"ok": true, "unit": unit_name_eq, "item": item_id_eq})
		"open_town":
			var town_id := str(d.get("town_id", "player_hq"))
			var map_mgr2 := get_tree().current_scene.get_node_or_null("MapManager") as MapManager
			if not map_mgr2:
				_send({"error": "no MapManager"})
			else:
				var found: TownNode = null
				for t in map_mgr2.get_towns():
					if t.town_data.town_id == town_id:
						found = t
						break
				if found:
					found.emit_signal("town_selected", found)
					_send({"ok": true, "town": town_id})
				else:
					_send({"error": "town not found: %s" % town_id})
		"units":
			var all_units: Array = []
			for sq in GameState.player_squads:
				if sq is Squad:
					for u in (sq as Squad).squad_data.units:
						all_units.append(_unit_dict(u as UnitData))
			for sd in GameState.reserve_squads:
				if sd is SquadData:
					for u in (sd as SquadData).units:
						all_units.append(_unit_dict(u as UnitData))
			_send({"units": all_units})
		"squads":
			var out := {"player": [], "reserve": [], "enemy": []}
			for sq in GameState.player_squads:
				if sq is Squad:
					(out["player"] as Array).append(_squad_dict((sq as Squad).squad_data))
			for sd in GameState.reserve_squads:
				if sd is SquadData:
					(out["reserve"] as Array).append(_squad_dict(sd as SquadData))
			for sq in GameState.enemy_squads:
				if sq is Squad:
					(out["enemy"] as Array).append(_squad_dict((sq as Squad).squad_data))
			_send(out)
		"force_battle":
			var atk_sq: Squad = null
			var def_sq: Squad = null
			var fb_enemy_idx: int = int(d.get("enemy_squad_idx", 0))
			for sq in GameState.player_squads:
				if sq is Squad: atk_sq = sq; break
			var fb_enemy_count: int = 0
			for sq in GameState.enemy_squads:
				if sq is Squad:
					if fb_enemy_count == fb_enemy_idx:
						def_sq = sq
						break
					fb_enemy_count += 1
			if not atk_sq or not def_sq:
				_send({"error": "need at least one player and one enemy squad"})
			else:
				var result := BattleResolver.resolve(atk_sq.squad_data, def_sq.squad_data)
				var atk_states: Array = []
				for u in result.attacker_unit_states:
					atk_states.append(_unit_dict(u as UnitData))
				var def_states: Array = []
				for u in result.defender_unit_states:
					def_states.append(_unit_dict(u as UnitData))
				var log_entries: Array = []
				for act in result.action_log:
					var ba := act as BattleAction
					log_entries.append({"type": ba.action_type, "actor": ba.actor_unit_id, "target": ba.target_unit_id, "attack": ba.attack_name, "dmg": ba.damage_dealt})
				_send({"ok": true, "attacker_wiped": result.attacker_wiped, "defender_wiped": result.defender_wiped, "attacker_xp": result.attacker_xp, "defender_xp": result.defender_xp, "attacker_units": atk_states, "defender_units": def_states, "log": log_entries})
		"item_defs":
			var id_list: Array = []
			for item in ItemRegistry.get_all_items():
				id_list.append(_item_dict(item))
			_send({"items": id_list})
		"inventory":
			var inv_list: Array = []
			for inv_id in GameState.player_inventory:
				var inv_qty: int = GameState.player_inventory[inv_id] as int
				if inv_qty <= 0:
					continue
				var inv_item = ItemRegistry.get_item(inv_id)
				var inv_entry := {"id": inv_id, "qty": inv_qty}
				if inv_item:
					inv_entry.merge(_item_dict(inv_item))
				inv_list.append(inv_entry)
			_send({"gold": GameState.player_gold, "inventory": inv_list})
		"give_item":
			var gi_id := str(d.get("item", ""))
			var gi_qty: int = int(d.get("qty", 1))
			if gi_id == "":
				_send({"error": "missing item id"})
			elif not ItemRegistry.get_item(gi_id):
				_send({"error": "unknown item: %s" % gi_id})
			else:
				GameState.player_inventory[gi_id] = GameState.player_inventory.get(gi_id, 0) + gi_qty
				_send({"ok": true, "item": gi_id, "qty": GameState.player_inventory[gi_id]})
		"set_gold":
			var sg_amount: int = int(d.get("amount", 0))
			GameState.player_gold = sg_amount
			GameState.gold_changed.emit(0, sg_amount)
			_send({"ok": true, "gold": GameState.player_gold})
		"get_relations":
			var rel_out := {}
			for key in GameState.faction_relations:
				rel_out[str(key)] = int(GameState.faction_relations[key])
			_send({"relations": rel_out, "active_factions": Array(GameState.active_factions)})
		"trigger_diplomacy":
			var td_from: int = int(d.get("from_faction", 1))
			var td_to: int = int(d.get("to_faction", 0))
			var td_relation: int = int(d.get("relation", GameState.Relation.HOSTILE))
			GameState.set_relation(td_from, td_to, td_relation)
			_send({"ok": true, "from": td_from, "to": td_to, "relation": td_relation})
		"class_defs":
			var cd_list: Array = []
			for cd_id in UnitRegistry._classes:
				cd_list.append(_class_dict(UnitRegistry._classes[cd_id] as ClassDefinition))
			_send({"classes": cd_list})
		"debug_atk_row":
			var cls_id := str(d.get("class_id", "sorcerer"))
			var side := str(d.get("side", "back"))  # "front" or "back"
			if not UnitRegistry._classes.has(cls_id):
				_send({"error": "unknown class"})
			else:
				var cls := UnitRegistry._classes[cls_id] as ClassDefinition
				var attacks: Array = cls.back_attacks if side == "back" else cls.front_attacks
				if attacks.is_empty():
					_send({"error": "no attacks"})
				else:
					var a := attacks[0] as AttackDefinition
					var tr_raw = a.targets_row
					_send({
						"class_id": cls_id, "side": side,
						"attack_name": a.attack_name,
						"targets_row_raw": tr_raw,
						"targets_row_int": int(tr_raw),
						"is_front": tr_raw == TerrainDefs.TargetRow.FRONT,
						"is_back": tr_raw == TerrainDefs.TargetRow.BACK,
						"is_any": tr_raw == TerrainDefs.TargetRow.ANY,
						"front_val": int(TerrainDefs.TargetRow.FRONT),
						"back_val": int(TerrainDefs.TargetRow.BACK),
						"any_val": int(TerrainDefs.TargetRow.ANY),
					})
		"inject_unit":
			var iu_class := str(d.get("class_id", "fighter"))
			var iu_level: int = int(d.get("level", 1))
			var iu_row: int = int(d.get("row", 0))
			var iu_sq: Squad = null
			for sq in GameState.player_squads:
				if sq is Squad: iu_sq = sq; break
			if not iu_sq:
				_send({"error": "no player squad on map"})
			else:
				var iu_unit := UnitRegistry.create_unit(iu_class, iu_level)
				if not iu_unit:
					_send({"error": "unknown class_id: %s" % iu_class})
				else:
					var iu_col := 0
					for u in iu_sq.squad_data.units:
						if (u as UnitData).row == iu_row:
							iu_col += 1
					iu_unit.row = iu_row
					iu_unit.col = iu_col
					iu_unit.unit_name = iu_class.capitalize() + str(iu_sq.squad_data.units.size())
					iu_sq.squad_data.units.append(iu_unit)
					_send({"ok": true, "unit": _unit_dict(iu_unit)})
		"give_xp":
			var gx_name := str(d.get("unit", ""))
			var gx_amount: int = int(d.get("amount", 100))
			var gx_unit := _find_unit(gx_name)
			if not gx_unit:
				_send({"error": "unit not found: %s" % gx_name})
			else:
				gx_unit.xp += gx_amount
				var gx_leveled := 0
				while LevelSystem.try_level_up(gx_unit):
					gx_leveled += 1
				_send({"ok": true, "unit": gx_name, "xp": gx_unit.xp, "level": gx_unit.level, "levels_gained": gx_leveled})
		"start_game":
			# Bypass all UI: reset state, create default squads, load Main scene
			GameState.reset()
			var sg_params := MapParams.new()
			sg_params.width = 24
			sg_params.height = 24
			sg_params.map_seed = int(d.get("seed", 42))
			sg_params.num_towns = 4
			sg_params.num_castles = 2
			sg_params.active_factions = [0, 1]
			GameState.pending_map_params = sg_params
			var sg_squad := SquadData.new()
			sg_squad.squad_id = "player_squad_0"
			sg_squad.faction = TerrainDefs.Faction.PLAYER
			var _sg_names := ["Roland", "Gawain", "Sylvia", "Marcus", "Bors"]
			var _sg_classes := ["knight", "fighter", "archer", "fighter", "archer"]
			for sg_i in range(5):
				var sg_unit := UnitRegistry.create_unit(_sg_classes[sg_i], 5)
				if sg_unit:
					sg_unit.unit_name = _sg_names[sg_i]
					sg_unit.faction = TerrainDefs.Faction.PLAYER
					sg_unit.row = 0 if sg_i < 3 else 1
					sg_unit.col = sg_i if sg_i < 3 else sg_i - 3
					if sg_i == 0:
						sg_unit.is_leader = true
					sg_squad.units.append(sg_unit)
			GameState.configured_squads = [sg_squad]
			get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
			_send({"ok": true})
		"capture_town":
			var ct_id := str(d.get("town_id", ""))
			var ct_faction: int = int(d.get("faction", 0))
			if not GameState.town_ownership.has(ct_id):
				_send({"error": "unknown town_id: %s" % ct_id})
			else:
				GameState.town_ownership[ct_id] = ct_faction
				var ct_mgr := get_tree().current_scene.get_node_or_null("MapManager") as MapManager
				if ct_mgr:
					for ct_town in ct_mgr.get_towns():
						if (ct_town as TownNode).town_data.town_id == ct_id:
							(ct_town as TownNode).set_faction(ct_faction)
							break
				_send({"ok": true, "town_id": ct_id, "faction": ct_faction})
		"start_campaign":
			# Set up a campaign run at the given scenario index and go to Main.
			# sc_idx == 0: full reset + fresh default roster.
			# sc_idx  > 0: preserve leveled persistent_roster from previous scenario.
			var sc_idx: int = int(d.get("scenario_idx", 0))
			var permadeath: bool = bool(d.get("permadeath", false))
			var sc_num_squads: int = int(d.get("num_squads", 1))
			const _CampaignDef = preload("res://scripts/campaign/CampaignDef.gd")
			if sc_idx == 0:
				GameState.reset()
			GameState.campaign_run_active = true
			GameState.difficulty_permadeath = permadeath
			if GameState.campaign_def == null:
				var _sc_cd := _CampaignDef.new()
				_sc_cd.build_default()
				GameState.campaign_def = _sc_cd
			GameState.current_scenario_idx = sc_idx
			var sc_campaign = GameState.campaign_def
			# Scenario 0: build the canonical starting roster
			if sc_idx == 0:
				GameState.persistent_roster = []
				for entry in sc_campaign.starting_units:
					var sc_unit := UnitRegistry.create_unit(str(entry["class_id"]), int(entry["level"]))
					if sc_unit:
						sc_unit.unit_name = str(entry["unit_name"])
						sc_unit.faction = TerrainDefs.Faction.PLAYER
						if GameState.persistent_roster.is_empty():
							sc_unit.is_leader = true  # Roland is the squad leader
						GameState.persistent_roster.append(sc_unit)
				GameState.player_gold = int(sc_campaign.starting_gold)
			# Apply map params for the chosen scenario
			if sc_idx < sc_campaign.scenarios.size():
				var sc_def = sc_campaign.scenarios[sc_idx]
				var sc_params := MapParams.new()
				sc_params.map_seed = int(sc_def.map_seed)
				sc_params.width = int(sc_def.map_width)
				sc_params.height = int(sc_def.map_height)
				sc_params.num_towns = int(sc_def.num_towns)
				sc_params.num_castles = int(sc_def.num_castles)
				sc_params.castles_per_faction = int(sc_def.castles_per_faction)
				sc_params.town_liberation_gold = int(sc_def.town_liberation_gold)
				sc_params.town_liberation_unit = sc_def.town_liberation_unit
				var sc_factions: Array[int] = []
				for f in sc_def.active_factions:
					sc_factions.append(int(f))
				sc_params.active_factions = sc_factions
				GameState.pending_map_params = sc_params
				GameState.active_factions = sc_factions
				GameState.enemy_difficulty_mult = float(sc_def.enemy_difficulty_mult)
				GameState._init_default_relations()
				GameState.active_conditions = []
				for wc in sc_def.win_conditions:
					GameState.active_conditions.append(str(wc))
			# For sc_idx > 0, deliver the previous scenario's reward units into persistent_roster.
			# This mirrors what VictoryScreen._deliver_scenario_rewards() does in real play.
			if sc_idx > 0 and sc_idx - 1 < sc_campaign.scenarios.size():
				var prev_sdef = sc_campaign.scenarios[sc_idx - 1]
				for sc_reward in prev_sdef.reward_units:
					var sc_re := sc_reward as Dictionary
					var sc_ru := UnitRegistry.create_unit(str(sc_re.get("class_id", "")), int(sc_re.get("level", 1)))
					if sc_ru:
						sc_ru.unit_name = str(sc_re.get("unit_name", "Unknown"))
						sc_ru.faction = TerrainDefs.Faction.PLAYER
						sc_ru.is_leader = false
						GameState.persistent_roster.append(sc_ru)
			# Build player squads from roster, split into up to num_squads squads.
			if GameState.persistent_roster.size() > 0:
				for sc_u in GameState.persistent_roster:
					(sc_u as UnitData).faction = TerrainDefs.Faction.PLAYER
				GameState.configured_squads = _split_roster(GameState.persistent_roster, sc_num_squads)
			# Clear stale scene-node references so register_squad() starts clean.
			# (GameState.reset() handles this for sc_idx == 0; we do it manually here.)
			if sc_idx > 0:
				GameState.player_squads = []
				GameState.enemy_squads = []
				GameState.reserve_squads = []
				GameState.faction_squads = {}
				GameState.town_ownership = {}
				GameState.current_phase = GameState.Phase.OVERWORLD
			get_tree().paused = false  # clear any stale pause from a previous popup
			get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
			_send({"ok": true, "scenario_idx": sc_idx})
		"get_campaign_state":
			var roster_info: Array = []
			for rc_u in GameState.persistent_roster:
				var rc_ud := rc_u as UnitData
				roster_info.append({"name": rc_ud.unit_name, "class_id": rc_ud.class_id, "level": rc_ud.level, "hp": rc_ud.hp, "max_hp": rc_ud.max_hp, "is_alive": rc_ud.is_alive, "is_wounded": rc_ud.is_wounded})
			_send({
				"campaign_run_active": GameState.campaign_run_active,
				"current_scenario_idx": GameState.current_scenario_idx,
				"difficulty_permadeath": GameState.difficulty_permadeath,
				"campaign_retry": GameState.campaign_retry,
				"roster_size": GameState.persistent_roster.size(),
				"roster": roster_info,
				"player_gold": GameState.player_gold,
			})
		"advance_scenario":
			# Force advance to next scenario without going through VictoryScreen
			if not GameState.campaign_run_active:
				_send({"error": "no active campaign"})
			else:
				GameState.collect_survivors()
				GameState.campaign_retry = false
				GameState.current_scenario_idx += 1
				const _CampaignDefAdv = preload("res://scripts/campaign/CampaignDef.gd")
				if GameState.campaign_def == null:
					var _adv_cd := _CampaignDefAdv.new()
					_adv_cd.build_default()
					GameState.campaign_def = _adv_cd
				var adv_cdef = GameState.campaign_def
				if GameState.current_scenario_idx >= adv_cdef.scenarios.size():
					_send({"error": "already at final scenario"})
				else:
					GameSetupManager.prepare_campaign_scenario(GameState.current_scenario_idx)
					_send({"ok": true, "new_scenario_idx": GameState.current_scenario_idx})
		"apply_battle_damage":
			# Apply HP/alive states from a force_battle attacker_units result to the real roster.
			var ab_states: Array = d.get("units", [])
			for ab_state in ab_states:
				var ab_st := ab_state as Dictionary
				var ab_unit := _find_unit(str(ab_st.get("name", "")))
				if not ab_unit:
					continue
				if not bool(ab_st.get("alive", true)):
					ab_unit.hp = 0
					ab_unit.is_alive = false
				else:
					var ab_ratio := float(ab_st.get("hp", ab_unit.hp)) / float(maxi(int(ab_st.get("max_hp", ab_unit.max_hp)), 1))
					ab_unit.hp = maxi(1, int(float(ab_unit.max_hp) * ab_ratio))
					ab_unit.is_wounded = float(ab_unit.hp) / float(maxi(ab_unit.max_hp, 1)) < 0.25
			_send({"ok": true})
		"heal_roster":
			# Raise all alive roster units to at least (fraction * max_hp).
			# If revive=true, also revive dead units at the given fraction (min 0.25 max_hp).
			# If add=true, add (fraction * max_hp) to current HP instead of using a floor.
			var hr_frac: float = float(d.get("fraction", 1.0))
			var hr_revive: bool = bool(d.get("revive", false))
			var hr_add: bool = bool(d.get("add", false))
			for sq in GameState.player_squads:
				if not (sq is Squad):
					continue
				for unit in (sq as Squad).squad_data.units:
					var u := unit as UnitData
					if not u.is_alive:
						if hr_revive:
							u.is_alive = true
							u.hp = maxi(1, int(float(u.max_hp) * maxf(hr_frac, 0.25)))
							u.is_wounded = float(u.hp) / float(maxi(u.max_hp, 1)) < 0.25
						continue
					if hr_add:
						var hr_amount := int(float(u.max_hp) * hr_frac)
						u.hp = mini(u.max_hp, u.hp + hr_amount)
					else:
						var hr_target := int(float(u.max_hp) * hr_frac)
						u.hp = mini(u.max_hp, maxi(u.hp, hr_target))
					u.is_wounded = float(u.hp) / float(maxi(u.max_hp, 1)) < 0.25
			_send({"ok": true})
		"overworld":
			_send(_build_overworld())
		"move_squad":
			_send(_move_squad(d))
		"set_time_scale":
			var ts_scale: float = clampf(float(d.get("scale", 1.0)), 0.1, 20.0)
			var ts_prev: float = Engine.time_scale
			Engine.time_scale = ts_scale
			_send({"ok": true, "previous": ts_prev, "scale": ts_scale})
		"deploy_squad":
			_send(_deploy_squad(d))
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
	var lmp := GameState.last_map_params
	return {
		"scene": str(scene.name) if scene else "",
		"phase": GameState.current_phase,
		"map_seed": GameState.map_seed,
		"map_width":  lmp.width  if lmp else 0,
		"map_height": lmp.height if lmp else 0,
		"player_gold": GameState.player_gold,
		"player_squads": GameState.player_squads.size(),
		"enemy_squads": GameState.enemy_squads.size(),
		"reserve_squads": GameState.reserve_squads.size(),
		"active_conditions": GameState.active_conditions,
		"town_ownership": GameState.town_ownership,
		"campaign_run_active": GameState.campaign_run_active,
		"current_scenario_idx": GameState.current_scenario_idx,
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

func _find_unit(unit_name: String) -> UnitData:
	for sq in GameState.player_squads:
		if sq is Squad:
			for u in (sq as Squad).squad_data.units:
				if (u as UnitData).unit_name == unit_name:
					return u as UnitData
	for sd in GameState.reserve_squads:
		if sd is SquadData:
			for u in (sd as SquadData).units:
				if (u as UnitData).unit_name == unit_name:
					return u as UnitData
	return null

func _item_dict(item) -> Dictionary:
	return {
		"id": item.item_id, "name": item.display_name, "desc": item.description,
		"type": int(item.item_type), "cost": item.cost,
		"hp": item.hp_bonus, "str": item.str_bonus, "agi": item.agi_bonus,
		"int": item.int_bonus, "def": item.def_bonus, "res": item.res_bonus,
		"heal_pct": item.heal_percent,
	}

func _atk_dict(atk) -> Dictionary:
	var a := atk as AttackDefinition
	return {
		"name": a.attack_name, "type": int(a.damage_type),
		"hits": a.hits, "power": a.power_multiplier,
		"row": int(a.targets_row), "all_row": a.hits_all_in_row,
		"all_col": a.hits_all_in_column, "cond": a.condition_id,
		"is_heal": a.is_heal,
	}

func _class_dict(cls: ClassDefinition) -> Dictionary:
	var cd_front: Array = []
	for a in cls.front_attacks: cd_front.append(_atk_dict(a))
	var cd_back: Array = []
	for a in cls.back_attacks: cd_back.append(_atk_dict(a))
	var cd_skills: Array = []
	for sk in cls.skills:
		cd_skills.append({
			"id": sk.skill_id, "name": sk.display_name, "desc": sk.description,
			"condition": int(sk.condition), "effect": int(sk.effect),
			"power": sk.power, "heal_pct": sk.heal_percent, "dmg_red": sk.damage_reduction,
		})
	return {
		"id": cls.class_id, "name": cls.display_name, "desc": cls.description,
		"base_hp": cls.base_hp, "base_str": cls.base_strength, "base_agi": cls.base_agility,
		"base_int": cls.base_intelligence, "base_def": cls.base_defense, "base_res": cls.base_resistance,
		"move_type": int(cls.movement_type), "move_speed": cls.base_move_speed,
		"can_lead": cls.can_lead, "deploy_cost": cls.deploy_cost,
		"front_attacks": cd_front, "back_attacks": cd_back, "skills": cd_skills,
	}

func _unit_dict(u: UnitData) -> Dictionary:
	var cls := UnitRegistry.get_class_def(u.class_id) as ClassDefinition
	var skills_list: Array = []
	if cls:
		for sk in cls.skills:
			skills_list.append({
				"id": sk.skill_id, "name": sk.display_name,
				"desc": sk.description, "condition": int(sk.condition), "effect": int(sk.effect),
			})
	return {
		"name": u.unit_name, "class_id": u.class_id,
		"class_name": cls.display_name if cls else u.class_id,
		"level": u.level, "hp": u.hp, "max_hp": u.max_hp,
		"str": u.strength, "agi": u.agility, "int": u.intelligence,
		"def": u.defense, "res": u.resistance,
		"held_item": u.held_item, "alive": u.is_alive,
		"leader": u.is_leader, "row": u.row, "col": u.col,
		"xp": u.xp, "xp_to_next": u.xp_to_next,
		"skills": skills_list,
	}

func _squad_dict(sd: SquadData) -> Dictionary:
	var units: Array = []
	for u in sd.units:
		units.append(_unit_dict(u as UnitData))
	return {"id": sd.squad_id, "units": units}

func _send(data: Dictionary) -> void:
	if _client and _client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_client.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())


# ── Overworld automation (real-play bridge) ─────────────────────────────────────

func _squad_id(sq: Squad) -> String:
	return str(sq.get_instance_id())

func _find_live_squad(id: String) -> Squad:
	for sq in GameState.player_squads:
		if sq is Squad and _squad_id(sq as Squad) == id:
			return sq as Squad
	for sq in GameState.enemy_squads:
		if sq is Squad and _squad_id(sq as Squad) == id:
			return sq as Squad
	return null

func _overworld_squad_dict(sq: Squad) -> Dictionary:
	var sd := sq.squad_data
	var alive := 0
	var hp_cur := 0.0
	var hp_max := 0.0
	if sd:
		for u in sd.units:
			var ud := u as UnitData
			if ud.is_alive:
				alive += 1
			hp_cur += float(ud.hp)
			hp_max += float(ud.max_hp)
	var dest := sq.get_destination()
	var squad_id_str := ""
	if sd:
		squad_id_str = sd.squad_id
	return {
		"id": _squad_id(sq),
		"squad_id": squad_id_str,
		"name": str(sq.name),
		"faction": int(sq.faction),
		"x": sq.global_position.x, "z": sq.global_position.z,
		"in_battle": sq.in_battle,
		"is_moving": sq.is_moving(),
		"is_garrisoned": sq.is_garrisoned,
		"dest_x": dest.x, "dest_z": dest.z,
		"alive_count": alive,
		"hp_frac": (hp_cur / hp_max) if hp_max > 0.0 else 0.0,
		"hostile_to_player": GameState.are_hostile(TerrainDefs.Faction.PLAYER, sq.faction),
	}

func _build_overworld() -> Dictionary:
	var scene := get_tree().current_scene
	var map_mgr: MapManager = null
	if scene:
		map_mgr = scene.get_node_or_null("MapManager") as MapManager
	var squads: Array = []
	for sq in GameState.player_squads:
		if sq is Squad:
			squads.append(_overworld_squad_dict(sq as Squad))
	for sq in GameState.enemy_squads:
		if sq is Squad:
			squads.append(_overworld_squad_dict(sq as Squad))
	var towns: Array = []
	if map_mgr:
		for t in map_mgr.get_towns():
			var tn := t as TownNode
			var cap_owner := -2
			if is_instance_valid(tn.occupying_squad) and tn.occupying_squad.faction != tn.faction:
				cap_owner = int(tn.occupying_squad.faction)
			var capturable := tn.faction == TerrainDefs.Faction.NEUTRAL or GameState.are_hostile(TerrainDefs.Faction.PLAYER, tn.faction)
			towns.append({
				"id": tn.town_data.town_id, "faction": int(tn.faction),
				"x": tn.global_position.x, "z": tn.global_position.z,
				"type": int(tn.town_data.town_type),
				"is_stronghold": tn.town_data.is_stronghold(),
				"capture_ticks": tn.capture_ticks,
				"capture_turns": tn.town_data.capture_turns,
				"capture_owner": cap_owner,
				"garrisoned": is_instance_valid(tn.garrisoned_squad),
				"capturable_by_player": capturable,
			})
	var winner := -2
	if GameState.current_phase == GameState.Phase.VICTORY:
		winner = int(TerrainDefs.Faction.PLAYER)
	elif GameState.current_phase == GameState.Phase.DEFEAT:
		winner = -3
	return {
		"phase": int(GameState.current_phase),
		"paused": get_tree().paused,
		"squads": squads,
		"towns": towns,
		"active_conditions": GameState.active_conditions,
		"town_ownership": GameState.town_ownership,
		"winner": winner,
	}

func _move_squad(d: Dictionary) -> Dictionary:
	var sq := _find_live_squad(str(d.get("id", "")))
	if not sq:
		return {"error": "squad not found: %s" % str(d.get("id", ""))}
	var scene := get_tree().current_scene
	var map_mgr: MapManager = null
	if scene:
		map_mgr = scene.get_node_or_null("MapManager") as MapManager
	var dest := Vector3.ZERO
	if d.has("town_id"):
		if not map_mgr:
			return {"error": "no MapManager"}
		var found: TownNode = null
		for t in map_mgr.get_towns():
			if (t as TownNode).town_data.town_id == str(d.get("town_id", "")):
				found = t as TownNode
				break
		if not found:
			return {"error": "town not found: %s" % str(d.get("town_id", ""))}
		dest = found.global_position
	elif d.has("grid_x") and d.has("grid_y"):
		if not map_mgr:
			return {"error": "no MapManager"}
		dest = map_mgr.grid_to_world(Vector2i(int(d.get("grid_x", 0)), int(d.get("grid_y", 0))))
	elif d.has("x") and d.has("z"):
		dest = Vector3(float(d.get("x", 0.0)), sq.global_position.y, float(d.get("z", 0.0)))
	else:
		return {"error": "move_squad needs town_id, grid_x/grid_y, or x/z"}
	if sq.is_garrisoned:
		var gt := sq.garrison_town
		if gt:
			gt.clear_garrison()
		sq.ungarrison()
	sq.set_destination(dest)
	return {"ok": true, "id": _squad_id(sq), "dest_x": dest.x, "dest_z": dest.z}


# ── Multi-squad harness helpers ─────────────────────────────────────────────────

func _split_roster(roster: Array, num_squads: int) -> Array[SquadData]:
	# Cap so each squad keeps ~2+ units (a player wouldn't field 1-unit squads).
	var n := clampi(num_squads, 1, maxi(1, int(roster.size() / 2.0)))
	var squads: Array[SquadData] = []
	for i in range(n):
		var sd := SquadData.new()
		sd.squad_id = "player_squad_%d" % i
		sd.faction = TerrainDefs.Faction.PLAYER
		squads.append(sd)
	var leaders: Array = []
	var others: Array = []
	for u in roster:
		var ud := u as UnitData
		ud.is_leader = false
		var cls := UnitRegistry.get_class_def(ud.class_id) as ClassDefinition
		if cls and cls.can_lead:
			leaders.append(ud)
		else:
			others.append(ud)
	for sq in squads:
		if leaders.is_empty():
			break
		var ldr := leaders.pop_front() as UnitData
		ldr.is_leader = true
		(sq as SquadData).units.append(ldr)
	var pool: Array = leaders + others
	var idx := 0
	for u in pool:
		var placed := false
		for _t in range(squads.size()):
			var sq := squads[idx % squads.size()] as SquadData
			idx += 1
			if sq.units.size() < 6:
				sq.units.append(u)
				placed = true
				break
		if not placed:
			break
	var result: Array[SquadData] = []
	for sq in squads:
		var s := sq as SquadData
		if s.units.is_empty():
			continue
		var has_leader := false
		for u in s.units:
			if (u as UnitData).is_leader:
				has_leader = true
				break
		if not has_leader:
			(s.units[0] as UnitData).is_leader = true
		result.append(s)
	return result

func _deploy_squad(d: Dictionary) -> Dictionary:
	var scene := get_tree().current_scene
	if not scene:
		return {"error": "no scene"}
	var ctrl := scene.get_node_or_null("Squads") as SquadController
	var map_mgr := scene.get_node_or_null("MapManager") as MapManager
	if not ctrl or not map_mgr:
		return {"error": "not in Main scene"}
	var town: TownNode = null
	if d.has("town_id"):
		for t in map_mgr.get_towns():
			if (t as TownNode).town_data.town_id == str(d.get("town_id", "")):
				town = t as TownNode
				break
		if not town:
			return {"error": "town not found: %s" % str(d.get("town_id", ""))}
	else:
		town = map_mgr.get_hq(TerrainDefs.Faction.PLAYER)
		if not town:
			return {"error": "no player HQ"}
	var free := bool(d.get("free", false))
	var which = d.get("index", "all")
	var deployed: Array = []
	var reserves: Array = GameState.reserve_squads.duplicate()
	if str(which) == "all":
		for sd in reserves:
			if ctrl.deploy_reserve(sd as SquadData, town, free):
				deployed.append((sd as SquadData).squad_id)
			else:
				break
	else:
		var i := int(which)
		if i >= 0 and i < reserves.size():
			if ctrl.deploy_reserve(reserves[i] as SquadData, town, free):
				deployed.append((reserves[i] as SquadData).squad_id)
	return {"ok": true, "deployed": deployed, "gold": GameState.player_gold,
		"reserve_remaining": GameState.reserve_squads.size()}
