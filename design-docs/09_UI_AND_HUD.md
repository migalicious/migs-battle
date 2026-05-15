# 09 — UI and HUD

## Architecture

All UI is built with Godot's `Control` nodes inside a `CanvasLayer` (so it renders above 3D). The main HUD is always present during overworld play. Panels open/close on top of it.

```
HUD (CanvasLayer)
├── TopBar              # Turn timer, faction info (future)
├── MinimapPanel        # Bottom-left minimap
├── SquadInspector      # Right side, visible when squad selected
├── TownMenu            # Center popup, shown on town click
├── BattleScene         # Full-screen overlay during battle
└── VictoryScreen       # Full-screen overlay on win/loss
```

---

## HUD (Always Visible)

### Top Bar
- Left: Game title / map name placeholder
- Center: Status text ("Overworld" / "Battle" / "Paused")
- Right: [Pause button] [Menu button]

### Bottom Bar
- Left: Selected entity name + quick stats (when something is selected)
- Right: Minimap

### Minimap

A top-down 2D representation of the map using a `SubViewport` or a custom drawn `Control`:
- Terrain shown as colored pixels (matching terrain colors from §03)
- Towns shown as small colored dots (faction color)
- Player squads shown as blue triangles
- Enemy squads shown as red triangles
- Camera viewport rectangle drawn as a white outline

Size: 200×200 px, bottom-right corner.

---

## Squad Inspector (Right Panel)

Opens when a squad is selected. Width ~260px, anchored to right edge.

```
┌────────────────────────────┐
│ ★ Sir Roland               │  ← Leader name, star icon
│ Knight  Lv.8               │  ← Class and level
├────────────────────────────┤
│ FRONT ROW                  │
│ [Slot 0,0] [Slot 0,1] [Slot 0,2] │
│ BACK ROW                   │
│ [Slot 1,0] [Slot 1,1] [Slot 1,2] │
├────────────────────────────┤
│ Movement: Infantry         │
│ Speed: 3.2 u/s             │
└────────────────────────────┘
```

### Unit Slot

Each slot is a `Panel` (80×80 px) containing:
- Unit's class placeholder color as background
- Class name (small text, top)
- Level (small text, top-right corner)
- HP bar (bottom of slot, full-width, green→yellow→red)
- Leader star (top-left, only for leader slot)
- Greyed-out overlay if slot is empty

Clicking a slot opens the **Unit Detail Popup**.

### Unit Detail Popup

A centered modal popup (400×300 px):
```
┌──────────────────────────────────────┐
│ [Class Name]  Level [N]              │
│ [Placeholder colored box]            │
├──────────────────────────────────────┤
│ HP: 45/50     STR: 12  AGI: 8        │
│ INT: 4        DEF: 10  RES: 5        │
│ XP: 80/900 ████████░░ (progress bar) │
├──────────────────────────────────────┤
│ ATTACKS                              │
│ Front: Slash ×2 (Physical)           │
│ Back:  Slash ×1 (Physical)           │
├──────────────────────────────────────┤
│ Promotion: → Paladin at Lv.15        │
│ [Close]                              │
└──────────────────────────────────────┘
```

---

## Town Menu

Opens on left-click of a friendly town. Centered modal, 340×260 px.

```
┌───────────────────────────────────┐
│ [Town Name]          [Type: Town] │
│ Owner: Player                     │
├───────────────────────────────────┤
│ Garrison: [Squad name or "None"]  │
│                                   │
│ [Deploy Squad ▼]  [Ungarrison]    │
│                                   │
│ (Deploy Squad opens roster below) │
└───────────────────────────────────┘
```

If the town is enemy/neutral (info only view):
```
┌───────────────────────────────────┐
│ [Town Name]          [Type: Castle]│
│ Owner: Enemy                      │
│ Garrison: Template B              │
│ Capture Time: 3 ticks             │
│                            [Close]│
└───────────────────────────────────┘
```

### Deploy Squad Roster (Sub-panel)

Expands below or replaces the town menu when "Deploy Squad" is clicked. Shows all squads not currently on the map:

```
┌───────────────────────────────────┐
│ SELECT SQUAD TO DEPLOY            │
├───────────────────────────────────┤
│ [Squad A] ★ Knight Lv8  6 units   │
│ [Squad B] ★ Mage Lv6    4 units   │
│ [Squad C] ★ Cavalry Lv5 3 units   │
├───────────────────────────────────┤
│                          [Cancel] │
└───────────────────────────────────┘
```

Clicking a squad deploys it and closes the menu.

---

## Battle Scene (Full Screen Overlay)

Covers the entire screen. Background: dark semi-transparent panel over a blurred(ish) overworld.

### Layout (1920×1080 reference)

```
┌────────────────────────────────────────────────────────┐
│  ATTACKER: Squad A            DEFENDER: Enemy Squad B  │
│                                                        │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │ [U][U][U]            │  │            [U][U][U] │    │
│  │ [U][U][ ]  FRONT  ←→ FRONT  [ ][U][U] │    │
│  │ [U][U][U]            │  │            [U][U][U] │    │
│  │           BACK        BACK           │    │
│  └──────────────────────┘  └──────────────────────┘    │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Action Log:                                      │  │
│  │ > Sir Roland attacks Orc Fighter! 14 damage.     │  │
│  │ > Orc Mage casts Magic! 22 damage. (MISS)        │  │
│  └──────────────────────────────────────────────────┘  │
│                                              [Skip >>]  │
└────────────────────────────────────────────────────────┘
```

Each `[U]` is a 80×80 px colored cube icon with HP bar beneath. Dead units show greyed and tilted.

Damage numbers float up from target and fade (Tween animation).

### Battle Result Banner

After all rounds, show:
```
┌────────────────────────────────┐
│        ★ VICTORY! ★           │
│  or    ✕ DEFEAT               │
│                                │
│  XP Gained: +45               │
│  Level Up: Sir Roland → Lv.9  │
│                                │
│              [Continue]        │
└────────────────────────────────┘
```

---

## Victory / Defeat Screen

Full-screen overlay.

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│              ★ VICTORY! ★                             │
│         You have captured all strongholds.             │
│                                                        │
│              [Play Again]    [Quit]                    │
│                                                        │
└────────────────────────────────────────────────────────┘
```

Or "DEFEAT — The enemy has captured your HQ."

---

## Input Map (project.godot settings)

Define these in **Project → Project Settings → Input Map**:

| Action | Default Key |
|--------|-------------|
| `camera_pan_left` | A |
| `camera_pan_right` | D |
| `camera_pan_up` | W |
| `camera_pan_down` | S |
| `camera_zoom_in` | Mouse Wheel Up |
| `camera_zoom_out` | Mouse Wheel Down |
| `select` | Left Mouse Button |
| `order` | Right Mouse Button |
| `pause` | Space |
| `deselect` | Escape |
| `ui_confirm` | Enter |
| `ui_cancel` | Escape |

---

## Fonts and Styling (V1 Minimal)

Use Godot's default font for V1. Define a `theme.tres` with:
- Background panels: dark grey (`#1a1a2e`) with slight transparency
- Borders: 1px `#4a4a6a`
- Text: white `#f0f0f0` primary, grey `#a0a0c0` secondary
- Accent: gold `#f0c040` for leader names and victory text
- HP bar: green→yellow→red gradient based on hp% (set in code via `ProgressBar.modulate`)
- Faction colors: Player = `#4080ff`, Enemy = `#ff4040`, Neutral = `#808080`
