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
const TOWN_INCOME: int = 15
const CASTLE_INCOME: int = 30
const HQ_INCOME: int = 50
const AI_TICK_INTERVAL: float = 8.0
const AI_THREAT_RADIUS: float = 12.0
const AI_REINFORCE_GOLD_THRESHOLD: int = 200
const AI_MAX_SQUADS: int = 4
const AI_GARRISON_CASTLES: int = 2  # nearest neutral castles each faction claims+garrisons at spawn
const AI_MAX_ROAMERS: int = 3       # roaming squads per faction (additive to HQ/castle garrisons)
const BETWEEN_MAP_RECOVER_COST: int = 50
const GARRISON_HEAL_RATE: float = 0.10  # fraction of max_hp recovered per second while garrisoned
