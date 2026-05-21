# V2-01 — Fixes and Polish (Complete Before New Features)

These are V1 stubs and bugs. Fix them first — they make the existing game feel broken. Most are small.

---

## Fix 1 — Terrain Speed During Movement (HIGH PRIORITY)

**File**: `scripts/squads/Squad.gd` — `_update_terrain_speed()`

**Current state**: Called every `_physics_process` frame but has a `# TODO` and does nothing.

**Fix**:
```gdscript
func _update_terrain_speed() -> void:
    if not squad_data or not _map_manager:
        return
    var grid := _map_manager.world_to_grid(global_position)
    var terrain := _map_manager.get_terrain(grid.x, grid.y)
    squad_data.recalculate_speed(terrain)
    # Clamp: flying units have a floor speed so they're never stuck
    if _is_flying:
        squad_data.move_speed = max(squad_data.move_speed, 1.0)
```

Also update `Squad._ready()` / `setup()` to cache a reference to `MapManager`:
```gdscript
var _map_manager: MapManager = null

func setup(data: SquadData) -> void:
    # ... existing code ...
    _map_manager = get_tree().current_scene.get_node_or_null("MapManager") as MapManager
```

**Impact**: Squads now actually slow down in forest, stop at water/mountain edges.

---

## Fix 2 — Player Squad Faction Color (TRIVIAL)

**File**: `scripts/squads/Squad.gd` — `_faction_color()`

**Current state**: Returns `Color(1.0, 0.0, 1.0)` (magenta) for PLAYER. This is a debug placeholder.

**Fix**:
```gdscript
func _faction_color(f: int) -> Color:
    if f == TerrainDefs.Faction.PLAYER:
        return Color(0.20, 0.40, 0.90)   # Blue
    if f == TerrainDefs.Faction.ENEMY:
        return Color(0.90, 0.20, 0.20)   # Red
    return Color(0.60, 0.60, 0.60)       # Neutral grey
```

---

## Fix 3 — Minimap Wiring (MEDIUM)

**File**: `scripts/ui/MinimapPanel.gd`

**Current state**: The script exists but is not connected to `MapManager` — it draws nothing.

**Fix**: In `MinimapPanel._ready()`, get a reference to `MapManager` and pull the terrain grid. Draw colored pixels per cell using a `draw_rect` in `_draw()` or render to a `Texture2D` via an `Image`.

Recommended approach — generate a minimap `Image` once after the map is built, then display it as a `TextureRect`:

```gdscript
# MinimapPanel.gd
const MINIMAP_SIZE := 200   # pixels

var _map_tex: ImageTexture = null
var _squad_dots: Array = []  # [{pos: Vector2, color: Color}]

func _ready() -> void:
    call_deferred("_build_minimap")

func _build_minimap() -> void:
    var map_mgr := get_tree().current_scene.get_node_or_null("MapManager") as MapManager
    if not map_mgr:
        return
    var img := Image.create(map_mgr.map_width, map_mgr.map_height, false, Image.FORMAT_RGB8)
    for x in range(map_mgr.map_width):
        for z in range(map_mgr.map_height):
            img.set_pixel(x, z, _terrain_color(map_mgr.get_terrain(x, z)))
    _map_tex = ImageTexture.create_from_image(img)
    # Set on the TextureRect child
    $TextureRect.texture = _map_tex
    # Connect to town_captured to update dots
    for town in map_mgr.get_towns():
        town.town_captured.connect(_on_town_captured.bind(town))

func _process(_delta: float) -> void:
    queue_redraw()  # Update squad dot positions each frame

func _draw() -> void:
    # Draw the static terrain texture
    if _map_tex:
        draw_texture_rect(_map_tex, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)
    # Draw squad dots on top
    # ... (convert world pos → minimap pixel, draw small rects)

func _terrain_color(terrain: TerrainDefs.TerrainType) -> Color:
    match terrain:
        TerrainDefs.TerrainType.WATER:    return Color(0.23, 0.42, 0.63)
        TerrainDefs.TerrainType.PLAINS:   return Color(0.78, 0.84, 0.35)
        TerrainDefs.TerrainType.GRASS:    return Color(0.29, 0.55, 0.25)
        TerrainDefs.TerrainType.FOREST:   return Color(0.18, 0.36, 0.16)
        TerrainDefs.TerrainType.MOUNTAIN: return Color(0.55, 0.55, 0.55)
        TerrainDefs.TerrainType.ROAD:     return Color(0.76, 0.66, 0.42)
        _: return Color.BLACK
```

Town dots: small colored squares (2×2 px) at town grid positions, faction-colored. Update on `town_captured`.
Squad dots: 3×3 px squares, drawn in `_draw()` using live `GameState.player_squads` and `GameState.enemy_squads` positions.

---

## Fix 4 — Squad Path Line (MEDIUM)

**File**: `scripts/squads/Squad.gd`

**Current state**: No visual feedback for move destination.

**Fix**: Add a `Line3D` (or MeshInstance3D with `ImmediateMesh`) that draws from squad position to destination while moving. Use a dotted appearance by placing small sphere meshes along the path, or simply draw a straight line.

Simple implementation:
```gdscript
var _path_line: MeshInstance3D = null

func set_destination(world_pos: Vector3) -> void:
    _destination = Vector3(world_pos.x, global_position.y, world_pos.z)
    _is_moving = true
    if not _is_flying and _nav_agent:
        _nav_agent.target_position = _destination
    _update_path_line()

func _update_path_line() -> void:
    if _path_line:
        _path_line.queue_free()
        _path_line = null
    if not _is_moving:
        return
    # Draw a thin box from current pos to destination
    var diff := _destination - global_position
    diff.y = 0.0
    var length := diff.length()
    if length < 0.1:
        return
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.06, 0.06, length)
    _path_line = MeshInstance3D.new()
    _path_line.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = _faction_color(faction).lightened(0.4)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _path_line.set_surface_override_material(0, mat)
    _path_line.position = (global_position + _destination) * 0.5
    _path_line.position.y = 0.3
    _path_line.look_at(_destination + Vector3.UP * 0.001, Vector3.UP)
    get_parent().add_child(_path_line)

func _stop_moving() -> void:
    _is_moving = false
    velocity = Vector3.ZERO
    if _path_line:
        _path_line.queue_free()
        _path_line = null
    squad_arrived.emit(self, _destination)
```

---

## Fix 5 — "Can't Go There" Indicator (SMALL)

**File**: `scripts/squads/SquadController.gd` — `_handle_right_click()`

**Current state**: Impassable terrain clicks are silently `return`ed with a `# TODO` comment.

**Fix**: Add a brief world-space label or colored flash at the click position:
```gdscript
if spd == 0.0:
    _show_cant_move_indicator(world_pos)
    return

func _show_cant_move_indicator(world_pos: Vector3) -> void:
    var lbl := Label3D.new()
    lbl.text = "✕"
    lbl.modulate = Color(1.0, 0.2, 0.2)
    lbl.font_size = 32
    lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    lbl.position = world_pos + Vector3(0, 1.5, 0)
    get_parent().add_child(lbl)
    var tween := create_tween()
    tween.tween_property(lbl, "modulate:a", 0.0, 0.7)
    tween.tween_callback(lbl.queue_free)
```

---

## Fix 6 — Battle Result Shows Level-Ups (MEDIUM)

**File**: `scripts/battle/BattleAnimator.gd` — `_show_result()`

**Current state**: Shows total XP earned but level-ups and promotions happen silently in `BattleManager._grant_xp()` without being communicated to the animator.

**Fix**: After `BattleManager` applies XP and levels, it should build a list of level-up and promotion events and pass them to the scene. Two approaches:

**Option A** — Add `level_up_events: Array[Dictionary]` to `BattleResult`:
```gdscript
# In BattleResult.gd
@export var level_up_events: Array[Dictionary] = []
# Each dict: {"unit_name": String, "new_level": int, "promoted_to": String}
```

Populate in `BattleManager._grant_xp()`:
```gdscript
while LevelSystem.try_level_up(unit):
    var ev := {"unit_name": unit.unit_name, "new_level": unit.level, "promoted_to": ""}
    var promo := LevelSystem.check_promotion(unit)
    if promo != "":
        LevelSystem.apply_promotion(unit, promo)
        ev["promoted_to"] = promo
    _current_result.level_up_events.append(ev)
```

Then in `BattleAnimator._show_result()`:
```gdscript
for ev in _result.level_up_events:
    var line: String = "%s → Level %d!" % [ev["unit_name"], ev["new_level"]]
    if ev["promoted_to"] != "":
        line += "  Promoted to %s!" % ev["promoted_to"].capitalize()
    _log_line("[color=gold]%s[/color]" % line)
```

---

## Fix 7 — Dead Code Cleanup (TRIVIAL)

- Remove `SquadController._spawn_enemy_squads()` — enemy spawning is done by `AIFaction._initial_spawn()` and `SquadController`'s version is never called.
- Remove the `movement_type` property stub in `SquadData` if it's not being set (verify it's populated correctly from leader's class).

---

## Fix 8 — SquadData.movement_type Population

**File**: `scripts/units/SquadData.gd`

**Current state**: `movement_type` field exists but `recalculate_speed()` is only called with PLAINS terrain at spawn. The `movement_type` property needs to be set when the squad is configured.

**Fix**: In `SquadData`, derive `movement_type` from the leader:
```gdscript
var movement_type: TerrainDefs.MovementType:
    get:
        var leader := get_leader()
        if leader:
            var cls := UnitRegistry.get_class_def(leader.class_id) as ClassDefinition
            if cls:
                return cls.movement_type
        return TerrainDefs.MovementType.INFANTRY
```

This makes it a computed property so it always reflects the current leader's class, including after promotion.
