# 11 — Implementation Order

This document tells Claude Code the recommended build order. Each milestone is self-contained and testable before the next begins. Do not skip ahead — later milestones depend on earlier ones being stable.

---

## Milestone 1 — Project Skeleton

**Goal**: A runnable Godot project with folder structure and autoloads registered.

Tasks:
- [ ] Create the folder structure from `01_PROJECT_STRUCTURE.md`
- [ ] Create stub `GameState.gd`, `UnitRegistry.gd`, `BattleManager.gd` autoloads (empty `_ready` functions, correct class names)
- [ ] Register all three autoloads in `project.godot`
- [ ] Create `Main.tscn` with a `Node3D` root, a placeholder `Camera3D` pointing down
- [ ] Create all enums in `TerrainDefs.gd` (`TerrainType`, `MovementType`, `DamageType`, `TownType`, `Faction`)
- [ ] Verify project runs without errors

**Test**: Project opens, no errors in output, camera renders an empty 3D view.

---

## Milestone 2 — Data Model

**Goal**: All Resource classes exist and can be instantiated.

Tasks:
- [ ] Implement `UnitData.gd` (Resource subclass, all exported fields from §02)
- [ ] Implement `ClassDefinition.gd` (Resource subclass)
- [ ] Implement `AttackDefinition.gd` (Resource subclass)
- [ ] Implement `PromotionRequirement.gd` (Resource subclass)
- [ ] Implement `SquadData.gd` with `get_unit_at()`, `get_leader()`, `get_alive_units()`, `recalculate_speed()`
- [ ] Implement `TownData.gd` (Resource subclass)
- [ ] Implement `BattleResult.gd` and `BattleAction.gd` (Resource subclasses)
- [ ] Implement `TerrainDefs.gd` with all enums and the `get_speed(movement_type, terrain)` lookup table

**Test**: In `GameState._ready()`, create one of each resource type and print its default values. No errors.

---

## Milestone 3 — Unit Registry and Class Data

**Goal**: All 8 V1 unit classes exist as `.tres` files and can be loaded.

Tasks:
- [ ] Create `res://data/classes/fighter.tres` through `gryphon_rider.tres` using the stat values from §04
- [ ] Implement `UnitRegistry.gd`:
  - `_ready()` loads all `.tres` files from `res://data/classes/`
  - `get_class(class_id: String) -> ClassDefinition`
  - `create_unit(class_id: String, level: int) -> UnitData` — creates a unit with stats scaled to the given level (apply `level-1` rounds of `apply_stat_growth`)
- [ ] Implement the leveling functions in a `LevelSystem.gd` (or inline in UnitRegistry):
  - `try_level_up(unit: UnitData) -> bool`
  - `apply_stat_growth(unit: UnitData) -> void`
  - `check_promotion(unit: UnitData) -> String`

**Test**: Print `UnitRegistry.create_unit("knight", 5)` stats. Verify HP, STR etc. are higher than base level-1 values.

---

## Milestone 4 — Map Generation

**Goal**: A playable 3D map appears when the game runs.

Tasks:
- [ ] Implement `MapGenerator.gd` with the noise-based terrain generation from §03
  - Heightmap → terrain type assignment
  - Forest overlay pass
  - Continent flood-fill guarantee
- [ ] Implement `MapCell.gd` and `MapCell.tscn`:
  - `StaticBody3D` + `BoxMesh` + `CollisionShape3D`
  - Height and color vary by terrain type
- [ ] `MapManager.gd` owns the grid; implement `get_cell()`, `get_terrain()`, `world_to_grid()`, `grid_to_world()`
- [ ] Implement town/castle placement rules from §03
- [ ] Implement `TownNode.gd` and `TownNode.tscn` with placeholder primitive meshes
- [ ] Add `NavigationRegion3D` to the map, bake nav mesh for ground units
- [ ] Wire `MapManager` into `Main.tscn`
- [ ] Camera panning and zoom (§05 camera controls)

**Test**: Run game. See a 32×32 terrain grid with colored cells, some towns/castles visible. Camera pans and zooms.

---

## Milestone 5 — Squads on the Map

**Goal**: Squads appear on the map and can be moved.

Tasks:
- [ ] Implement `Squad.gd` and `Squad.tscn`:
  - `CharacterBody3D` with colored capsule mesh (faction color)
  - `NavigationAgent3D`
  - `Label3D` for leader name
  - `Area3D` for collision detection
  - Movement loop from §05
  - `update_speed_for_current_cell()` using `TerrainDefs`
- [ ] Implement player squad selection (left-click → highlight ring)
- [ ] Implement move order (right-click with squad selected → set nav destination)
- [ ] Implement `SquadInspector.tscn` + `SquadInspector.gd` (right panel, opens on squad select)
- [ ] Spawn the 2 hardcoded player squads in reserve (not on map yet)
- [ ] Spawn 4 AI squads at enemy towns
- [ ] Implement flying unit movement (straight-line lerp, bypasses navmesh)

**Test**: Click a squad, right-click a destination, squad moves there. Inspector panel shows unit slots. Flying squad ignores terrain pathing.

---

## Milestone 6 — Town Interaction and Capture

**Goal**: Towns can be captured and used as deploy points.

Tasks:
- [ ] Implement `TownMenu.gd` and `TownMenu.tscn` (§09)
- [ ] Wire left-click on town → open TownMenu
- [ ] Implement garrison logic (squad arrives at friendly town → garrison)
- [ ] Implement capture timer and progress bar (§07)
- [ ] Implement `GameState.town_ownership` updates and `town_captured` signal
- [ ] Implement deploy from town (select reserve squad → spawns at town)
- [ ] Implement faction color changes on capture (Tween)
- [ ] Implement retreat logic (nearest friendly town after losing battle — teleport for now)

**Test**: Move a player squad to a neutral town. Progress bar fills. Town changes color. Open town menu. Deploy a reserve squad.

---

## Milestone 7 — Battle System

**Goal**: Squads that collide fight a battle and the result is applied.

Tasks:
- [ ] Implement `BattleResolver.gd` — pure logic, no nodes (§06):
  - `resolve(attacker, defender) -> BattleResult`
  - Round loop, attack order by agility
  - Target selection by `targets_row`
  - Damage formula (physical and magical)
  - Hit/miss calculation
  - Death handling, leader fall
  - XP calculation
- [ ] Implement `BattleManager.gd` autoload:
  - Listen for `squad_collided_with_enemy`
  - Pause tree, call resolver, instantiate BattleScene, apply result
- [ ] Implement `BattleScene.tscn` + `BattleAnimator.gd`:
  - Two 3×2 grids of unit slots (colored cubes)
  - Action log text box
  - Playback of `action_log` with tweened damage numbers
  - Battle result banner
  - "Continue" button resumes overworld
- [ ] Implement `SkillSystem.gd` with V1 stub conditions
- [ ] Wire level-up and promotion into post-battle flow

**Test**: Two squads collide. Battle scene appears. Actions play out. Continue returns to map. Dead units are gone, HP updated, XP granted.

---

## Milestone 8 — AI

**Goal**: The enemy faction actively plays against the player.

Tasks:
- [ ] Implement `AIFaction.gd` with tick loop (§08)
- [ ] Implement objective priority logic (defend HQ, recapture, capture neutral, attack player, patrol)
- [ ] Wire AI squads to use the same `squad.set_destination()` interface as player orders
- [ ] Spawn AI squads from pre-defined templates (§08)
- [ ] Verify AI doesn't issue orders while in battle (phase check)

**Test**: Start game without issuing any player orders. Watch AI squads move toward towns and attack player HQ.

---

## Milestone 9 — Win/Loss Conditions

**Goal**: Game ends when conditions are met.

Tasks:
- [ ] Implement `check_win_conditions()` in `GameState` (§10)
- [ ] Implement `VictoryScreen.tscn` and `VictoryScreen.gd`
- [ ] Wire "Play Again" to reset and regenerate the map
- [ ] Implement defeat condition (player HQ captured)
- [ ] Verify both factions can win

**Test**: Let the AI capture the player HQ. Defeat screen appears. Click Play Again. New map generates.

---

## Milestone 10 — Polish Pass

**Goal**: Visual feedback and quality-of-life touches.

Tasks:
- [ ] HUD minimap (§09)
- [ ] Squad path line drawn on map (dotted line to destination)
- [ ] "Can't go there" indicator on invalid right-click
- [ ] Squad wipe particle puff (simple `GPUParticles3D`)
- [ ] Screen flash on battle trigger
- [ ] Unit Detail Popup (click a slot in SquadInspector)
- [ ] Camera clamping to map bounds
- [ ] Capture progress bar polished (§07)
- [ ] Level-up popup in battle result banner

**Test**: Play through a full game start to finish. Check all feedback elements fire correctly.

---

## Notes for Claude Code

- **Work milestone by milestone.** Do not begin Milestone 5 until Milestone 4 tests pass.
- **Prefer GDScript** for all logic. No C# in V1.
- **Do not use `@tool` scripts** unless specifically needed for editor tooling.
- **All signals must be documented with `signal` declarations** at the top of each script before use.
- **No magic numbers in logic scripts** — use constants or the values from `TerrainDefs.gd`.
- **BattleResolver must be a pure function** — no `await`, no scene tree access, no signals. Input → output only.
- **When in doubt about a design detail not covered here**, implement the simplest version and add a `# TODO:` comment.
- **Test each milestone in the Godot editor** using the built-in debugger before proceeding.
