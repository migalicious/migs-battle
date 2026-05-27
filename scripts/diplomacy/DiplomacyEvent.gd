class_name DiplomacyEvent
extends Resource

enum EventType {
	ALLIANCE_OFFER,   # Faction asks player to ally (requires Y/N input)
	BETRAYAL,         # Allied faction turns hostile
	ENEMY_ALLIANCE,   # Two enemy factions ally against player
}

@export var event_type: EventType = EventType.BETRAYAL
@export var from_faction: int = 1
@export var to_faction: int = 0
@export var trigger_condition: String = "player_ahead"  # "player_ahead" | "player_behind" | "timer_N"
@export var description: String = ""
@export var event_id: String = ""   # unique string; prevents re-firing
