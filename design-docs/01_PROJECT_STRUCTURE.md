# 01 — Project Structure

## Folder Layout

```
res://
├── autoloads/
│   ├── GameState.gd          # Global game state (current map, turn, faction ownership)
│   ├── UnitRegistry.gd       # All unit/class definitions loaded from data files
│   └── BattleManager.gd      # Manages battle initiation, resolution, and return to map
│
├── data/
│   ├── classes/              # One .tres (Resource) per unit class definition
│   │   ├── fighter.tres
│   │   ├── knight.tres
│   │   ├── archer.tres
│   │   ├── mage.tres
│   │   └── ...
│   └── maps/                 # Saved map configs or generation seed files (future)
│
├── scenes/
│   ├── main/
│   │   └── Main.tscn         # Root scene; loads map, HUD, camera
│   │
│   ├── map/
│   │   ├── MapGenerator.tscn # Procedural map generation root
│   │   ├── MapCell.tscn      # Single terrain tile (3D mesh + collision)
│   │   ├── TownNode.tscn     # Town/castle on the map
│   │   └── MapManager.tscn   # Autoload-adjacent: owns all cell/town refs
│   │
│   ├── squads/
│   │   ├── Squad.tscn        # One squad on the map (leader icon, nav agent)
│   │   ├── SquadUnit.tscn    # One unit within a squad (data only, no world presence)
│   │   └── SquadInspector.tscn # UI panel for viewing/editing squad composition
│   │
│   ├── battle/
│   │   ├── BattleScene.tscn  # Full-screen battle overlay
│   │   ├── BattleGrid.tscn   # 3×2 grid display for each side
│   │   ├── BattleUnit.tscn   # Visual representation of a unit during battle
│   │   └── BattleResult.tscn # End-of-battle summary popup
│   │
│   └── ui/
│       ├── HUD.tscn          # Always-on overlay: minimap, gold, turn info
│       ├── MapMenu.tscn      # Right-click / context menu on map
│       ├── TownMenu.tscn     # Menu when entering/selecting a friendly town
│       └── VictoryScreen.tscn
│
├── scripts/
│   ├── map/
│   │   ├── MapGenerator.gd
│   │   ├── MapCell.gd
│   │   ├── TownNode.gd
│   │   └── TerrainDefs.gd    # Terrain type constants and movement cost tables
│   │
│   ├── units/
│   │   ├── UnitData.gd       # Resource subclass: one unit's stats, class ref, XP
│   │   ├── ClassDefinition.gd # Resource subclass: class stats, skills, upgrade paths
│   │   └── SquadData.gd      # Resource subclass: array of UnitData + grid positions
│   │
│   ├── squads/
│   │   ├── Squad.gd          # World node: NavigationAgent3D, movement, collision
│   │   └── SquadController.gd # Handles player input → movement order
│   │
│   ├── battle/
│   │   ├── BattleResolver.gd # Pure logic: given two SquadData, produce BattleResult
│   │   ├── BattleAnimator.gd # Drives BattleScene visual playback from BattleResult
│   │   └── SkillSystem.gd    # Evaluates skill conditions, applies effects
│   │
│   ├── ai/
│   │   └── AIFaction.gd      # Enemy AI: selects squad orders each tick
│   │
│   └── ui/
│       ├── HUD.gd
│       ├── SquadInspector.gd
│       └── TownMenu.gd
│
├── resources/
│   ├── materials/
│   │   ├── terrain_grass.tres
│   │   ├── terrain_forest.tres
│   │   ├── terrain_mountain.tres
│   │   ├── terrain_water.tres
│   │   └── terrain_plains.tres
│   └── meshes/               # Simple primitive mesh libraries (optional)
│
└── project.godot
```

## Autoloads

Register these in **Project → Project Settings → Autoload**:

| Singleton Name | Script |
|---|---|
| `GameState` | `res://autoloads/GameState.gd` |
| `UnitRegistry` | `res://autoloads/UnitRegistry.gd` |
| `BattleManager` | `res://autoloads/BattleManager.gd` |

### GameState responsibilities
- Which faction owns which town/castle (`Dictionary<town_id, faction_id>`)
- List of all squads currently on the map, indexed by faction
- Current map seed and generator params
- Win condition state (have conditions been met?)
- Game phase (OVERWORLD, IN_BATTLE, VICTORY, DEFEAT)

### UnitRegistry responsibilities
- Loads all `ClassDefinition` resources from `res://data/classes/` at startup
- Provides `get_class(class_id: String) -> ClassDefinition`
- Provides `create_unit(class_id, level) -> UnitData` with stats scaled to level

### BattleManager responsibilities
- Called by `Squad.gd` when collision with enemy squad is detected
- Pauses overworld (`get_tree().paused = true`)
- Instantiates `BattleScene`, passes both `SquadData` references
- Receives `BattleResult` when scene finishes
- Applies result (unit HP changes, XP grants, kills, squad removal if wiped)
- Resumes overworld

## Scene Tree at Runtime (Overworld)

```
Main (Node3D)
├── MapManager (Node3D)
│   ├── MapCells (Node3D)          # Grid of MapCell children
│   └── TownNodes (Node3D)         # All town/castle nodes
├── Squads (Node3D)
│   ├── PlayerSquad_1 (Squad)
│   ├── PlayerSquad_2 (Squad)
│   └── EnemySquad_1 (Squad)
├── Camera (Camera3D + controller)
├── NavigationRegion3D             # Baked nav mesh for the map
└── HUD (CanvasLayer)
```

## Key Signals

Define these on the relevant nodes; other nodes connect to them:

```gdscript
# Squad.gd
signal squad_selected(squad: Squad)
signal squad_arrived(squad: Squad, destination: Vector3)
signal squad_entered_town(squad: Squad, town: TownNode)
signal squad_collided_with_enemy(squad_a: Squad, squad_b: Squad)

# TownNode.gd
signal town_captured(town: TownNode, new_faction: int)
signal town_selected(town: TownNode)

# BattleManager (autoload)
signal battle_started(attacker: SquadData, defender: SquadData)
signal battle_ended(result: BattleResult)

# GameState (autoload)
signal faction_won(faction_id: int)
```
