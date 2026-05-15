# Project Overview — Untitled Ogre Battle / Unicorn Overlord Clone

## Vision

A real-time strategy game played on a fully 3D procedurally generated map. The player deploys squads of up to 6 units onto the map, selects destinations for each squad, and watches them move in real time. When two opposing squads collide, a turn-based auto-resolved battle occurs between them. The goal is to capture towns and castles across the map, ultimately seizing the enemy's main stronghold.

Inspired by:
- **Ogre Battle: The March of the Black Queen** (SNES/PS1) — squad composition, front/back row, terrain-based movement, overworld strategy
- **Unicorn Overlord** (Vanillaware, 2024) — unified battle/overworld map, skill-based auto-battle, map objectives as deploy and rally points

## Technology

- **Engine**: Godot 4.x
- **Dimensionality**: 3D with an overhead camera (orthographic or perspective, configurable)
- **Art**: Primitive shapes (cubes, capsules, cylinders) as placeholders throughout V1
- **Language**: GDScript

## Document Index

| File | Contents |
|------|----------|
| `00_PROJECT_OVERVIEW.md` | This file. Vision, scope, document map. |
| `01_PROJECT_STRUCTURE.md` | Godot project folder layout, scene hierarchy, autoloads |
| `02_DATA_MODEL.md` | All game data: units, classes, squads, towns, map cells |
| `03_MAP_GENERATION.md` | Procedural map generator: terrain types, layout rules, town/castle placement |
| `04_UNIT_AND_SQUAD_SYSTEM.md` | Unit stats, class system, squad composition, movement types |
| `05_OVERWORLD_GAMEPLAY.md` | Camera, squad selection, movement orders, real-time map loop |
| `06_BATTLE_SYSTEM.md` | Collision detection, battle grid, auto-resolution, skill/condition framework |
| `07_TOWN_AND_CAPTURE_SYSTEM.md` | Town/castle types, capture mechanics, deploy points, income |
| `08_AI_SYSTEM.md` | Enemy AI faction: squad behavior, objective prioritization, difficulty |
| `09_UI_AND_HUD.md` | All UI scenes: HUD, squad inspector, battle viewer, map menus |
| `10_WIN_LOSS_AND_GAME_FLOW.md` | Victory conditions, defeat, stage transitions, save structure |
| `11_IMPLEMENTATION_ORDER.md` | Recommended build order for Claude Code, milestone checklist |

## V1 Scope (In)

- Procedural 3D map with terrain types (grass, forest, mountain, water, plains)
- Town and castle nodes (player-owned, enemy-owned, neutral)
- Unit data: stats, class, movement type
- Unit class system with progression (a small starter set of classes)
- XP and leveling
- Squad system: up to 6 units per squad, 3×2 grid (front row / back row, 3 columns)
- Real-time overworld movement with terrain-based speed modifiers
- Collision-triggered auto-battle between squads
- Battle auto-resolution: front/back row targeting, attack order, damage formula
- Town capture and deploy mechanic
- Player vs. one AI faction
- Win by capturing enemy HQ or all towns/castles
- Placeholder 3D graphics (primitives)

## V2+ Scope (Out for now)

- Multiple AI factions with diplomacy / alliance system
- Full world map with handcrafted stage layout
- Aquatic-specific unit movement (stub the type in V1 data, don't implement nav)
- Tarot / item system
- Alignment / morale system
- Gold economy and shop
- Sound and music
- Save/load to disk
