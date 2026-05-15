# 07 — Town and Capture System

## Town Types

| Type | Description | Can Be Player HQ Lost? |
|------|-------------|----------------------|
| TOWN | Small settlement; deploy point, minor objective | No |
| CASTLE | Fortified stronghold; deploy point, major objective | No |
| HQ | Main stronghold; one per faction | Yes — losing = defeat |

All types function the same mechanically in V1. The distinction is visual (mesh size/shape) and strategic (win condition checks).

---

## Ownership States

Each town has an owner: `PLAYER (0)`, `ENEMY (1)`, or `NEUTRAL (-1)`.

`GameState` maintains the authoritative ownership dictionary:
```gdscript
# GameState.gd
var town_ownership: Dictionary = {}   # town_id -> Faction enum value
```

Town nodes query this on ready and whenever the signal `town_captured` fires.

---

## Capture Mechanic

Capture is not instant — a squad must **occupy** a town for a duration.

### Capture Rules

1. A squad moves to the cell containing a town.
2. If the town is **friendly**: the squad enters garrison (see §05).
3. If the town is **neutral or enemy**:
   - If an enemy squad is garrisoned there: a battle triggers first. After the battle, if the attacker wins, proceed to capture.
   - If no defender: capture begins immediately.
4. **Capture timer**: the town has a `capture_turns` value (default 3). This is counted in **capture ticks**. One capture tick fires every **5 seconds of real time** while a squad occupies the town.
5. A progress bar appears over the town showing capture progress.
6. If the occupying squad leaves or is driven off before capture completes, the timer resets to 0.
7. On completion: `town_ownership[town_id] = attacking_faction`. Signal `town_captured` fires.

```gdscript
# TownNode.gd
var capture_ticks: int = 0
var occupying_squad: Squad = null
var tick_timer: float = 0.0
const TICK_INTERVAL: float = 5.0

func _process(delta):
    if occupying_squad == null:
        return
    if occupying_squad.faction == current_owner:
        return   # Friendly — garrison, not capture
    tick_timer += delta
    if tick_timer >= TICK_INTERVAL:
        tick_timer = 0.0
        capture_ticks += 1
        update_capture_bar()
        if capture_ticks >= town_data.capture_turns:
            complete_capture(occupying_squad.faction)

func complete_capture(new_faction: int) -> void:
    GameState.town_ownership[town_data.town_id] = new_faction
    capture_ticks = 0
    occupying_squad = null
    update_visuals()
    emit_signal("town_captured", self, new_faction)
    GameState.check_win_conditions()
```

### Squad Enters Town Cell

```gdscript
# Squad.gd — called when squad_arrived fires at a town cell
func on_arrived_at_town(town: TownNode) -> void:
    if town.current_owner == self.faction:
        town.set_garrison(self)
        emit_signal("squad_entered_town", self, town)
    else:
        if town.occupying_squad != null and town.occupying_squad.faction != self.faction:
            # Occupied by enemy — fight for the town
            emit_signal("squad_collided_with_enemy", self, town.occupying_squad)
        else:
            town.begin_capture(self)
```

---

## Deploy System

All player deployment happens from friendly towns. The flow:

1. Player left-clicks a friendly town → `TownMenu` opens.
2. `TownMenu` shows:
   - Town name and type
   - Current garrison (if any)
   - "Deploy Squad" button (disabled if a squad is already standing on the town)
3. Clicking "Deploy Squad" opens the army roster panel.
4. Player selects a squad from their reserve.
5. Squad spawns at the town's world position.
6. The town is now the squad's "home base" for retreat purposes.

### Retreat Destination

When a squad retreats (lost a battle), it moves to the nearest **friendly town**:
```gdscript
func find_retreat_destination(squad: Squad) -> TownNode:
    var friendly_towns = MapManager.get_towns_by_faction(squad.faction)
    var nearest = friendly_towns.reduce(func(a, b):
        var da = squad.global_position.distance_to(a.global_position)
        var db = squad.global_position.distance_to(b.global_position)
        return a if da < db else b
    )
    return nearest
```

In V1, retreat is a **teleport** (position set instantly) to avoid complex pathfinding edge cases after battle. Add movement animation in V2.

---

## Town Visuals

### Base Mesh (placeholder primitives)

```
Town:
  Base box: 1.8 × 0.5 × 1.8 (faction color material)
  Tower:    0.5 × 1.0 × 0.5 (slightly darker shade)
  Flag:     0.1 radius cylinder, 0.6 tall, at top of tower (faction color)

Castle:
  Base box: 2.2 × 0.6 × 2.2
  Tower:    0.7 × 1.6 × 0.7
  Battlements: 4 small cubes at corners of base, 0.3 × 0.4 × 0.3

HQ:
  Same as Castle but tower height 2.4, extra ring of battlements
```

### Dynamic Color Updates

When `town_captured` fires:
- Tween the base and flag material's `albedo_color` to the new faction color over 0.5s.

### Capture Progress Bar

A `ProgressBar` or custom `SubViewport`-rendered bar floating above the town during capture. Show only while actively being captured. Hidden otherwise.

---

## Garrison Indicator

When a squad is garrisoned, show a small colored cube on top of the town's tower (faction color, slightly transparent). Remove it when the squad deploys or is defeated.
