#!/usr/bin/env python3
"""
migs_client.py — DebugServer client for migs-battle.

Import everything:
    from tools.migs_client import *

CLI:
    python3 tools/migs_client.py state
    python3 tools/migs_client.py units
    python3 tools/migs_client.py squads
    python3 tools/migs_client.py inventory
    python3 tools/migs_client.py item_defs
    python3 tools/migs_client.py class_defs
    python3 tools/migs_client.py battle [N]
    python3 tools/migs_client.py towns
    python3 tools/migs_client.py inject <class_id> [level] [row]
    python3 tools/migs_client.py give_item <item_id> [qty]
    python3 tools/migs_client.py set_gold <amount>
    python3 tools/migs_client.py give_xp <unit_name> <amount>
    python3 tools/migs_client.py capture <town_id> [faction]
"""

import json
import socket
import sys
import time

HOST = "127.0.0.1"
PORT = 6560

# ---------------------------------------------------------------------------
# Enum maps (mirror GDScript)
# ---------------------------------------------------------------------------

BATTLE_ACTION   = {0: "ATTACK", 1: "HEAL", 2: "SKILL", 3: "MISS", 4: "KILL"}
SKILL_CONDITION = {0: "ALWAYS", 1: "HP_BELOW_50", 2: "HP_ABOVE_75",
                   3: "FIRST_ROUND", 4: "LAST_ROUND", 5: "ALLY_DEAD",
                   6: "ENEMY_FRONT_EMPTY", 7: "ON_WATER"}
SKILL_EFFECT    = {0: "BONUS_DAMAGE", 1: "DAMAGE_MULTIPLIER", 2: "HEAL_SELF",
                   3: "HEAL_ALLY", 4: "GUARD", 5: "EXTRA_ATTACK",
                   6: "STAT_BUFF_SELF", 7: "STAT_DEBUFF_ENEMY"}
ITEM_TYPE       = {0: "passive", 1: "consumable"}
DAMAGE_TYPE     = {0: "Physical", 1: "Fire", 2: "Cold", 3: "Thunder", 4: "Holy", 5: "Dark"}
TARGET_ROW      = {0: "FRONT", 1: "BACK", 2: "ANY"}
MOVE_TYPE       = {0: "Infantry", 1: "Cavalry", 2: "Flying", 3: "Aquatic"}
FACTION         = {0: "player", 1: "enemy", -1: "neutral"}


# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------

def send(cmd: dict, delay: float = 0.4) -> dict:
    """Send one JSON command over raw TCP and return the parsed response."""
    s = socket.socket()
    s.connect((HOST, PORT))
    s.sendall((json.dumps(cmd) + "\n").encode())
    time.sleep(delay)
    data = b""
    s.settimeout(3.0)
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    except socket.timeout:
        pass
    s.close()
    return json.loads(data.decode())


# ---------------------------------------------------------------------------
# UI actions
# ---------------------------------------------------------------------------

def press_button(text: str) -> dict:
    return send({"action": "press_button", "text": text})

def click(x: float, y: float) -> dict:
    return send({"action": "click", "x": x, "y": y})

def right_click(x: float, y: float) -> dict:
    return send({"action": "right_click", "x": x, "y": y})

def open_town(town_id: str) -> dict:
    return send({"action": "open_town", "town_id": town_id})

def screenshot(path: str = "/tmp/migs_screenshot.png") -> dict:
    return send({"action": "screenshot", "path": path}, delay=0.6)

def get_scene_tree() -> list:
    return send({"action": "scene_tree"}).get("tree", [])


# ---------------------------------------------------------------------------
# Game flow helpers (compose UI actions)
# ---------------------------------------------------------------------------

def play_again() -> dict:
    """Press Play Again from the Main scene."""
    return press_button("Play Again")

def new_game() -> dict:
    """From TitleScreen: New Game → Generate Map → Start Battle. Returns final state."""
    press_button("New Game")
    time.sleep(0.5)
    press_button("Generate Map")
    time.sleep(0.5)
    press_button("Start Battle")
    time.sleep(1.5)
    return get_state()

def setup_squad(pairs: list) -> None:
    """
    Configure the Army Builder squad.
    pairs = [("Roland", "F-0"), ("Gawain", "F-1"), ...]
    Slots: F-0, F-1, F-2 (front row), B-0, B-1, B-2 (back row).
    """
    for name, slot in pairs:
        press_button(name)
        time.sleep(0.15)
        press_button(slot)
        time.sleep(0.15)


# ---------------------------------------------------------------------------
# Game state queries
# ---------------------------------------------------------------------------

def get_state() -> dict:
    """High-level state: scene, phase, gold, squad/town counts."""
    return send({"action": "state"})

def get_towns() -> list:
    """All towns with world and screen coordinates."""
    return send({"action": "towns"}).get("towns", [])

def get_units() -> list:
    """
    All deployed + reserve player units with full stats and skills.
    Each entry: name, class_id, class_name, level, hp, max_hp,
                str, agi, int, def, res, held_item, alive, leader,
                row, col, xp, xp_to_next, skills[].
    """
    return send({"action": "units"}).get("units", [])

def get_squads() -> dict:
    """
    All squads keyed by side: {"player": [...], "reserve": [...], "enemy": [...]}.
    Each squad: {"id": str, "units": [<same shape as get_units()>]}.
    """
    return send({"action": "squads"})

def get_inventory() -> dict:
    """
    Player gold + inventory.
    Returns {"gold": int, "inventory": [{id, name, qty, type, str, agi, ...}]}.
    """
    return send({"action": "inventory"})

def get_item_defs() -> list:
    """All item definitions from ItemRegistry."""
    return send({"action": "item_defs"}).get("items", [])

def get_class_defs() -> list:
    """
    All class definitions from UnitRegistry.
    Each entry: id, name, base stats, move_type, deploy_cost, can_lead,
                front_attacks[], back_attacks[], skills[].
    """
    return send({"action": "class_defs"}).get("classes", [])


# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

def equip_item(unit_name: str, item_id: str) -> dict:
    """Equip an item to a unit (removes it from inventory)."""
    return send({"action": "equip_item", "unit": unit_name, "item": item_id})

def give_item(item_id: str, qty: int = 1) -> dict:
    """Add qty copies of item_id to player inventory."""
    return send({"action": "give_item", "item": item_id, "qty": qty})

def set_gold(amount: int) -> dict:
    """Set player gold to amount."""
    return send({"action": "set_gold", "amount": amount})

def inject_unit(class_id: str, level: int = 1, row: int = 0) -> dict:
    """
    Add a unit of class_id/level to the first player squad on the map.
    row=0 = front, row=1 = back.
    """
    return send({"action": "inject_unit", "class_id": class_id, "level": level, "row": row})

def give_xp(unit_name: str, amount: int) -> dict:
    """Add XP to a unit and trigger level-ups. Returns new xp, level, levels_gained."""
    return send({"action": "give_xp", "unit": unit_name, "amount": amount})

def capture_town(town_id: str, faction: int = 0) -> dict:
    """
    Force town ownership. faction: 0=player, 1=enemy, -1=neutral.
    Updates both GameState and the TownNode visuals.
    """
    return send({"action": "capture_town", "town_id": town_id, "faction": faction})


# ---------------------------------------------------------------------------
# Battle
# ---------------------------------------------------------------------------

def force_battle() -> dict:
    """
    Run BattleResolver.resolve() between the first player and enemy squads.
    Returns: attacker_wiped, defender_wiped, attacker_xp, defender_xp,
             attacker_units[], defender_units[], log[].
    """
    return send({"action": "force_battle"}, delay=0.8)


# ---------------------------------------------------------------------------
# Pretty-printers
# ---------------------------------------------------------------------------

def _bonuses(it: dict) -> str:
    parts = []
    for stat in ("str", "agi", "int", "def", "res", "hp"):
        v = it.get(stat, 0)
        if v:
            parts.append(f"+{v} {stat.upper()}")
    if it.get("heal_pct", 0):
        parts.append(f"+{it['heal_pct'] * 100:.0f}% heal")
    return ", ".join(parts) or "—"

def print_units(units: list) -> None:
    for u in units:
        skills = ", ".join(
            f'{s["name"]}({SKILL_EFFECT.get(s["effect"], "?")}/'
            f'{SKILL_CONDITION.get(s["condition"], "?")})'
            for s in u.get("skills", [])
        )
        item = u["held_item"] or "—"
        alive = "" if u["alive"] else " [DEAD]"
        print(
            f'  {u["name"]:10} [{u["class_name"]:15}] Lv{u["level"]:2}{alive}  '
            f'HP {u["hp"]:3}/{u["max_hp"]:3}  '
            f'STR {u["str"]:3} AGI {u["agi"]:3} INT {u["int"]:3} '
            f'DEF {u["def"]:3} RES {u["res"]:3}  '
            f'item={item:<16} [{skills}]'
        )

def print_squads(squads: dict) -> None:
    for side in ("player", "reserve", "enemy"):
        entries = squads.get(side, [])
        if not entries:
            continue
        print(f"\n=== {side.upper()} ===")
        for sq in entries:
            print(f"Squad {sq['id']}:")
            print_units(sq["units"])

def print_inventory(data: dict = None) -> None:
    if data is None:
        data = get_inventory()
    print(f"Gold: {data.get('gold', 0)}")
    items = data.get("inventory", [])
    if not items:
        print("  (empty)")
        return
    for it in items:
        typ = ITEM_TYPE.get(it.get("type", 0), "?")
        print(f'  {it["qty"]}×  {it.get("name", it["id"]):<22} [{typ:11}]  {_bonuses(it)}')

def print_item_defs(items: list = None) -> None:
    if items is None:
        items = get_item_defs()
    for it in items:
        typ = ITEM_TYPE.get(it.get("type", 0), "?")
        print(f'  {it["id"]:<22} [{typ:11}] {it.get("cost", 0):5}g  {_bonuses(it)}')

def print_class_defs(classes: list = None) -> None:
    if classes is None:
        classes = get_class_defs()
    for cls in sorted(classes, key=lambda c: c["deploy_cost"]):
        lead = "★ " if cls["can_lead"] else "  "
        move = MOVE_TYPE.get(cls["move_type"], "?")
        print(f'\n{lead}[{cls["id"]}] {cls["name"]}  {cls["deploy_cost"]}g  {move}')
        print(f'    Base: HP={cls["base_hp"]} STR={cls["base_str"]} AGI={cls["base_agi"]} '
              f'INT={cls["base_int"]} DEF={cls["base_def"]} RES={cls["base_res"]}')
        for label, attacks in [("Front", cls.get("front_attacks", [])),
                                ("Back",  cls.get("back_attacks",  []))]:
            for a in attacks:
                dt = DAMAGE_TYPE.get(a.get("type", 0), "?")
                tr = TARGET_ROW.get(a.get("row",  0), "?")
                flags = []
                if a.get("all_row"): flags.append("all-row")
                if a.get("all_col"): flags.append("all-col")
                if a.get("cond"):    flags.append(f'cond={a["cond"]}')
                tag = f'  [{" ".join(flags)}]' if flags else ""
                print(f'    {label}: {a["name"]} ×{a["hits"]} {dt:<9} {tr:<6} '
                      f'×{a["power"]:.1f}{tag}')
        for sk in cls.get("skills", []):
            eff  = SKILL_EFFECT.get(sk.get("effect", 0), "?")
            cond = SKILL_CONDITION.get(sk.get("condition", 0), "?")
            print(f'    Skill: {sk["name"]} [{eff}/{cond}]  — {sk["desc"]}')

def print_battle_result(r: dict) -> None:
    if "error" in r:
        print(f"ERROR: {r['error']}")
        return
    print(
        f"Result: atk_wiped={r['attacker_wiped']}  def_wiped={r['defender_wiped']}"
        f"  XP atk={r['attacker_xp']} def={r['defender_xp']}"
    )
    log = r.get("log", [])
    skill_heal = [e for e in log if e["type"] in (1, 2)]
    print(f"Log: {len(log)} entries  SKILL/HEAL: {len(skill_heal)}")
    if skill_heal:
        print("\nSKILL / HEAL entries:")
        for e in skill_heal:
            t = BATTLE_ACTION.get(e["type"], str(e["type"]))
            print(f'  [{t:6}] {e["actor"]:12} -> {e["target"]:12}  "{e["attack"]}"  dmg={e["dmg"]}')
    print("\nFull log:")
    for e in log:
        t = BATTLE_ACTION.get(e["type"], str(e["type"]))
        print(f'  [{t:6}] {e["actor"]:12} -> {e["target"]:12}  "{e["attack"]}"  dmg={e["dmg"]}')
    print("\nAttacker post-battle:")
    print_units(r.get("attacker_units", []))
    print("\nDefender post-battle:")
    print_units(r.get("defender_units", []))


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def _cli():
    args = sys.argv[1:]
    cmd  = args[0] if args else "state"

    if cmd == "state":
        print(json.dumps(get_state(), indent=2))

    elif cmd == "units":
        print_units(get_units())

    elif cmd == "squads":
        print_squads(get_squads())

    elif cmd == "inventory":
        print_inventory()

    elif cmd == "item_defs":
        print_item_defs()

    elif cmd == "class_defs":
        print_class_defs()

    elif cmd == "battle":
        n = int(args[1]) if len(args) > 1 else 1
        for i in range(n):
            if n > 1:
                print(f"\n{'='*60}\nBattle {i + 1}/{n}")
            print_battle_result(force_battle())

    elif cmd == "towns":
        for t in get_towns():
            owner = FACTION.get(t.get("faction", -2), "?")
            coastal = " [COASTAL]" if t.get("has_aquatic_recruit") else ""
            print(f'  {t["id"]:20}  faction={owner:7}  world=({t["wx"]:.0f}, {t["wz"]:.0f})'
                  f'  screen=({t["sx"]:.0f}, {t["sy"]:.0f}){coastal}')

    elif cmd == "inject":
        if len(args) < 2:
            print("Usage: inject <class_id> [level=1] [row=0]")
            sys.exit(1)
        r = inject_unit(args[1], int(args[2]) if len(args) > 2 else 1,
                                 int(args[3]) if len(args) > 3 else 0)
        print(r)

    elif cmd == "give_item":
        if len(args) < 2:
            print("Usage: give_item <item_id> [qty=1]")
            sys.exit(1)
        r = give_item(args[1], int(args[2]) if len(args) > 2 else 1)
        print(r)

    elif cmd == "set_gold":
        if len(args) < 2:
            print("Usage: set_gold <amount>")
            sys.exit(1)
        r = set_gold(int(args[1]))
        print(r)

    elif cmd == "give_xp":
        if len(args) < 3:
            print("Usage: give_xp <unit_name> <amount>")
            sys.exit(1)
        r = give_xp(args[1], int(args[2]))
        print(r)

    elif cmd == "capture":
        if len(args) < 2:
            print("Usage: capture <town_id> [faction=0]  (0=player 1=enemy -1=neutral)")
            sys.exit(1)
        r = capture_town(args[1], int(args[2]) if len(args) > 2 else 0)
        print(r)

    else:
        print(f"Unknown command: {cmd}")
        print(
            "Commands:\n"
            "  state | units | squads | inventory | item_defs | class_defs\n"
            "  battle [N] | towns\n"
            "  inject <class_id> [level] [row]\n"
            "  give_item <item_id> [qty] | set_gold <amount>\n"
            "  give_xp <unit_name> <amount> | capture <town_id> [faction]"
        )
        sys.exit(1)


if __name__ == "__main__":
    _cli()
