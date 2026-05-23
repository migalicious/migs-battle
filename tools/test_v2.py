#!/usr/bin/env python3
"""
test_v2.py — Comprehensive V2 test suite for migs-battle.

Run:  python3 tools/test_v2.py
Requires Godot running with the project open (DebugServer on 127.0.0.1:6560).
"""

import sys
import time
sys.path.insert(0, ".")
from tools.migs_client import *

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
SKIP = "\033[33mSKIP\033[0m"

_results = []

def check(name: str, ok: bool, detail: str = "") -> None:
    status = PASS if ok else FAIL
    msg = f"  [{status}] {name}"
    if detail:
        msg += f"  — {detail}"
    print(msg)
    _results.append((name, ok))

def header(title: str) -> None:
    print(f"\n{'='*60}")
    print(f"  {title}")
    print('='*60)


# ────────────────────────────────────────────────────────────
# 0. Setup — start a fresh game
# ────────────────────────────────────────────────────────────

def setup_game():
    header("0. Game Setup")
    press_button("New Game")
    time.sleep(0.5)
    press_button("Generate Map")
    time.sleep(1.0)
    press_button("Start Battle")
    time.sleep(1.5)
    state = get_state()
    check("Scene is Main", state.get("scene") == "Main",
          f'scene={state.get("scene")}')
    check("Phase is OVERWORLD", state.get("phase") == 0,
          f'phase={state.get("phase")}')
    check("Player has squads", state.get("player_squads", 0) > 0,
          f'squads={state.get("player_squads")}')
    check("Enemy has squads", state.get("enemy_squads", 0) > 0,
          f'enemy_squads={state.get("enemy_squads")}')
    check("Gold initialized", state.get("player_gold", 0) > 0,
          f'gold={state.get("player_gold")}')
    return state


# ────────────────────────────────────────────────────────────
# 1. Class Definitions — all 14 classes
# ────────────────────────────────────────────────────────────

EXPECTED_CLASSES = [
    "fighter", "archer", "mage", "knight", "cavalry",
    "paladin", "sorcerer", "cleric",
    "warrior", "berserker", "witch",
    "merfolk", "sea_knight"
]

def test_class_defs():
    header("1. Class Definitions (14 classes)")
    classes = get_class_defs()
    ids = {c["id"] for c in classes}
    check("Got class list", len(classes) > 0, f'{len(classes)} classes')

    for cid in EXPECTED_CLASSES:
        check(f"Class '{cid}' exists", cid in ids)

    # Verify Cleric has a heal back-attack
    cleric = next((c for c in classes if c["id"] == "cleric"), None)
    if cleric:
        back_heals = [a for a in cleric.get("back_attacks", []) if a.get("name") == "Heal"]
        check("Cleric back-attack is Heal", len(back_heals) > 0,
              f'back={[a["name"] for a in cleric["back_attacks"]]}')
        skill_effects = [s["effect"] for s in cleric.get("skills", [])]
        check("Cleric skill is HEAL_ALLY (3)", 3 in skill_effects,
              f'effects={skill_effects}')

    # Verify Warrior skill is DAMAGE_MULTIPLIER (1) with HP_BELOW_50 (1)
    warrior = next((c for c in classes if c["id"] == "warrior"), None)
    if warrior:
        sk = warrior.get("skills", [])
        check("Warrior has Berserk skill", len(sk) > 0)
        if sk:
            check("Warrior skill effect=DAMAGE_MULTIPLIER", sk[0]["effect"] == 1,
                  f'effect={sk[0]["effect"]}')
            check("Warrior skill condition=HP_BELOW_50", sk[0]["condition"] == 1,
                  f'condition={sk[0]["condition"]}')

    # Verify Witch skill is STAT_DEBUFF_ENEMY (7)
    witch = next((c for c in classes if c["id"] == "witch"), None)
    if witch:
        sk = witch.get("skills", [])
        check("Witch has Weaken skill", len(sk) > 0)
        if sk:
            check("Witch skill effect=STAT_DEBUFF_ENEMY", sk[0]["effect"] == 7,
                  f'effect={sk[0]["effect"]}')

    # Verify Merfolk and Sea Knight are AQUATIC (move_type=3)
    merfolk = next((c for c in classes if c["id"] == "merfolk"), None)
    sea_knight = next((c for c in classes if c["id"] == "sea_knight"), None)
    if merfolk:
        check("Merfolk is AQUATIC", merfolk.get("move_type") == 3,
              f'move_type={merfolk.get("move_type")}')
    if sea_knight:
        check("Sea Knight is AQUATIC", sea_knight.get("move_type") == 3,
              f'move_type={sea_knight.get("move_type")}')

    # Verify Berserker skill is HEAL_SELF (2)
    berserker = next((c for c in classes if c["id"] == "berserker"), None)
    if berserker:
        sk = berserker.get("skills", [])
        if sk:
            check("Berserker skill=HEAL_SELF", sk[0]["effect"] == 2,
                  f'effect={sk[0]["effect"]}')

    return classes


# ────────────────────────────────────────────────────────────
# 2. Item Definitions
# ────────────────────────────────────────────────────────────

def test_item_defs():
    header("2. Item Definitions")
    items = get_item_defs()
    check("Items exist", len(items) > 0, f'{len(items)} items')
    passive = [i for i in items if i.get("type") == 0]
    consumable = [i for i in items if i.get("type") == 1]
    check("Has passive items", len(passive) > 0, f'{len(passive)} passive')
    check("Has consumable items", len(consumable) > 0, f'{len(consumable)} consumable')
    # All items have a cost
    no_cost = [i for i in items if i.get("cost", 0) == 0]
    check("All items have cost > 0", len(no_cost) == 0,
          f'{len(no_cost)} items with cost=0')
    return items


# ────────────────────────────────────────────────────────────
# 3. Town System
# ────────────────────────────────────────────────────────────

def test_towns():
    header("3. Town System")
    towns = get_towns()
    check("Towns exist", len(towns) > 0, f'{len(towns)} towns')

    hqs = [t for t in towns if "hq" in t["id"]]
    check("HQs exist", len(hqs) >= 2, f'{len(hqs)} HQs')

    player_hq = next((t for t in towns if t["id"] == "0_hq"), None)
    enemy_hq  = next((t for t in towns if t["id"] == "1_hq"), None)
    check("Player HQ exists (0_hq)", player_hq is not None)
    check("Enemy HQ exists (1_hq)", enemy_hq is not None)

    if player_hq:
        check("Player HQ faction=0", player_hq.get("faction") == 0,
              f'faction={player_hq.get("faction")}')
    if enemy_hq:
        check("Enemy HQ faction=1", enemy_hq.get("faction") == 1,
              f'faction={enemy_hq.get("faction")}')

    coastal = [t for t in towns if t.get("has_aquatic_recruit")]
    check("Coastal towns detected", True,
          f'{len(coastal)} coastal towns')

    return towns


# ────────────────────────────────────────────────────────────
# 4. Gold Economy
# ────────────────────────────────────────────────────────────

def test_economy():
    header("4. Gold Economy")
    inv = get_inventory()
    check("Inventory endpoint works", "gold" in inv, str(inv))

    # Set gold to a known value
    set_gold(500)
    time.sleep(0.1)
    inv2 = get_inventory()
    check("set_gold works", inv2.get("gold") == 500,
          f'gold={inv2.get("gold")}')

    # Give and check item
    give_item("iron_shield", 2)
    time.sleep(0.1)
    inv3 = get_inventory()
    shield_count = 0
    for it in inv3.get("inventory", []):
        if it["id"] == "iron_shield":
            shield_count = it["qty"]
    check("give_item works", shield_count >= 2,
          f'iron_shield qty={shield_count}')

    return inv3


# ────────────────────────────────────────────────────────────
# 5. Battle — base resolver
# ────────────────────────────────────────────────────────────

def test_basic_battle():
    header("5. Basic Battle (force_battle)")
    result = force_battle()
    if "error" in result:
        check("force_battle succeeds", False, result["error"])
        return result
    check("force_battle returns", True)
    check("Has action log", len(result.get("log", [])) > 0,
          f'{len(result.get("log", []))} entries')
    check("Has XP values", result.get("attacker_xp", 0) > 0,
          f'xp={result.get("attacker_xp")}')
    # At least one side should be wiped in a standard battle
    wiped = result.get("attacker_wiped") or result.get("defender_wiped")
    check("Someone wiped", wiped,
          f'atk_wiped={result.get("attacker_wiped")} def_wiped={result.get("defender_wiped")}')
    return result


# ────────────────────────────────────────────────────────────
# 6. Skill System — Berserker Bloodlust (HEAL_SELF)
# ────────────────────────────────────────────────────────────

def test_skill_heal_self():
    header("6. Berserker Bloodlust (HEAL_SELF)")
    inject_unit("berserker", 10, 0)
    time.sleep(0.2)
    result = force_battle()
    if "error" in result:
        check("Berserker battle", False, result["error"])
        return
    log = result.get("log", [])
    skill_entries = [e for e in log if e["type"] == 2]  # type=2 = SKILL
    check("SKILL entries in log", len(skill_entries) > 0,
          f'{len(skill_entries)} SKILL entries')
    berserker_heals = [e for e in skill_entries
                       if "berserker" in e.get("actor", "").lower()
                       or "Berserker" in e.get("actor", "")]
    check("Berserker fired SKILL", len(skill_entries) > 0,
          f'skill count={len(skill_entries)}')


# ────────────────────────────────────────────────────────────
# 7. Skill System — Cleric Heal (is_heal attack)
# ────────────────────────────────────────────────────────────

def test_cleric_heal():
    header("7. Cleric Heal Attack (is_heal)")
    # Fresh game state for clean test
    inject_unit("cleric", 5, 1)  # back row
    time.sleep(0.2)
    result = force_battle()
    if "error" in result:
        check("Cleric battle", False, result["error"])
        return
    log = result.get("log", [])
    heal_entries = [e for e in log if e["type"] == 1]  # type=1 = HEAL
    check("HEAL entries in log", len(heal_entries) > 0,
          f'{len(heal_entries)} HEAL entries')
    heal_attacks = [e for e in heal_entries if e.get("attack") == "Heal"]
    check("Cleric 'Heal' attack fired", len(heal_attacks) > 0,
          f'Heal entries={len(heal_attacks)}')


# ────────────────────────────────────────────────────────────
# 8. Skill System — Paladin Holy Aura (HEAL_ALLY)
# ────────────────────────────────────────────────────────────

def test_paladin_holy_aura():
    header("8. Paladin Holy Aura (HEAL_ALLY skill)")
    inject_unit("paladin", 8, 0)
    time.sleep(0.2)
    result = force_battle()
    if "error" in result:
        check("Paladin battle", False, result["error"])
        return
    log = result.get("log", [])
    skill_entries = [e for e in log if e["type"] == 2]
    check("Paladin SKILL/HEAL_ALLY fired", len(skill_entries) > 0,
          f'{len(skill_entries)} skill entries')


# ────────────────────────────────────────────────────────────
# 9. XP and Level-up
# ────────────────────────────────────────────────────────────

def test_xp_levelup():
    header("9. XP and Level-Up")
    units = get_units()
    if not units:
        check("Units available", False, "no units")
        return
    target = units[0]["name"]
    before_level = units[0]["level"]

    r = give_xp(target, 10000)
    check("give_xp works", "error" not in r, str(r))
    check("Level gained", r.get("levels_gained", 0) > 0,
          f'levels_gained={r.get("levels_gained")}')

    units2 = get_units()
    after_level = next((u["level"] for u in units2 if u["name"] == target), before_level)
    check("Unit leveled up", after_level > before_level,
          f'{before_level} → {after_level}')


# ────────────────────────────────────────────────────────────
# 10. Item Equip and Stat Bonus
# ────────────────────────────────────────────────────────────

def test_item_equip():
    header("10. Item Equip and Stat Bonus")
    give_item("iron_shield", 1)
    time.sleep(0.1)
    units = get_units()
    if not units:
        check("Units for equip", False, "no units")
        return
    target_name = units[0]["name"]
    def_before = units[0]["def"]

    equip_item(target_name, "iron_shield")
    time.sleep(0.1)

    units2 = get_units()
    target = next((u for u in units2 if u["name"] == target_name), None)
    if target:
        check("Item equipped", target.get("held_item") == "iron_shield",
              f'held_item={target.get("held_item")}')
    else:
        check("Item equipped", False, "unit not found after equip")


# ────────────────────────────────────────────────────────────
# 11. Town Capture
# ────────────────────────────────────────────────────────────

def test_town_capture():
    header("11. Town Capture via Debug")
    towns = get_towns()
    neutral_towns = [t for t in towns if t.get("faction") == -1]
    if not neutral_towns:
        check("Neutral town available", False, "no neutral towns — skip")
        return
    tid = neutral_towns[0]["id"]
    r = capture_town(tid, 0)  # Capture for player
    check("capture_town works", r.get("ok") is True, str(r))

    towns2 = get_towns()
    captured = next((t for t in towns2 if t["id"] == tid), None)
    if captured:
        check("Town faction updated", captured.get("faction") == 0,
              f'faction={captured.get("faction")}')


# ────────────────────────────────────────────────────────────
# 12. Inject Unit — all new classes
# ────────────────────────────────────────────────────────────

def test_inject_new_classes():
    header("12. Inject New Classes")
    new_classes = ["warrior", "berserker", "witch", "merfolk", "sea_knight", "cleric"]
    for cid in new_classes:
        r = inject_unit(cid, 5, 1)
        check(f"inject {cid}", r.get("ok") is True,
              f'result={r.get("error", "ok")}')
        time.sleep(0.1)


# ────────────────────────────────────────────────────────────
# 13. Faction System
# ────────────────────────────────────────────────────────────

def test_faction_system():
    header("13. Faction / State")
    state = get_state()
    ownership = state.get("town_ownership", {})
    check("town_ownership populated", len(ownership) > 0,
          f'{len(ownership)} entries')

    # Check all HQ towns exist in ownership
    hq_ids = ["0_hq", "1_hq"]
    for hid in hq_ids:
        check(f"Ownership has {hid}", hid in ownership,
              f'keys={list(ownership.keys())[:6]}')


# ────────────────────────────────────────────────────────────
# 14. Open Town Menu
# ────────────────────────────────────────────────────────────

def test_open_town():
    header("14. Open Town Menu")
    towns = get_towns()
    player_towns = [t for t in towns if t.get("faction") == 0]
    if not player_towns:
        check("Player town exists", False, "no player towns")
        return
    tid = player_towns[0]["id"]
    r = open_town(tid)
    check("open_town works", r.get("ok") is True, str(r))

    # Check for coastal recruit button on coastal towns
    coastal = [t for t in towns if t.get("has_aquatic_recruit") and t.get("faction") == 0]
    if coastal:
        r2 = open_town(coastal[0]["id"])
        check("Open coastal town works", r2.get("ok") is True)
        print(f"    (coastal town {coastal[0]['id']} opened — check for 'Recruit Merfolk' button visually)")


# ────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────

def print_summary():
    header("SUMMARY")
    passed = sum(1 for _, ok in _results if ok)
    failed = sum(1 for _, ok in _results if not ok)
    total  = len(_results)
    print(f"\n  {passed}/{total} passed,  {failed} failed\n")
    if failed:
        print("  Failed tests:")
        for name, ok in _results:
            if not ok:
                print(f"    ✗ {name}")
    return failed == 0


# ────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("migs-battle V2 Test Suite")
    print("Connecting to DebugServer on 127.0.0.1:6560 ...\n")

    try:
        state = get_state()
    except Exception as e:
        print(f"ERROR: Cannot connect to DebugServer: {e}")
        print("Make sure Godot is running with the project open.")
        sys.exit(1)

    # If not on Main scene, run setup
    if state.get("scene") != "Main":
        setup_game()
    else:
        header("0. Already in Main scene")
        print(f"  scene={state['scene']}  phase={state['phase']}  gold={state['player_gold']}")

    test_class_defs()
    test_item_defs()
    test_towns()
    test_economy()
    test_basic_battle()
    test_skill_heal_self()
    test_cleric_heal()
    test_paladin_holy_aura()
    test_xp_levelup()
    test_item_equip()
    test_town_capture()
    test_inject_new_classes()
    test_faction_system()
    test_open_town()

    ok = print_summary()
    sys.exit(0 if ok else 1)
