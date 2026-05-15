# 03 — Map Generation

## Overview

The map is a flat 3D grid of cells. Each cell has a terrain type that affects movement cost and provides visual variety. Towns and castles are placed after terrain generation according to placement rules.

The map is viewed from above with a 3D camera. Each cell is a 3D mesh — flat for water/plains/grass, raised box for mountains, medium box for forest.

---

## Map Parameters

```gdscript
class MapParams:
    var width: int = 32           # cells across X
    var height: int = 32          # cells across Z
    var cell_size: float = 2.0    # world units per cell
    var seed: int = 0             # 0 = random

    var water_threshold: float = 0.30     # noise below this = water
    var mountain_threshold: float = 0.72  # noise above this = mountain
    var forest_coverage: float = 0.20     # fraction of remaining land = forest

    var num_towns: int = 6
    var num_castles: int = 2              # includes the two HQs (player + enemy)
```

---

## Terrain Generation Algorithm

### Step 1 — Heightmap via Simplex Noise

Use Godot's `FastNoiseLite` with fractal octaves.

```gdscript
var noise = FastNoiseLite.new()
noise.seed = params.seed if params.seed != 0 else randi()
noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
noise.fractal_octaves = 4
noise.frequency = 0.05
```

For each cell `(x, z)`:
- `value = noise.get_noise_2d(x, z)`  → range roughly -1 to 1
- Normalize to 0–1: `value = (value + 1.0) / 2.0`

### Step 2 — Assign Base Terrain

```
value < water_threshold                   → WATER
value >= water_threshold and < 0.45      → PLAINS
value >= 0.45 and < mountain_threshold   → GRASS
value >= mountain_threshold              → MOUNTAIN
```

### Step 3 — Forest Overlay

After base terrain assignment, run a second noise pass (different seed, higher frequency). On cells classified as GRASS: if second noise value > (1.0 - forest_coverage), reclassify as FOREST.

### Step 4 — Continent Guarantee

Flood-fill from the center. If the largest land mass covers less than 40% of non-water cells, regenerate with a new seed. Prevents tiny island maps.

### Step 5 — Road Pass (Optional V1)

Connect the two HQ positions with a road. Find a path using A* on the grid (treating water and mountain as impassable, all other terrain as passable). Mark cells along this path as ROAD. Roads give fast movement to all ground-based units.

---

## Cell Mesh Generation

Each `MapCell` is a `StaticBody3D` with a `MeshInstance3D` (BoxMesh) and `CollisionShape3D`.

| Terrain | Box Height | Y Position | Material Color |
|---------|-----------|------------|----------------|
| WATER | 0.1 | -0.05 | Blue (#3a6ea5) |
| PLAINS | 0.2 | 0.0 | Yellow-green (#c8d45a) |
| GRASS | 0.2 | 0.0 | Green (#4a8c3f) |
| FOREST | 0.5 | 0.15 | Dark green (#2d5a27), small cylinder "trees" on top |
| MOUNTAIN | 1.2 | 0.5 | Grey (#8a8a8a) |
| ROAD | 0.25 | 0.025 | Tan (#c2a86a) |

Cell top surface is at `y = height / 2.0 + y_position`. Squads move on the top surface.

---

## Town and Castle Placement

### Placement Rules

1. **Player HQ**: Place in the bottom-left quadrant of the map on a land cell.
2. **Enemy HQ**: Place in the top-right quadrant on a land cell.
3. **Other castles and towns**: Scatter on land cells, at least 4 cells from any HQ and at least 3 cells from each other. Neutral on generation.
4. **No town on WATER or MOUNTAIN** cells.
5. **Flatten terrain**: Any cell assigned a town or castle becomes PLAINS terrain (remove forest, level mountain).

### Town Visual Placeholder

- `TownNode` is a `StaticBody3D` with stacked BoxMesh shapes:
  - Base: 1.5×0.4×1.5 unit box in faction color
  - Tower: 0.6×1.2×0.6 unit box centered on top
  - Flag cylinder at apex (color = owning faction)
- Castle HQ: taller tower (1.8 height), slightly larger base

### Faction Color Scheme

| Faction | Color |
|---------|-------|
| Player | Blue |
| Enemy | Red |
| Neutral | Grey |

---

## Navigation Mesh

After all cells are placed, bake a `NavigationRegion3D` over the map. Squads use `NavigationAgent3D` for pathfinding.

Water and mountain cells should be excluded from the navmesh for INFANTRY and CAVALRY movement types. Flying units bypass the navmesh and move in a straight line at reduced speed.

**Implementation note**: For V1, maintain separate navigation layers:
- Layer 1: Ground (PLAINS, GRASS, ROAD, FOREST)
- Layer 2: Ground + slow (MOUNTAIN) — not used in V1 but stub the layer
- Flying units do not use navigation at all; they lerp directly to destination

---

## MapManager

`MapManager` (a Node3D in the main scene) owns all cells and towns and exposes:

```gdscript
func get_cell(x: int, z: int) -> MapCell
func get_terrain(x: int, z: int) -> TerrainType
func world_to_grid(world_pos: Vector3) -> Vector2i
func grid_to_world(grid: Vector2i) -> Vector3      # center of cell, on top surface
func get_towns() -> Array[TownNode]
func get_towns_by_faction(faction: int) -> Array[TownNode]
func get_hq(faction: int) -> TownNode
```

---

## Terrain Movement Costs

See `TerrainDefs.gd`. Movement speed is expressed as a **multiplier on base_move_speed**.

| Terrain | INFANTRY | CAVALRY | FLYING | AQUATIC |
|---------|----------|---------|--------|---------|
| PLAINS | 1.0 | 1.2 | 0.8 | 0.5 |
| GRASS | 0.9 | 1.0 | 0.8 | 0.5 |
| ROAD | 1.3 | 1.5 | 0.8 | 0.5 |
| FOREST | 0.6 | 0.4 | 0.8 | 0.4 |
| MOUNTAIN | 0.3 | 0.2 | 0.7 | 0.3 |
| WATER | 0.0 | 0.0 | 0.7 | 1.2 |

**0.0 = impassable** (squad cannot enter, nav mesh excludes).

A squad's speed over any given cell is: `base_move_speed × terrain_multiplier`, where `base_move_speed` is taken from the slowest unit's class definition.

The squad's movement type is determined by its **leader's** class. If the leader is INFANTRY, the whole squad uses INFANTRY costs.

---

## Map Coordinate System

- Grid origin `(0, 0)` = top-left corner of map.
- World origin `(0, 0, 0)` = center of the map.
- X axis = grid X (east), Z axis = grid Z (south).
- Cell center world position: `Vector3((gx - width/2.0 + 0.5) * cell_size, 0, (gz - height/2.0 + 0.5) * cell_size)`
