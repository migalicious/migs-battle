# V2-08 — Implementation Order

Complete each milestone in order. Do not start a later milestone until earlier ones are stable and testable. Each milestone builds on V1's existing codebase — don't rewrite what works.

---

## Milestone V2-1 — V1 Fixes (Required First)

These are bug fixes and stubs that must be completed before any V2 features are added. The existing game is broken in subtle ways without them.

**Tasks** (from `v2_01_FIXES_AND_POLISH.md`):
- [ ] Fix `Squad._update_terrain_speed()` — actually update `squad_data.move_speed` based on current terrain
- [ ] Fix player squad color — magenta → blue
- [ ] Fix `SquadData.movement_type` — make it a computed property from the leader's class
- [ ] Remove dead code: `SquadController._spawn_enemy_squads()` (never called)
- [ ] Wire `MinimapPanel` to `MapManager` — generate terrain image, draw squad dots
- [ ] Add path line from squad to destination (box mesh between current pos and target)
- [ ] Add "can't go there" indicator (Label3D that fades out)
- [ ] Add level-up/promotion events to `BattleResult` and display them in `BattleAnimator._show_result()`

**Test**: Play a full game. Squads visually slow in forest. Player squads are blue. Minimap shows terrain. A line appears from squad to destination when ordered to move. Battle result shows "Merlin → Level 7! Promoted to Sorcerer!" if it happens.

---

## Milestone V2-2 — Map Config Screen

**From**: `v2_07_MAP_CONFIG_AND_SAVE_LOAD.md` (first half only — save/load comes later)

**Tasks**:
- [ ] Create `MapConfigScreen.tscn` and `MapConfigScreen.gd`
- [ ] Add map size selector (Small/Medium/Large), seed field, towns slider, castles slider
- [ ] Add win condition dropdown (HQ Capture / All Strongholds / Both)
- [ ] Wire "Generate Map" button to emit `config_ready` signal
- [ ] Create `GameSetupManager.gd` to orchestrate TitleScreen → MapConfig → Game flow
- [ ] Store last used seed in `user://map_config.cfg`, show "Replay" button
- [ ] Show seed on `VictoryScreen` with Copy button

**Test**: From title screen, open config. Change map size to Small. Enter seed 12345. Click Generate. Map is 24×24. Enter same seed again — same map. Change win condition to "All Strongholds" — verify it changes the active condition in `GameState`.

---

## Milestone V2-3 — Army Builder

**From**: `v2_02_ARMY_BUILDER.md`

**Tasks**:
- [ ] Create `ScenarioData.gd` resource with starting unit list
- [ ] Create the V2 starter scenario as a `.tres` file (18 units)
- [ ] Create `ArmyBuilderScreen.tscn` and `ArmyBuilderScreen.gd`
  - [ ] Left panel: squad tabs with 3×2 slot grid
  - [ ] Right panel: roster of unassigned units
  - [ ] Click-to-assign interaction
  - [ ] Auto-leader detection
  - [ ] Validation: disabled Start if no valid leader
- [ ] Wire `GameSetupManager` to show `ArmyBuilderScreen` after map config
- [ ] Update `SquadController._spawn_player_squads()` to read from `GameState.configured_squads`
- [ ] Show `UnitDetailPopup` on roster unit hover

**Test**: Configure a squad with a Knight as leader, two Fighters and two Archers. Start game. Those exact units appear as the player squad. The second configured squad is in reserve and can be deployed from the HQ.

---

## Milestone V2-4 — Gold Economy

**From**: `v2_03_GOLD_ECONOMY.md`

**Tasks**:
- [ ] Add `player_gold`, `enemy_gold`, `gold_tick_interval` to `GameState`
- [ ] Add `_collect_income()` tick in `GameState._process()`
- [ ] Populate `TownData.income` values in `MapManager._spawn_towns()`
- [ ] Set `deploy_cost` on all 8 existing `ClassDefinition`s in `UnitRegistry`
- [ ] Add deploy cost check and deduction in `SquadController._on_deploy_requested()`
- [ ] Add gold display to `TopBar` (with gold flash animation)
- [ ] Show deploy cost in `TownMenu` reserve squad list
- [ ] Create `ItemDefinition.gd` resource
- [ ] Create `ItemRegistry.gd` autoload, register in `project.godot`
- [ ] Create 7 starter item `.tres` files in `res://data/items/`
- [ ] Add `held_item` to `UnitData`
- [ ] Add `player_inventory: Dictionary` to `GameState`
- [ ] Update `BattleResolver._calculate_damage()` to use `_get_stat()` with item bonuses
- [ ] Add `_apply_consumables()` to `BattleResolver.resolve()` (fires before round 1)
- [ ] Add Shop tab to `TownMenu` (buy items, equip to units)

**Test**: Start with 100 gold. Capture a Town (income 15g/tick). After 10 seconds, gold increases by 15. Try to deploy a squad — if cost > gold, see "Need Xg!" label. Buy an Iron Shield (+3 DEF) for 80g. Equip it to a unit. Verify in battle that unit takes less physical damage.

---

## Milestone V2-5 — Skill System

**From**: `v2_04_SKILL_SYSTEM.md`

**Tasks**:
- [ ] Create `SkillDefinition.gd` resource with all enums
- [ ] Add `skills: Array[SkillDefinition]` to `ClassDefinition`
- [ ] Add skills for all 8 existing classes inline in `UnitRegistry._build_default_classes()`
- [ ] Expand `SkillSystem.gd` with full `condition_met()` function
- [ ] Update `BattleResolver._run_round()` to pass `allies` arrays to `_execute_attacks()`
- [ ] Update `BattleResolver._execute_attacks()` to build context and fire post-attack skills
- [ ] Add `GUARD` skill handling (modify `dmg` before `_apply_damage()`)
- [ ] Add `HEAL_ALLY` handling (find lowest-HP ally, restore HP)
- [ ] Add `EXTRA_ATTACK` handling (call `_apply_damage()` a second time)
- [ ] Add `HEAL` and `SKILL` to `BattleAction.ActionType`
- [ ] Update `BattleAnimator._process_action()` to handle HEAL (green float number)
- [ ] Update `UnitDetailPopup` to show skills section

**Test**: Field a Paladin. In battle, check that the log shows "Holy Aura — [ally] healed for Xhp" each round. Field a low-HP Fighter and verify "Grit" reduces incoming damage. Check that Cavalry deals extra damage on round 1 only.

---

## Milestone V2-6 — New Unit Classes and Aquatic

**From**: `v2_05_NEW_UNIT_CLASSES.md`

**Tasks**:
- [ ] Add `is_heal: bool` to `AttackDefinition` and handle in `BattleResolver`
- [ ] Add Cleric class to `UnitRegistry._build_default_classes()` with Heal attack
- [ ] Add Warrior class
- [ ] Add Berserker class
- [ ] Add Witch class
- [ ] Add Merfolk class (AQUATIC movement type)
- [ ] Add Sea Knight class (promotes from Merfolk)
- [ ] Update promotion trees: Fighter → Warrior, Fighter → Witch, Mage → Cleric
- [ ] Update `Squad.setup()` to detect `_is_aquatic`
- [ ] Add aquatic movement physics (same direct-lerp as flying, uses terrain cost)
- [ ] Add `has_aquatic_recruit` to `TownData`, set in `MapGenerator` for coastal towns
- [ ] Add "Recruit Merfolk" button to `TownMenu` for eligible towns
- [ ] Add all 6 new classes to the `ArmyBuilderScreen` roster display

**Test**: Promote a Mage to Cleric. Field a squad with a Cleric. Verify heals appear in battle. Field a Merfolk squad. Move it across water — it moves fast. Move it onto land — it slows. Check Merfolk can capture a land town. Test Witch's Weaken skill reduces enemy DEF in battle log.

---

## Milestone V2-7 — Multi-Faction

**From**: `v2_06_MULTI_FACTION.md`

**Tasks**:
- [ ] Extend `TerrainDefs.Faction` enum to 4 factions + FACTION_COLORS / FACTION_NAMES
- [ ] Add `faction_relations`, `active_factions`, `get_relation()`, `set_relation()` to `GameState`
- [ ] Update `Squad._on_area_entered()` to use `GameState.are_hostile()`
- [ ] Update `BattleManager.on_squads_collided()` to check hostile relation
- [ ] Update `TownNode._faction_color()` to use `TerrainDefs.FACTION_COLORS`
- [ ] Update `MapGenerator._place_towns()` to place HQ per active faction using quadrant regions
- [ ] Update `MapParams` to include `active_factions`
- [ ] Add `controlled_faction` export to `AIFaction`, update all faction references
- [ ] Add cooperative AI objective (assist allied faction's HQ)
- [ ] Update `GameState._check_hq_capture()` for multi-faction win logic
- [ ] Update `GameSetupManager` to instantiate one `AIFaction` per enemy faction
- [ ] Add faction count/preset selector to `MapConfigScreen`
- [ ] Add `GameState.faction_squads` dictionary, update `register_squad()`

**Test**: Select a 3-faction map (Three-Way War). See three differently-colored HQs. Watch two enemy factions fight each other when their squads collide. Win by capturing both enemy HQs. Confirm you can lose to either enemy faction.

---

## Milestone V2-8 — Save/Load

**From**: `v2_07_MAP_CONFIG_AND_SAVE_LOAD.md` (second half)

**Tasks**:
- [ ] Create `SaveSystem.gd` autoload with `save()`, `load_game()`, `load_exists()`
- [ ] Implement `_serialize_squad()` and `_deserialize_squad()`
- [ ] Auto-save after each battle in `BattleManager._on_battle_completed()`
- [ ] Add "Continue" button to `TitleScreen` (grayed if no save)
- [ ] Add `GameState.is_loading_save` flag + restore logic in `Main.tscn._ready()`
- [ ] Add "Save Game" button to pause menu
- [ ] Handle save file version mismatch gracefully (warn + offer fresh start)

**Test**: Play until 3 battles have been fought. Quit. Reopen. Click Continue. Squads are in the same positions with correct HP/XP. Towns have correct ownership. Gold is correct.

---

## Notes for Claude Code

- **Do V2-1 fixes before any other milestone**. Skipping them will cause confusing bugs in later work.
- **Don't rewrite working V1 code** — extend it. Add fields to existing resources rather than creating parallel data structures.
- **`BattleResolver` must stay a pure function** — no autoload access except `UnitRegistry` and `ItemRegistry`. `SkillSystem` is static so it's fine.
- **The `Faction` enum change in V2-7 is the highest-risk item** — audit every hardcoded `TerrainDefs.Faction.ENEMY` reference across all files and replace with `controlled_faction` or `GameState.are_hostile()` as appropriate.
- **Test each milestone with at least one full game** (map gen → deploy → battle → capture → win/lose) before moving to the next.
- When in doubt on a design detail, implement the simplest version and add a `# TODO V3:` comment.
