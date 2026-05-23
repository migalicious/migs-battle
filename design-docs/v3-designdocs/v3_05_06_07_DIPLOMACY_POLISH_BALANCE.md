# V3-05 — Dynamic Diplomacy

## Overview

In V2, faction relations are set at map start and never change. V3 adds **mid-game relation events** — moments where an AI faction proposes an alliance, betrays the player, or turns on another faction based on the map state.

This makes multi-faction maps feel alive rather than static.

---

## DiplomacyEvent (new resource)

```gdscript
class_name DiplomacyEvent
extends Resource

enum EventType {
    ALLIANCE_OFFER,    # Faction asks player to ally
    BETRAYAL,          # Faction that was allied turns hostile
    ENEMY_ALLIANCE,    # Two enemy factions ally against player
}

@export var event_type: EventType
@export var from_faction: int     # Who is initiating
@export var to_faction: int       # Target (usually PLAYER for offers)
@export var trigger_condition: String   # "player_ahead" | "player_behind" | "timer_N" | "town_captured:town_id"
@export var description: String   # Shown in the diplomacy popup
```

---

## Event Triggers

`DiplomacyManager` (new `Node` in `Main.tscn`) checks trigger conditions each AI tick:

```gdscript
class_name DiplomacyManager
extends Node

var _pending_events: Array[DiplomacyEvent] = []
var _fired_events: Array[String] = []   # event IDs already triggered this map

func _process(_delta: float) -> void:
    if GameState.current_phase != GameState.Phase.OVERWORLD:
        return
    for event in _pending_events:
        if _condition_met(event) and not _already_fired(event):
            _fire_event(event)

func _condition_met(event: DiplomacyEvent) -> bool:
    match event.trigger_condition:
        "player_ahead":
            # Player owns more than 60% of towns
            return _player_town_fraction() > 0.6
        "player_behind":
            # Player owns fewer than 30% of towns
            return _player_town_fraction() < 0.3
        _:
            if event.trigger_condition.begins_with("timer_"):
                var t := int(event.trigger_condition.split("_")[1])
                return Time.get_ticks_msec() / 1000 > t
    return false
```

---

## Event Examples (Scenario 3 — "Uneasy Allies")

The player starts allied with Iron Pact. Possible events:

**Betrayal (if player dominates)**:
- Trigger: `player_ahead` (player owns >60% of towns)
- Iron Pact turns hostile: "The Iron Pact grows fearful of your power. They withdraw their support."
- `GameState.set_relation(PLAYER, ENEMY_B, HOSTILE)`

**Alliance Offer (if player is struggling)**:
- Trigger: `player_behind` (player owns <30% of towns)
- Shadow Order (if present) offers alliance: "The Shadow Order proposes terms. Will you accept?"
- Player sees a Y/N popup.
- Yes: `GameState.set_relation(PLAYER, ENEMY_C, ALLIED)` and `GameState.set_relation(ENEMY_C, ENEMY_A, HOSTILE)`
- No: nothing changes

---

## Diplomacy Popup UI

When an event fires that requires player input (`ALLIANCE_OFFER`), pause the game and show:

```
┌────────────────────────────────────────────────┐
│  ⚔ DIPLOMACY                                   │
│                                                │
│  The Shadow Order proposes terms:              │
│  "Join us and destroy the Vanguard together."  │
│                                                │
│  [Accept Alliance]        [Refuse]             │
└────────────────────────────────────────────────┘
```

Events that don't require input (BETRAYAL, ENEMY_ALLIANCE) just show a notification banner that auto-dismisses after 4 seconds while changing the relation in the background.

---

## Visual Feedback on Relation Change

When `faction_relation_changed` fires, update:
- Minimap: redraw faction-colored squad dots
- Town colors: towns owned by newly-hostile factions don't change (they're still their color) but the tooltip/TownMenu shows the updated relation
- Notification banner: "[Faction] is now HOSTILE / ALLIED"

The `faction_relation_changed` signal was emitted in V2 but nothing listened. Wire it in V3.

---

# V3-06 — Battle Polish

## Round Separators

Currently all battle actions stream into the log with no visual break between rounds. Add a separator:

```gdscript
# In BattleAnimator._animate_battle(), track round boundaries in BattleResult
# Add a new ActionType: ROUND_START

# In BattleResolver._run_round():
var sep := BattleAction.new()
sep.action_type = BattleAction.ActionType.ROUND_START
sep.attack_name = "Round %d" % round_num
battle_log.append(sep)
# ... existing round logic

# In BattleAnimator._process_action():
BattleAction.ActionType.ROUND_START:
    _log_line("[color=#888888]── Round %s ──[/color]" % action.attack_name)
    # Brief pause between rounds
    await get_tree().create_timer(0.5).timeout
```

Also add a round indicator at the top of the BattleScene panel: "Round 1 / 3", updating after each ROUND_START action.

---

## Battle Speed Control

Add a speed toggle button to the battle scene (top-right corner):

```
[1× Speed]  →  [2× Speed]  →  [Skip]  →  (loops back to 1×)
```

Implementation: change `BattleAnimator.DELAY` dynamically.

```gdscript
var _speed_mode: int = 0   # 0=normal, 1=fast, 2=instant
const DELAYS := [0.35, 0.12, 0.0]

func _on_speed_btn_pressed() -> void:
    _speed_mode = (_speed_mode + 1) % 3
    _speed_btn.text = ["1× Speed", "2× Speed", "Skip"][_speed_mode]

func _animate_battle() -> void:
    for action in _result.action_log:
        var delay := DELAYS[_speed_mode]
        if delay > 0.0:
            await get_tree().create_timer(delay).timeout
        _process_action(action as BattleAction)
        if _speed_mode == 2:   # Skip: process all instantly
            continue
```

"Skip" mode processes all actions with no delay, then shows the result immediately.

---

## Status Effect Display

V2 has `STAT_DEBUFF_ENEMY` and `STAT_BUFF_SELF` effects, but they're applied silently — no visual feedback. V3 shows a brief indicator:

```gdscript
# In BattleAnimator._process_action(), add SKILL handling:
BattleAction.ActionType.SKILL:
    _log_line("[color=#c080ff]%s — %s: %s[/color]" % [
        action.actor_unit_id, action.attack_name, action.description])
    if action.target_unit_id != "":
        var box := _find_slot_box(action.target_unit_id)
        if box:
            _show_damage_number(box, action.attack_name, Color(0.75, 0.5, 1.0))
```

Add `description: String` to `BattleAction` (populated from `skill.display_name`). The floating text shows what the skill did ("Weakened!", "Shield Bash!", "Drain Life!").

---

## HP Bar Colors During Battle

Currently HP bars don't update color as they drain. Fix:

```gdscript
func _update_hp(box: ColorRect, delta: int) -> void:
    # ... existing code ...
    var frac := float(cur) / float(box.get_meta("unit_max_hp", 1))
    if bar:
        bar.value = float(cur)
        if frac > 0.5:
            bar.modulate = Color(0.2, 0.85, 0.2)   # Green
        elif frac > 0.25:
            bar.modulate = Color(0.9, 0.75, 0.1)   # Yellow
        else:
            bar.modulate = Color(0.9, 0.2, 0.2)    # Red
```

Store `unit_max_hp` as box metadata in `_make_slot()`.

---

# V3-07 — Difficulty and Balance

## Difficulty Settings Screen

**Scene**: `scenes/ui/DifficultyScreen.tscn`

Appears after clicking "New Campaign". Two choices:

```
┌──────────────────────────────────────────┐
│           SELECT DIFFICULTY              │
├──────────────────────────────────────────┤
│  [STANDARD]                              │
│  Units recover between maps.             │
│  Recommended for first-time players.     │
│                                          │
│  [PERMADEATH]                            │
│  Fallen units are lost forever.          │
│  A true strategic challenge.             │
└──────────────────────────────────────────┘
```

Sets `GameState.difficulty_permadeath`. Difficulty also affects AI `difficulty_mult` (1.0 for Standard, 1.2 for Permadeath base).

---

## Balance Review — Issues to Address in V3

After reviewing the class stats and skill effects from V2:

**Berserker is likely overtuned**: 3 Rampage hits at power 1.3 + Bloodlust self-heal + War Cry AoE in back row. Recommend reducing Rampage to 2 hits or lowering power to 1.1 before adding more classes.

**Mage back-row targeting**: Back-row Magic hits `FRONT` target row — this was likely a typo from the V1 spec. Magic users should threaten the back row by default. Check `mage.back_attacks` — if `targets_row = FR`, change to `ANY` or `BK`.

**Cleric heal value**: `INT * 1.5` per heal tick at INT ~7 base = ~10 HP per action. With Devoted skill (12% max HP per round) on top, Clerics are very strong. Consider requiring Devoted to check `HP_BELOW_50` on the ally rather than being unconditional.

**Cavalry on road**: speed 4.5 × 1.5 = 6.75 u/s on roads vs infantry at 3.0 × 1.3 = 3.9. Cavalry can lap the map multiple times before infantry reaches the midpoint. Consider adding a global `MAX_SQUAD_SPEED` cap (e.g. 5.5 u/s) or reducing cavalry road multiplier to 1.3.

**XP scaling**: Winning gives `10 + avg_level * 3` per unit. At level 15, that's 55 XP per battle, while level 15 XP threshold is 1500. Fighting level 15 enemies gains 55 XP toward a 1500 threshold — very slow at high levels. Consider a multiplier or a flat bonus for fighting higher-level enemies.

### Tuning Constants File

Create `res://scripts/GameBalance.gd` (not an autoload, just a constants file):

```gdscript
class_name GameBalance

# Battle
const ROUNDS: int = 3
const BASE_HIT_CHANCE: float = 0.80
const HIT_CHANCE_PER_AGI: float = 0.02
const DEFENSE_REDUCTION: float = 0.5     # defender.DEF * this subtracted from base damage
const DAMAGE_VARIANCE: float = 0.10      # ±10%
const MAX_SQUAD_SPEED: float = 5.5       # world units/sec cap

# XP
const XP_WIN_BASE: int = 10
const XP_WIN_PER_LEVEL: float = 3.0
const XP_LOSE_BASE: int = 5
const XP_LOSE_PER_LEVEL: float = 1.0
const XP_THRESHOLD_BASE: int = 100       # xp_to_next = XP_THRESHOLD_BASE * level

# Economy
const GOLD_TICK_INTERVAL: float = 10.0
const TOWN_INCOME: int = 15
const CASTLE_INCOME: int = 30
const HQ_INCOME: int = 50
const BETWEEN_MAP_RECOVER_COST: int = 50   # per unit
const SHOP_BETWEEN_MAP_DISCOUNT: float = 0.10

# AI
const AI_TICK_INTERVAL: float = 8.0
const AI_THREAT_RADIUS: float = 12.0
const AI_REINFORCE_GOLD_THRESHOLD: int = 200
const AI_MAX_SQUADS: int = 4
```

Replace hardcoded magic numbers in `BattleResolver`, `GameState`, `AIFaction`, and `TerrainDefs` with references to `GameBalance.*`. This makes balancing iterations much faster.
