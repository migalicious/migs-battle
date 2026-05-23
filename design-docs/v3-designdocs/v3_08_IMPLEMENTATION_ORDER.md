# V3-08 — Implementation Order

Complete milestones in order. V3 has more cross-cutting concerns than V1 or V2, so the order matters more. Do the fixes and infrastructure first, then the campaign layer, then the depth features.

---

## Milestone V3-1 — Fix V2 Gaps (Do This First)

Small fixes that should have been in V2 but weren't. Fast wins before any new features.

**Tasks**:
- [ ] Fix `AIFaction._assign_objective()` to implement cooperative ally assist (the code from v3_04 — it's just a missing branch in the existing method)
- [ ] Fix `GameState._collect_income()` — extend to handle ENEMY_B and ENEMY_C income, not just ENEMY_A
- [ ] Fix Mage `back_attacks` target row — verify it's `ANY` or `BACK`, not `FRONT`. If it's `FRONT`, change to `ANY` in `UnitRegistry._build_default_classes()`
- [ ] Add round separator `ROUND_START` to `BattleAction.ActionType` and emit in `BattleResolver._run_round()` — log display only, no pause
- [ ] HP bar color update during battle (store `unit_max_hp` as box metadata, update modulate in `_update_hp()`)
- [ ] Status effect display: populate `BattleAction.description` for SKILL actions; show floating text in `BattleAnimator`

**Test**: Start a 3-faction map with Alliance preset. Watch ENEMY_B squads move to defend ENEMY_B's HQ when threatened. Verify all three factions accumulate gold. Verify Mage hits back row. Battle log shows "── Round 2 ──" separator. HP bars turn yellow/red as they drain.

---

## Milestone V3-2 — GameBalance Constants File

Extract all hardcoded tuning values before adding new systems that would reference them.

**Tasks**:
- [ ] Create `res://scripts/GameBalance.gd` with all constants listed in v3_07
- [ ] Replace hardcoded values in: `BattleResolver` (ROUNDS, hit chance, defense reduction, variance), `GameState` (tick interval, income amounts), `AIFaction` (TICK_INTERVAL, MAX_AI_SQUADS, THREAT_RADIUS), `TerrainDefs.SPEED_TABLE` (road cap via MAX_SQUAD_SPEED applied in `Squad._update_terrain_speed()`)
- [ ] Verify nothing broke — all constants should produce same behavior as before

**Test**: Change `GameBalance.ROUNDS = 5`, start a battle — it runs 5 rounds. Change back to 3.

---

## Milestone V3-3 — Battle Speed Control + Skip

Quick win that dramatically improves playability.

**Tasks**:
- [ ] Add `_speed_mode` int and `_speed_btn` Button to `BattleAnimator`
- [ ] Change `_animate_battle()` to use `DELAYS[_speed_mode]` instead of hardcoded `DELAY`
- [ ] Speed button cycles 1× → 2× → Skip
- [ ] Skip mode: process all log entries instantly, jump to result banner
- [ ] Save preferred speed in `user://preferences.cfg` and restore on next run

**Test**: Start a battle. Click speed button three times — verify 1×, 2×, instant/skip all work. Close and reopen game — verify speed preference is remembered.

---

## Milestone V3-4 — AI Items and Reinforcements

**Tasks**:
- [ ] Add `_equip_template_items()` to `AIFaction`, call it from `_initial_spawn()` after `_build_template()`
- [ ] Scale item quality by template index (A/D easy, B medium, C hard)
- [ ] Add `_consider_reinforcement()` to `AIFaction._run_ai_tick()`
- [ ] Add `_find_unoccupied_friendly_town()` helper
- [ ] Wire `GameBalance.AI_REINFORCE_GOLD_THRESHOLD` and `AI_MAX_SQUADS` constants
- [ ] Add `difficulty_mult: float` export to `AIFaction`
- [ ] Apply `difficulty_mult` to template levels in `_build_template()`
- [ ] `Main.gd` sets `difficulty_mult` on each AIFaction from `GameState.difficulty_level` (stub the field if needed)

**Test**: Let a game run for 2 minutes without doing anything. Watch enemy gold accumulate (visible via DebugServer or a debug label). Once threshold is hit, a new enemy squad should spawn at an enemy town. Verify enemy units have items in their `held_item` fields (check via DebugServer or print).

---

## Milestone V3-5 — Post-Battle Army Management

**Tasks**:
- [ ] Add `is_wounded` field to `UnitData`, serialize in `SaveSystem`
- [ ] Set `is_wounded` in `BattleManager._apply_result()` for units below 25% HP
- [ ] Apply wounded damage penalty (×0.8) in `BattleResolver._calculate_damage()`
- [ ] Show bandage icon in `SquadInspector` for wounded units
- [ ] Add "Manage Army" tab to `TownMenu` for friendly towns with garrisoned or nearby squads
- [ ] Implement squad edit view (simplified army builder grid, transfer units between squads)
- [ ] Implement `merge_squads()` in `SquadController` or a new `ArmyManager` node
- [ ] Add reserve squad cap (5 squads); notification if cap exceeded on retreat

**Test**: Field two squads. Let one get badly beaten (1 unit left). Move it to a friendly town. Open TownMenu → Manage Army. Merge the weak squad into the garrison. Verify units transferred correctly and the source squad is gone.

---

## Milestone V3-6 — Unit Persistence + Between-Maps Screen

This and V3-7 together form the campaign layer. Do V3-6 first.

**Tasks**:
- [ ] Add `persistent_roster: Array[UnitData]` and `campaign_run_active: bool` to `GameState`
- [ ] Add `_collect_survivors()` function — called from VictoryScreen before transition
- [ ] Implement `apply_between_map_recovery()` for wounded/dead units
- [ ] Create `CampaignTransitionScreen.tscn` and `.gd` with:
  - Unit list showing HP hearts and level
  - "Recover All" button (costs gold)
  - Item shop (10% discount)
  - "Recruit Unit" (class dropdown, pays deploy_cost)
  - Next scenario preview panel
  - "Advance" button
- [ ] Update `ArmyBuilderScreen._ready()` to check `campaign_run_active` and call `setup_from_roster()` if true
- [ ] Show promotion banners in army builder for units that promoted in the previous battle
- [ ] Update `SaveSystem` to serialize `persistent_roster`, `current_scenario_idx`, `difficulty_permadeath`

**Test**: Win a map. See CampaignTransitionScreen. Spend gold to recover units. Click Advance. ArmyBuilder shows the returning army with their actual levels. Start next map — squad has the same units.

---

## Milestone V3-7 — Campaign Mode

**Tasks**:
- [ ] Create `ScenarioDef.gd` and `CampaignDef.gd` resource classes
- [ ] Create `res://data/campaigns/default_campaign.tres` with all 6 scenarios
- [ ] Create `DifficultyScreen.tscn` and `.gd` (Standard / Permadeath choice)
- [ ] Create `CampaignIntroScreen.tscn` and `.gd` (shows campaign name + scenario 1 description)
- [ ] Add `current_scenario_idx`, `campaign_def`, `difficulty_permadeath` to `GameState`
- [ ] Add `scenario_difficulty_mults` array to campaign data; pass to `AIFaction.difficulty_mult` on map start
- [ ] Update `TitleScreen` with New Campaign / Continue Campaign / Random Map buttons
- [ ] Update `GameSetupManager` to handle campaign flow: load `ScenarioDef` → transition screen → army builder → map
- [ ] Implement loss handling: retry same scenario (standard) or campaign-fail check (permadeath)
- [ ] Update `SaveSystem` with `save_type` field; "Continue Campaign" checks for campaign save

**Test**: Start a new campaign. Choose Standard. See intro. Build army. Play map 1. Win. See transition screen. Advance. Play map 2. Save mid-game. Quit. Reopen. Click "Continue Campaign". Resume from where you left off on map 2.

---

## Milestone V3-8 — Dynamic Diplomacy

**Tasks**:
- [ ] Create `DiplomacyEvent.gd` resource
- [ ] Create `DiplomacyManager.gd` Node; add to `Main.tscn`
- [ ] Implement trigger conditions: `player_ahead`, `player_behind`, `timer_N`
- [ ] Implement event types: ALLIANCE_OFFER (player prompt), BETRAYAL (silent), ENEMY_ALLIANCE (silent)
- [ ] Create diplomacy popup UI (small centered Panel, Y/N buttons)
- [ ] Create notification banner (top of screen, auto-dismisses after 4s)
- [ ] Wire `faction_relation_changed` signal: update minimap squad dot colors, show notification
- [ ] Add diplomacy events to Scenario 3 (`trigger: player_ahead → Iron Pact betrayal`, `trigger: player_behind → Shadow Order offer`)
- [ ] Add `_apply_faction_preset()` to `GameSetupManager` for scenario faction presets

**Test**: Play Scenario 3. Capture >60% of towns. Iron Pact turns hostile — see notification banner. Allied squad dots change from friendly to hostile on minimap. Next AI tick, Iron Pact squads start moving toward player towns.

---

## Notes for Claude Code

- **V3-1 through V3-3 are fast** — complete in one session before anything else.
- **`GameBalance.gd` (V3-2) is a prerequisite** for V3-4 through V3-8. Don't skip it — it prevents numeric drift as new systems reference each other.
- **Campaign mode (V3-6 and V3-7) are tightly coupled** — do them back-to-back in the same session.
- **`DiplomacyManager` should be a child of Main.tscn**, not an autoload. It needs map context (town counts, squad positions) and should be destroyed when the map ends.
- **Berserker balance**: Apply the recommended nerf (Rampage 3 hits → 2 hits, or power 1.3 → 1.1) in V3-2 when touching balance constants. Don't wait.
- **Test the full campaign from scenario 1 through 6** before shipping V3. The campaign is the feature — it needs to actually be beatable.
- When in doubt, add a `# TODO V4:` comment and move on.
