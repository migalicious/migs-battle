# V3-02 — Campaign Mode

## Overview

V3 adds a **linear campaign**: a fixed sequence of 5–7 scenarios, each with a specific map seed, faction preset, win condition, and optional narrative context. The player progresses through them with their persistent army.

---

## Campaign Data Structure

### ScenarioDef (new resource)

```gdscript
class_name ScenarioDef
extends Resource

@export var scenario_idx: int = 0
@export var scenario_name: String = ""
@export var description: String = ""        # Flavor text shown on the inter-map screen
@export var map_seed: int = 0
@export var map_width: int = 32
@export var map_height: int = 32
@export var num_towns: int = 6
@export var num_castles: int = 2
@export var active_factions: Array[int] = [0, 1]
@export var faction_preset: String = "hostile_all"
# "hostile_all" | "alliance_b" (player + ENEMY_B vs ENEMY_A) | "three_way" | "free_for_all"
@export var win_conditions: Array[String] = ["hq_capture"]
@export var special_objectives: Array[String] = []
# Future hooks: "survive_10_ticks", "escort_unit:Roland", "protect_town:town_3"
@export var starting_gold: int = 100       # Overrides carry-over gold for scenario 0 only
```

### CampaignDef (new resource)

```gdscript
class_name CampaignDef
extends Resource

@export var campaign_name: String = "The Black March"
@export var scenarios: Array[ScenarioDef] = []
@export var starting_units: Array[Dictionary] = []   # Same format as ScenarioData.starting_units
@export var starting_gold: int = 150
```

Store as `res://data/campaigns/default_campaign.tres`.

---

## The Default Campaign: "The Black March"

A 6-scenario campaign with escalating difficulty.

### Scenario 1 — "Border Skirmish"
```
seed: 112233
size: 24×24 (Small)
factions: Player vs Vanguard
preset: hostile_all
win: hq_capture
towns: 4, castles: 1
description: "A small border dispute. Test your forces."
```

### Scenario 2 — "The River Crossing"
```
seed: 445566
size: 32×32 (Medium)
factions: Player vs Vanguard
preset: hostile_all
win: hq_capture + all_strongholds (either)
towns: 6, castles: 2
description: "Push across the river and claim the enemy's keep."
```

### Scenario 3 — "Uneasy Allies"
```
seed: 778899
size: 32×32 (Medium)
factions: Player + Iron Pact vs Vanguard
preset: alliance_b  (Player + ENEMY_B allied vs ENEMY_A)
win: hq_capture (ENEMY_A's HQ only)
towns: 7, castles: 2
description: "The Iron Pact offers unlikely aid against a common enemy. Trust them — for now."
```

### Scenario 4 — "Three Kingdoms"
```
seed: 101010
size: 48×48 (Large)
factions: Player vs Vanguard vs Iron Pact
preset: three_way
win: all_strongholds
towns: 9, castles: 3
description: "The alliance is shattered. Every faction fights for total control."
```

### Scenario 5 — "The Shadow Rises"
```
seed: 202020
size: 48×48 (Large)
factions: Player vs Vanguard vs Shadow Order
preset: hostile_all (3-way)
win: hq_capture (both enemy HQs)
towns: 8, castles: 3
description: "A new power emerges from the east. Crush them before they consolidate."
```

### Scenario 6 — "The Final March"
```
seed: 303030
size: 48×48 (Large)
factions: Player vs all three
preset: free_for_all (Player vs ENEMY_A + B + C all hostile)
win: all_strongholds
towns: 10, castles: 4
description: "The last stand. Your army against the world."
```

---

## GameState Changes

```gdscript
# Add to GameState.gd
var current_scenario_idx: int = 0
var campaign_def: CampaignDef = null
var difficulty_permadeath: bool = false
```

---

## Campaign Flow

```
Title Screen
  [New Campaign] → DifficultyScreen → CampaignIntroScreen → ArmyBuilder (fresh) → Map 1

  [Continue Campaign] → (load save) → BetweenMapsScreen → ArmyBuilder (roster) → Map N

  [Random Map] → MapConfigScreen → ArmyBuilder (fresh) → Map (no persistence)
```

### New Campaign

1. Player clicks "New Campaign" on title screen.
2. **DifficultyScreen** (see `v3_07`): choose Standard or Permadeath. Set `GameState.difficulty_permadeath`.
3. **CampaignIntroScreen**: Shows campaign name, brief lore blurb, and the first scenario's description. "Begin" button.
4. Load `ScenarioDef` for scenario 0 from `CampaignDef`. Apply its `MapParams` to `GameState.pending_map_params`.
5. Apply `CampaignDef.starting_units` to `GameState.persistent_roster` (fresh units at base levels).
6. Open `ArmyBuilderScreen` seeded from the starter roster.
7. Start map.

### Between Maps (CampaignTransitionScreen)

After each map completes (win or loss on loss? — see below):

1. **Collect survivors** (see `v3_01_UNIT_PERSISTENCE.md`).
2. Show `CampaignTransitionScreen`:
   - Header: "Scenario X Complete — [Name]"
   - Unit roster with HP/level status
   - Recovery shop (full heal 50g/unit, recruit new units, buy items)
   - Preview of next scenario: its name and description
3. "Advance" button → `ArmyBuilderScreen` with the recovered roster.
4. Load next `ScenarioDef`, apply its `MapParams` to `GameState.pending_map_params`.
5. Start next map.

### Loss Handling

On defeat:

- **Standard mode**: Player is taken to `CampaignTransitionScreen` with a "You were defeated" header. They recover and retry the same scenario. `current_scenario_idx` does not advance.
- **Permadeath mode**: If the player has at least one leader-capable unit alive, same as standard. If no leaders survive, campaign is over — show a "Campaign Failed" screen with the option to start a new campaign.

---

## CampaignTransitionScreen

**Scene**: `scenes/ui/CampaignTransitionScreen.tscn`

```
┌────────────────────────────────────────────────────────────┐
│  Scenario 3 Complete — "Uneasy Allies"                     │
│  Gold: 430                                                 │
├──────────────────────────┬─────────────────────────────────┤
│  YOUR ARMY               │  NEXT: "Three Kingdoms"         │
│                          │                                 │
│  Roland   Knight L9  ♥♥♥ │  A three-way war for total      │
│  Gawain   Paladin L8 ♥♥♥ │  control. Every faction fights  │
│  Sylvia   Archer L7  ♥♥½ │  for themselves.                │
│  Marcus   Cavalry L6 ♥♥  │                                 │
│  Bors     Fighter L5 ♥   │  Factions:                      │
│  Lyra     Sorc.  L7  ♥♥♥ │  You vs Vanguard vs Iron Pact   │
│  ...                     │                                 │
│  [Recover All  420g]     │  Win: All Strongholds           │
│  [Shop]                  │                                 │
├──────────────────────────┴─────────────────────────────────┤
│                                        [Advance to Map 4] │
└────────────────────────────────────────────────────────────┘
```

HP hearts: 3 hearts = full, 2 = above half, 1 = below half, skull = dead (recovering).

The "Recover All" button: costs `50 * number_of_injured_units` gold, restores all to full HP.

The "Shop" button opens a sub-panel with the item shop (same items as in-map, 10% cheaper).

"Recruit Unit" button: opens a class selection dropdown, costs `deploy_cost` of the selected class, adds a fresh level-1 named unit to the roster (name auto-generated or player-entered).

---

## Faction Preset Application

The `CampaignTransitionScreen` or `GameSetupManager` applies faction relations from `ScenarioDef.faction_preset` before map generation:

```gdscript
func _apply_faction_preset(preset: String, factions: Array[int]) -> void:
    GameState.active_factions = factions
    GameState._init_default_relations()   # All hostile by default
    match preset:
        "alliance_b":
            # Player + ENEMY_B allied vs ENEMY_A
            GameState.set_relation(TerrainDefs.Faction.PLAYER,
                TerrainDefs.Faction.ENEMY_B, GameState.Relation.ALLIED)
        "three_way":
            pass   # All hostile — default is already correct
        "free_for_all":
            pass   # All hostile — same
        _:
            pass   # "hostile_all" — default
```

---

## Title Screen Changes

Add three buttons:
- **New Campaign** → DifficultyScreen → intro → map 1
- **Continue Campaign** (grayed if no campaign save) → load → CampaignTransitionScreen
- **Random Map** → MapConfigScreen (V2 behavior, unchanged)
- **Quit**

`SaveSystem` needs to distinguish campaign saves from random-map saves. Add a `save_type` field:
```gdscript
cfg.set_value("meta", "save_type", "campaign")  # or "random"
```

"Continue Campaign" checks `save_type == "campaign"`.
