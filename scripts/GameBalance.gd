extends Node

const ROUNDS: int = 4
const BASE_HIT_CHANCE: float = 0.80
const HIT_CHANCE_PER_AGI: float = 0.02
const DEFENSE_REDUCTION: float = 0.5
const DAMAGE_VARIANCE: float = 0.10
const XP_WIN_BASE: int = 45
const XP_WIN_PER_LEVEL: float = 4.0
const XP_LOSE_BASE: int = 5
const XP_LOSE_PER_LEVEL: float = 1.0
const XP_THRESHOLD_BASE: int = 100
const GOLD_TICK_INTERVAL: float = 10.0
const TOWN_INCOME: int = 20
const CASTLE_INCOME: int = 40
const HQ_INCOME: int = 60
const AI_TICK_INTERVAL: float = 8.0
const AI_THREAT_RADIUS: float = 12.0
const AI_REINFORCE_GOLD_THRESHOLD: int = 200
const AI_MAX_SQUADS: int = 4
const AI_GARRISON_CASTLES: int = 2  # nearest neutral castles each faction claims+garrisons at spawn
const AI_MAX_ROAMERS: int = 3       # roaming squads per faction (additive to HQ/castle garrisons)
const BETWEEN_MAP_RECOVER_COST: int = 50
const GARRISON_HEAL_RATE: float = 0.10  # fraction of max_hp recovered per second (PLAYER garrisons only)

# Post-battle recoil. When a battle ends with neither side wiped, both squads are briefly
# invulnerable to re-collision and the loser slides away — preventing zero-input machine-gun
# re-battles between two squads left physically stacked on the same tile.
const BATTLE_INVULN_TIME: float = 1.0   # seconds both squads ignore re-collision after a battle
const KNOCKBACK_TIME: float = 0.3       # seconds the loser slides
const KNOCKBACK_DIST: float = 2.5       # world units pushed (> DetectionArea 1.1 and BLOCK_RANGE 1.6)
