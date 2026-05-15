# 08 — AI System

## Overview

In V1 there is one enemy AI faction. The AI runs on a **tick-based decision loop** layered on top of the real-time overworld. Every N seconds, the AI evaluates its squads and issues orders. Squads then move in real time between ticks.

The AI is intentionally simple but not purely random — it has objective priorities and reacts to the map state.

---

## AI Tick Rate

```gdscript
# AIFaction.gd
const TICK_INTERVAL: float = 8.0   # seconds between AI decisions
var tick_timer: float = 0.0

func _process(delta):
    if GameState.phase != GameState.Phase.OVERWORLD:
        return
    tick_timer += delta
    if tick_timer >= TICK_INTERVAL:
        tick_timer = 0.0
        run_ai_tick()
```

---

## Squad Objective Priorities

Each AI squad is assigned an **objective** each tick. Objectives are re-evaluated every tick (the AI can change its mind).

### Priority Order

1. **Defend HQ**: If the player has a squad within N cells of the enemy HQ and no AI squad is there, send the nearest idle AI squad to defend.
2. **Recapture lost town**: If a town that was previously enemy-owned is now player-owned or being captured, send a squad to recapture it.
3. **Capture neutral town**: If there are uncaptured neutral towns, move toward the nearest one.
4. **Attack player town**: Move toward the nearest player-owned town.
5. **Intercept player squad**: If a player squad is moving toward an AI town, intercept it.
6. **Idle patrol**: Move toward a random friendly or neutral town.

The AI assigns the highest-priority applicable objective to each squad. Multiple squads can share an objective (they'll converge on the same target).

```gdscript
func assign_objective(squad: Squad) -> Dictionary:
    # Returns {type: String, target: Node}
    if hq_under_threat():
        return {type: "defend", target: get_hq()}
    var lost = find_recently_lost_town()
    if lost:
        return {type: "recapture", target: lost}
    var neutral = find_nearest_neutral_town(squad)
    if neutral:
        return {type: "capture", target: neutral}
    var player_town = find_nearest_player_town(squad)
    if player_town:
        return {type: "attack", target: player_town}
    return {type: "patrol", target: find_patrol_target(squad)}
```

---

## AI Squad Spawning

At map start, the AI spawns squads at its HQ and any enemy-owned towns. Spawn count scales with map size:

```gdscript
func initial_spawn() -> void:
    var spawn_points = MapManager.get_towns_by_faction(Faction.ENEMY)
    for i in range(min(spawn_points.size(), MAX_AI_SQUADS)):
        var town = spawn_points[i]
        var squad = create_ai_squad()
        squad.global_position = town.global_position
        get_parent().add_child(squad)
        active_squads.append(squad)
```

`MAX_AI_SQUADS = 4` in V1. The AI does not spawn new squads mid-game in V1 (no reinforcement system yet).

---

## AI Squad Composition

AI squads are pre-defined in V1 (not generated). Define 3–4 preset squad templates:

### Template A — Infantry Rush
```
Front: Knight(L5), Fighter(L3), Fighter(L3)
Back:  Archer(L3), Archer(L3), [empty]
Leader: Knight
```

### Template B — Magic Support
```
Front: Knight(L5), Knight(L5), [empty]
Back:  Mage(L4),   Mage(L4),   [empty]
Leader: Knight
```

### Template C — Heavy
```
Front: Paladin(L8), Knight(L6), Knight(L6)
Back:  Archer(L6),  Mage(L5),   [empty]
Leader: Paladin
```

### Template D — Scout
```
Front: Cavalry(L4), Cavalry(L4), [empty]
Back:  Archer(L3),  [empty],     [empty]
Leader: Cavalry
```

Assign templates to AI squads at spawn (cycle through A→B→C→D for each squad).

---

## Threat Detection

```gdscript
func hq_under_threat() -> bool:
    var hq = MapManager.get_hq(Faction.ENEMY)
    var player_squads = GameState.get_squads_by_faction(Faction.PLAYER)
    for sq in player_squads:
        if sq.global_position.distance_to(hq.global_position) < THREAT_RADIUS:
            return true
    return false

const THREAT_RADIUS: float = 12.0   # world units
```

---

## Movement Orders

When an objective is assigned, the AI simply calls the same move order system that the player uses:

```gdscript
func execute_objective(squad: Squad, objective: Dictionary) -> void:
    var target_pos: Vector3 = objective.target.global_position
    squad.set_destination(target_pos)
```

The AI does not path-plan around enemy squads — squads will simply collide and battle if they meet, which is the intended behavior.

---

## AI Difficulty (V1 — Single Level)

No difficulty settings in V1. The AI is deterministic with the above rules. Tune difficulty through:
- `TICK_INTERVAL`: longer = slower/dumber AI
- `MAX_AI_SQUADS`: fewer = easier
- Squad template levels: lower levels = easier

These are constants for now; expose as exported vars for easy tuning later.

---

## V2 Notes

For V2 multiple factions:
- Each faction gets its own `AIFaction` node.
- Add a `faction_relations: Dictionary` to `GameState` mapping faction pairs to ALLIED / NEUTRAL / HOSTILE.
- AI objective priority adds: "assist allied faction" above "attack player town."
- Factions can flip allegiance based on map state (future).
