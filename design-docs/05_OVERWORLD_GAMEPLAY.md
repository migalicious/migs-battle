# 05 — Overworld Gameplay

## Camera

### Setup
- `Camera3D` positioned above the map looking down at a ~60–70° angle (not straight down — slight perspective shows terrain height differences).
- Attached to a `Node3D` camera rig that handles panning and zoom.
- **Projection**: Perspective (shows 3D depth of mountains/forests). Can try orthographic later.

### Controls

| Input | Action |
|-------|--------|
| Middle mouse drag / WASD | Pan camera across map |
| Scroll wheel | Zoom in/out (clamp: min 5 units above ground, max 60 units) |
| Q / E | Rotate camera around Y axis (optional in V1) |
| Escape | Deselect current selection |

Camera panning should clamp to the map bounds so the player cannot scroll off into empty space.

---

## Selection and Orders

### Selecting a Squad

- **Left-click** on a squad mesh → select it.
- Selected squad shows a highlight ring beneath it (a flat torus mesh or decal).
- `SquadInspector` panel opens on the right side of screen, showing all 6 grid slots and the units in them.
- Only one squad can be selected at a time.

### Moving a Squad

- With a squad selected, **right-click** on any passable cell on the map → issue a move order.
- The squad's `NavigationAgent3D` sets this as its target.
- An arrow or dotted line is drawn on the map from the squad to its destination (update each frame).
- The squad begins moving immediately. The player can issue orders to other squads while it moves.
- If the destination is impassable for the squad's movement type (e.g. water for INFANTRY), the right-click is ignored and a brief "can't go there" indicator shows.

### Clicking a Town

- **Left-click** on a friendly town → open `TownMenu`.
- **Left-click** on an enemy or neutral town → show a tooltip with town name, type, owner, and garrison (if any enemy squad is stationed there).
- A squad stationed at a town shows as "garrisoned" — it doesn't move and defends the town.

### Garrisoning

When a squad's move order destination is a friendly town and it arrives:
- Squad enters "garrisoned" state.
- Squad is not visible as a separate node; the town's flag/tower changes to show garrisoned status (e.g. a small cube on top).
- Garrisoned squads still defend: if an enemy squad tries to capture the town, a battle triggers with the garrisoned squad as defender.
- Player can "ungarrison" via the `TownMenu` → squad reappears at town position.

---

## Real-Time Loop

The overworld runs in real time. There is no turn system — all squads (player and AI) move simultaneously.

### Game Loop States (GameState.phase)

```
OVERWORLD   → Normal play. Player issues orders, AI moves, battles can trigger.
IN_BATTLE   → Tree is paused. BattleScene is shown.
PAUSED      → Player opened a menu. Tree is paused.
VICTORY     → Win condition met.
DEFEAT      → Loss condition met.
```

### Pausing

- **Spacebar** pauses/unpauses the overworld (sets `get_tree().paused`).
- Menus (TownMenu, SquadInspector edits) do not auto-pause in V1 — keep it simple.

---

## SquadInspector Panel

Always visible on the right side when a squad is selected. Dismissed when selection is cleared.

### Layout

```
┌─────────────────────────────┐
│ Squad: [Leader Name]        │
│ Faction: Player             │
├──────────────┬──────────────┤
│  [front-0]   │  [back-0]    │  Column 0
├──────────────┼──────────────┤
│  [front-1]   │  [back-1]    │  Column 1
├──────────────┼──────────────┤
│  [front-2]   │  [back-2]    │  Column 2
├──────────────┴──────────────┤
│ Move Speed: 3.2 u/s         │
│ Movement: Infantry          │
└─────────────────────────────┘
```

Each slot shows:
- Class name and level
- HP bar (green/yellow/red)
- Leader star icon if applicable
- Grayed out if slot is empty

Clicking a unit slot in the inspector opens a unit detail popup (name, full stats, attacks, XP bar, promotion status). **No editing in V1** — composition is set up before deployment.

---

## Pre-Battle Map Setup

Before the map starts (in V1, this is a simple setup screen):
1. Player sees the generated map.
2. Player's starting squads are pre-configured (hardcoded for V1 — a few sample squads).
3. Player clicks "Start" and is dropped into the overworld.
4. Enemy squads are spawned at enemy HQ and enemy-owned towns by the AI system.

---

## Map Menu (Right-Click Context)

Right-clicking with no squad selected (or on empty terrain) opens a small context menu:

- **View Terrain**: Shows terrain type and movement costs for clicked cell.
- **View Town** (if a town is at cursor): Same as left-clicking the town.

---

## Visual Feedback

| Event | Feedback |
|-------|---------|
| Squad selected | Highlight ring appears beneath squad |
| Move order issued | Dotted path line drawn to destination |
| Squad can't go there | Brief red X at click point |
| Battle triggered | Flash effect on both squads, then battle scene loads |
| Town captured | Town mesh changes color to new faction color |
| Squad wiped out | Squad node disappears with brief particle puff |
| Victory | VictoryScreen overlaid |

All of the above use simple Godot `Tween` animations or `GPUParticles3D` in V1 — nothing elaborate.
