# V3 Design Documents — Overview & Audit

## V2 Audit

Everything in the V2 spec got implemented. The codebase is in good shape:

### ✅ Fully Implemented
- All 8 V1 fixes (terrain speed, faction colors, minimap wiring, path line, can't-go-there, battle level-up display, SquadData.movement_type computed property, dead code removal)
- `MapConfigScreen` with size/seed/towns/castles/factions/win condition selectors, seed replay
- `GameSetupManager` orchestrating TitleScreen → MapConfig → ArmyBuilder → Main
- `ArmyBuilderScreen`: full click-to-assign, squad tabs, auto-leader, validation
- `ScenarioData` resource with 18-unit V2 starter roster
- Gold economy: income ticks, deploy costs, gold display with flash animation, can't-afford label
- `ItemRegistry` autoload, 7 starter items, shop in TownMenu, equip system
- Item bonuses applied in `BattleResolver._get_stat()`
- Consumable items applied before round 1
- Full `SkillDefinition` + `SkillSystem`: 8 conditions (ALWAYS, HP_BELOW_50, HP_ABOVE_75, FIRST_ROUND, LAST_ROUND, ALLY_DEAD, ENEMY_FRONT_EMPTY, ON_WATER)
- All 8 SkillEffects implemented in `BattleResolver`
- Skills assigned to all 14 classes
- 6 new classes: Cleric (with heal attack), Warrior, Berserker, Witch, Merfolk, Sea Knight
- `is_heal` attack flag; Cleric back-row heal works
- Aquatic movement: direct-lerp like flying, terrain speed still applied
- Coastal town detection; Merfolk recruit in TownMenu
- Multi-faction: 4 factions in TerrainDefs, FACTION_NAMES/FACTION_COLORS, relation API, hostile check in all collision/battle gates
- Multi-faction map generation with quadrant HQ placement
- `AIFaction.controlled_faction` export; `Main.gd` spawns extra AIFaction nodes
- `SaveSystem`: complete serialize/deserialize, auto-save after battle, Continue on title screen
- `DebugServer`: TCP server on port 6560 for debug commands — a bonus addition not in spec

### ⚠️ Gaps / Unfinished Areas
- **`AIFaction` cooperative behavior**: The `_assign_objective` method checks for `_find_nearest_hostile_town` but the cooperative "assist allied faction HQ" logic from the v2_06 spec was not implemented. Allied AI factions don't help each other.
- **`_collect_income()` in GameState**: Only handles `ENEMY_A`. Enemy factions B and C don't accumulate gold. Minor since AI doesn't spend gold yet, but inconsistent.
- **Faction relation changes mid-game**: `faction_relation_changed` signal is defined and emitted, but nothing listens for it in-game. No dynamic diplomacy events occur.
- **Army Builder doesn't persist across "Play Again"**: `VictoryScreen._on_play_again_pressed()` calls `get_tree().reload_current_scene()` which reloads TitleScreen — the player rebuilds their army from scratch every run. Units don't carry over between runs.
- **AI doesn't use items or skills strategically**: Items are not assigned to enemy units. AI squads fight as raw stats.
- **No unit persistence between runs**: Every new game recreates the unit pool from scratch via `_make_v2_starter()` in `ArmyBuilderScreen._ready()`. XP and levels are lost.
- **Battle scene has no round separator**: Actions from different rounds run together in the log with no visual break between them.
- **Merfolk recruit creates a squad with only one unit**: `_on_recruit_merfolk` creates a SquadData with one Merfolk marked as leader. Fine for now but the player would need to manually add other units to it via an in-battle army management system — which doesn't exist yet.
- **No post-battle army management**: After a battle, wiped units are just gone. There's no way to recompose squads on the map without returning to a town.
- **No scenario progression**: Each game is a standalone random map. There's no campaign with story, handcrafted maps, or unlocks.

---

## V3 Scope

V3 shifts the game from a "random map prototype" to something with **replayability and strategic identity**. The player's army persists, grows, and matters. The map has strategic variety. The campaign has structure.

### V3 Theme: "Campaign Layer"

| Area | V3 Feature |
|------|-----------|
| Persistence | Unit roster survives between maps; XP and levels carry over |
| Campaign | Linear scenario chain with hand-authored map seeds and objectives |
| Strategic depth | Post-battle army management; squad recomposition on the map |
| AI | Enemy items + skill-aware tactics; AI gold spending (reinforcements) |
| Polish | Round separators in battle; battle speed control; improved minimap |
| Balance | Difficulty settings; tuning knobs exposed |
| Diplomacy | Dynamic faction relations (betrayal events, alliance offers) |

## V3 Document Index

| File | Contents |
|------|----------|
| `v3_00_OVERVIEW.md` | This file |
| `v3_01_UNIT_PERSISTENCE.md` | Roster survival between maps; campaign save state |
| `v3_02_CAMPAIGN_MODE.md` | Scenario chain, handcrafted seeds, inter-map screen |
| `v3_03_POST_BATTLE_ARMY_MANAGEMENT.md` | Field recomposition, wounded unit recovery, squad editing |
| `v3_04_AI_IMPROVEMENTS.md` | Enemy items, AI gold spending, skill-aware behavior |
| `v3_05_DYNAMIC_DIPLOMACY.md` | Mid-game relation shifts, betrayal, alliance offers |
| `v3_06_BATTLE_POLISH.md` | Round separators, speed control, skip, status effects display |
| `v3_07_DIFFICULTY_AND_BALANCE.md` | Difficulty settings, tuning, stat balance review |
| `v3_08_IMPLEMENTATION_ORDER.md` | Build order for V3 |
