# V3-01 — Unit Persistence

## The Problem

Every new game in V2 calls `_make_v2_starter()` in `ArmyBuilderScreen._ready()`, creating a fresh set of level 1–5 units from a hardcoded list. No XP or levels carry over between maps. The army builder has no memory.

V3 fixes this: the player manages a **persistent roster** of named units that level up, promote, and potentially die permanently across a campaign.

---

## PersistentRoster (new GameState field)

Add to `GameState.gd`:

```gdscript
# The player's persistent named unit pool, survives between maps
var persistent_roster: Array[UnitData] = []
var campaign_run_active: bool = false   # true when in a campaign (not random map)
```

The persistent roster is populated once at campaign start (see `v3_02_CAMPAIGN_MODE.md`) and then mutated in place as units level up, get items, die, or are recruited.

---

## Carrying Units Between Maps

### At Map End (Victory or Defeat)

When `GameState.faction_won` fires:

1. Collect all surviving player units from all squads (on-map and reserve).
2. Update `GameState.persistent_roster` with their current state (HP, XP, level, held_item).
3. Dead units: **optionally** removed from the roster (permadeath mode) or recovered at 1 HP (standard mode — see `v3_07_DIFFICULTY_AND_BALANCE.md`).
4. Units that were fully wiped from the map mid-game (squad destroyed): already have `is_alive = false` from `BattleManager._handle_loser()`. In permadeath mode they are removed; in standard mode they recover with 1 HP between maps.

```gdscript
# In VictoryScreen or a new CampaignManager
func _collect_survivors() -> void:
    var survivors: Array[UnitData] = []
    # On-map squads
    for sq in GameState.player_squads:
        if is_instance_valid(sq):
            for u in sq.squad_data.units:
                survivors.append(u)
    # Reserve squads
    for sd in GameState.reserve_squads:
        if sd is SquadData:
            for u in (sd as SquadData).units:
                survivors.append(u)
    
    # Apply permadeath or recovery
    var permadeath: bool = GameState.difficulty_permadeath
    for u in survivors:
        if not u.is_alive:
            if permadeath:
                continue   # Don't add to roster — unit is gone
            else:
                u.hp = 1   # Wounded, recovers to 1 HP
                u.is_alive = true
        survivors.append(u)
    
    GameState.persistent_roster = survivors
```

### At Map Start (Army Builder seeded from roster)

`ArmyBuilderScreen.setup()` currently calls `_make_v2_starter()`. Change this:

```gdscript
func _ready() -> void:
    _build_ui()
    if GameState.campaign_run_active and not GameState.persistent_roster.is_empty():
        setup_from_roster(GameState.persistent_roster)
    else:
        setup(_make_v2_starter())

func setup_from_roster(roster: Array[UnitData]) -> void:
    _all_units = roster.duplicate()   # Work on copies until confirmed
    _unassigned = _all_units.duplicate()
    _squads = []
    _add_squad()
    _refresh()
```

The army builder now shows the returning army, with their actual levels and XP. The player rearranges them into squads for the next map.

---

## Unit HP Recovery Between Maps

After a map ends and before the next one begins, show a **Between-Maps screen** (see `v3_02_CAMPAIGN_MODE.md`). On this screen, units recover HP:

- Units at 0 HP (wiped, non-permadeath): recover to `max_hp * 0.25` (quarter health — they survived but are weakened)
- Units at low HP: recover to `max_hp * 0.5` (half health if they were below half at map end)
- Units at high HP: stay at their current HP

Full recovery is a purchasable service (costs gold — see economy interaction below).

```gdscript
func apply_between_map_recovery(unit: UnitData) -> void:
    if not unit.is_alive:
        unit.is_alive = true
        unit.hp = int(float(unit.max_hp) * 0.25)
        return
    if float(unit.hp) / float(unit.max_hp) < 0.5:
        unit.hp = int(float(unit.max_hp) * 0.5)
```

---

## Gold Persistence

`GameState.player_gold` carries over between maps in campaign mode. Gold earned on one map is available on the next. Items in `player_inventory` also persist.

The between-maps screen offers:
- **Full unit recovery**: 50 gold per unit (restores to full HP)
- **Recruit new unit**: buy a fresh level-1 unit of a chosen class (costs `deploy_cost` of that class)
- **Item shop**: same items as in-map shop, but cheaper (10% discount between maps)

---

## Permadeath vs. Standard

Controlled by `GameState.difficulty_permadeath: bool` (set at campaign start, locked in). See `v3_07_DIFFICULTY_AND_BALANCE.md` for difficulty settings UI.

In **permadeath** mode:
- Units that die in battle are removed from the roster permanently.
- If the player loses all leader-capable units, campaign fails.
- Gold earned between maps is more important for recruiting replacements.

In **standard** mode (default):
- Dead units recover at 1 HP between maps.
- No permanent unit loss.
- Campaign cannot be softlocked.

---

## SaveSystem Changes

`SaveSystem.save()` must now also serialize `GameState.persistent_roster` and `GameState.campaign_run_active`:

```gdscript
# In SaveSystem.save():
if GameState.campaign_run_active:
    var roster_arr: Array = []
    for u in GameState.persistent_roster:
        roster_arr.append(_serialize_unit(u))
    cfg.set_value("campaign", "persistent_roster", roster_arr)
    cfg.set_value("campaign", "run_active", true)
    cfg.set_value("campaign", "current_scenario_idx", GameState.current_scenario_idx)
    cfg.set_value("campaign", "permadeath", GameState.difficulty_permadeath)
```

And restore in `SaveSystem.load_game()`:
```gdscript
GameState.campaign_run_active = cfg.get_value("campaign", "run_active", false)
if GameState.campaign_run_active:
    var raw: Array = cfg.get_value("campaign", "persistent_roster", [])
    for ud in raw:
        GameState.persistent_roster.append(SaveSystem.deserialize_unit(ud))
    GameState.current_scenario_idx = cfg.get_value("campaign", "current_scenario_idx", 0)
    GameState.difficulty_permadeath = cfg.get_value("campaign", "permadeath", false)
```

---

## Army Builder: Returning Army UX

When the army builder is seeded from the persistent roster, a few UI changes:

1. **Roster shows current state**: Units display their actual level, HP (shown as colored indicator — green if full, yellow if partial, red if just recovered), and held items.
2. **"Returning from [Map Name]" header**: Shows which map was just completed.
3. **Dead-recovered units** appear with a red tint and a skull icon that fades — visually clear they're in poor shape.
4. **No "Start Battle" until at least one valid squad**: Same validation as before.
5. **Promotion notification**: If any unit promoted at the end of the last battle, a banner shows "Gawain promoted to Paladin!" at the top of the screen.

---

## Random Map Mode (No Persistence)

When the player selects "Random Map" from the title screen (not "Campaign"), the system works exactly as V2: `_make_v2_starter()` is called, no roster carries over, `campaign_run_active = false`. This mode is unchanged and serves as a quick-play sandbox.
