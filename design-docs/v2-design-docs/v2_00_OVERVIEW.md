# V2 Design Documents — Overview & Gap Analysis

## What V1 Actually Built (Audit)

After reviewing every script in `migs-battle-main`, here is the honest state of V1:

### ✅ Solid and Complete
- **MapGenerator**: Full simplex noise terrain, forest overlay, continent guarantee, town placement, A* road pass. Well-structured.
- **MapManager**: Cell spawning, town spawning, navmesh baking, all public API (`get_terrain`, `world_to_grid`, `grid_to_world`, `get_towns`, `get_hq`). Solid.
- **TerrainDefs**: All enums, speed table, terrain visual data. Complete.
- **UnitRegistry**: Loads `.tres` files, falls back to `_build_default_classes()`, `create_unit()` with proper level scaling. Well done.
- **All 8 ClassDefinitions**: Correctly defined in both `.tres` files and `_build_default_classes()`. Promotions wired.
- **LevelSystem**: `try_level_up`, `apply_stat_growth`, `check_promotion`, `apply_promotion`. Correct logic.
- **BattleResolver**: Full agility-sorted round loop, target selection by row, damage formula with hit/miss, kill handling, XP calculation. Clean pure-logic design.
- **BattleAnimator**: Full UI construction, grid playback, damage numbers, HP bars, grey-out on death, result banner. Works.
- **BattleManager**: Correct pause/resume cycle, result application, XP grant with level-up chain, leader-death retreat, wipe handling. Good.
- **TownNode**: Capture timer, garrison, faction color tweening, capture label, selection area. Complete.
- **Squad**: Navigation, flying bypass, terrain speed update stub, garrison/ungarrison, detection area collision. Good.
- **SquadController**: Left/right click handling, squad selection, deploy from reserve, ungarrison, squad wiring, battle trigger delegation. Complete.
- **AIFaction**: Tick loop, all 5 objective types, 4 squad templates, initial spawn. Functional.
- **GameState**: Phase enum, win condition checks (HQ and all-strongholds), `reset()`. Complete.
- **TownMenu**: Friendly and read-only views, deploy, ungarrison, close. Works.
- **SquadInspector**: 6-slot grid, HP bars, star for leader, movement/speed labels, UnitDetailPopup link. Complete.
- **VictoryScreen**: Victory/defeat text, play again (reload scene), quit. Works.

### ⚠️ Stubbed / Incomplete in V1
- **`Squad._update_terrain_speed()`**: Has a `# TODO` comment — the squad queries terrain while moving but never actually updates `squad_data.move_speed` mid-movement. Speed is set once at spawn using PLAINS. Squads don't actually slow down in forest.
- **`SquadController._spawn_enemy_squads()`**: Defined but **never called** — enemy squads are spawned by `AIFaction._initial_spawn()` instead. The `SquadController` version is dead code.
- **`SquadController._handle_left_click()`**: Only handles `Squad` collider hits; clicking on town nodes fires via `Area3D.input_event` in `TownNode` directly. Works but inconsistent.
- **`BattleAnimator._show_result()`**: Shows XP per unit but **does not show level-ups or promotions** that occurred — they happen silently in `BattleManager._grant_xp()`.
- **`SkillSystem`**: Only a 2-condition stub (`hp_below_50`, `first_round_only`). No real skill system.
- **`Squad._faction_color()`**: Returns magenta for PLAYER (debug color left in), not the intended blue.
- **No terrain speed update during movement**: `_update_terrain_speed()` is called every physics frame but does nothing.
- **No squad path visualization**: Move order destination is set but no line is drawn.
- **No "can't go there" indicator**: Impassable terrain right-clicks are silently ignored.
- **No minimap data connection**: `MinimapPanel.gd` exists but is not wired to `MapManager` — it draws nothing.
- **No army builder**: Starting squads are hardcoded in `SquadController._build_player_squad()`. Player can't configure squads before battle.
- **No title screen functionality**: `TitleScreen.tscn` is the main scene but `TitleScreen.gd` just has a "Start" button with `get_tree().change_scene_to_file()`.
- **No map size/seed config**: Generator params are `@export` vars on `MapManager` but there's no UI to set them before generation.
- **No save/load**.
- **No gold/economy system**.
- **No alignment/morale system**.
- **No aquatic movement** (enum exists, terrain cost table exists, no units use it).
- **No multi-faction support** (Faction enum only has PLAYER/ENEMY/NEUTRAL).

---

## V2 Document Index

| File | Contents |
|------|----------|
| `v2_00_OVERVIEW.md` | This file |
| `v2_01_FIXES_AND_POLISH.md` | Bug fixes and V1 stubs to complete before V2 features |
| `v2_02_ARMY_BUILDER.md` | Pre-battle squad composition UI |
| `v2_03_GOLD_ECONOMY.md` | Gold income, deployment costs, shop system |
| `v2_04_SKILL_SYSTEM.md` | Full skill/condition system (UO-inspired) |
| `v2_05_NEW_UNIT_CLASSES.md` | New classes, aquatic type, expanded promotion trees |
| `v2_06_MULTI_FACTION.md` | Multiple AI factions, diplomacy, alliance system |
| `v2_07_MAP_CONFIG_AND_SEED_UI.md` | Map settings screen, seed replay, map size options |
| `v2_08_SAVE_LOAD.md` | Save/load game state to disk |
| `v2_09_IMPLEMENTATION_ORDER.md` | Build order for V2 features |

## V2 Philosophy

V1 built the correct foundation. V2 adds **depth and replayability**. The priority order is:

1. **Fix V1 stubs first** (terrain speed, minimap, path line, battle result level-up display) — these are low-effort and make the existing game feel complete.
2. **Army Builder** — without this the player has no agency before deployment. High impact.
3. **Gold Economy** — gives strategic meaning to town capture beyond just objectives.
4. **Skill System** — makes battles more interesting and differentiated.
5. **New Classes + Aquatic** — expands roster and uses the already-stubbed AQUATIC type.
6. **Multi-Faction** — biggest structural change; save for last.
7. **Map Config UI + Save/Load** — quality of life; straightforward.
