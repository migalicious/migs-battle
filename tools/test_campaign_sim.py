#!/usr/bin/env python3
"""
test_campaign_sim.py — Campaign completability simulation for migs-battle.

Simulates a full 6-scenario "The Black March" campaign by:
  1. Starting scenario 0 with the default 3-unit roster.
  2. Running RUN_ATTEMPTS full-map clears per scenario in PARALLEL using a
     local Python mirror of BattleResolver (no Godot TCP calls per run).
  3. Tracking HP persistence across encounters within each run locally.
  4. After all runs: awarding XP once (from first winning run) if threshold met.
  5. Between scenarios: full-heal + start_campaign(idx+1) to deliver reward units.

Pass criteria per scenario  (no scenario may have 0 wins — that is a hard wall):
  S0 Border Skirmish:  win rate >= 60 %
  S1 River Crossing:   win rate >= 50 %
  S2 Uneasy Allies:    win rate >= 45 %
  S3 Three Kingdoms:   win rate >= 30 %
  S4 The Shadow Rises: win rate >= 35 %
  S5 The Final March:  win rate >= 30 %

Run:
    python3 tools/test_campaign_sim.py [--runs N]   (default 5)

Requires Godot running with the project open (DebugServer on 127.0.0.1:6560).
"""

import sys
import random
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
sys.path.insert(0, ".")
from tools.migs_client import *

# ── Config ────────────────────────────────────────────────────────────────────

RUN_ATTEMPTS = int(sys.argv[sys.argv.index("--runs") + 1]) if "--runs" in sys.argv else 5

SCENARIOS = [
    # (idx, name,                  win_threshold, win_conditions,              expected_roster_size)
    # expected_roster_size = units at the START of this scenario (including rewards from prior)
    (0, "Border Skirmish",         0.60, "hq_capture",                        3),
    (1, "River Crossing",          0.50, "hq_capture + all_strongholds",      4),  # +Aldric
    (2, "Uneasy Allies",           0.45, "hq_capture",                        5),  # +Bors
    (3, "Three Kingdoms",          0.30, "all_strongholds",                   6),  # +Isolde
    (4, "The Shadow Rises",        0.35, "hq_capture",                        8),  # +Leif +Caius
    (5, "The Final March",         0.30, "all_strongholds",                  10),  # +Petra +Nessa
]

# ── Colours ───────────────────────────────────────────────────────────────────

GREEN = "\033[32m"
RED   = "\033[31m"
CYAN  = "\033[36m"
RESET = "\033[0m"
PASS  = f"{GREEN}PASS{RESET}"
FAIL  = f"{RED}FAIL{RESET}"
INFO  = f"{CYAN}INFO{RESET}"

_results = []


# ── Helpers ───────────────────────────────────────────────────────────────────

def check(name: str, ok: bool, detail: str = "") -> None:
    tag = PASS if ok else FAIL
    msg = f"  [{tag}] {name}"
    if detail:
        msg += f"  — {detail}"
    print(msg)
    _results.append((name, ok))


def info(msg: str) -> None:
    print(f"  [{INFO}] {msg}")


def header(title: str) -> None:
    print(f"\n{'='*64}")
    print(f"  {title}")
    print("=" * 64)


def _avg_level(units: list) -> float:
    if not units:
        return 0.0
    return sum(u["level"] for u in units) / len(units)


# ── Python BattleSimulator ────────────────────────────────────────────────────
# Mirrors scripts/battle/BattleResolver.gd so runs execute locally in parallel.
# Constants MUST stay in sync with scripts/GameBalance.gd.

_ROUNDS         = 4
_BASE_HIT       = 0.80
_HIT_PER_AGI    = 0.02
_DEF_REDUCTION  = 0.5
_DMG_VARIANCE   = 0.10
_XP_WIN_BASE    = 45
_XP_WIN_PER_LVL = 4.0

# SkillCondition enum (SkillDefinition.gd)
_SC_ALWAYS = 0; _SC_HP_BELOW_50 = 1; _SC_HP_ABOVE_75 = 2
_SC_FIRST_ROUND = 3; _SC_LAST_ROUND = 4; _SC_ALLY_DEAD = 5
_SC_FRONT_EMPTY = 6  # _SC_ON_WATER = 7 — never true in overworld sim

# SkillEffect enum (SkillDefinition.gd)
_SE_BONUS_DMG = 0; _SE_DMG_MULT = 1; _SE_HEAL_SELF = 2; _SE_HEAL_ALLY = 3
_SE_GUARD = 4; _SE_EXTRA_ATK = 5

# TerrainDefs enums
_ROW_FRONT = 0; _ROW_BACK = 1; _ROW_ANY = 2
_DMG_PHYSICAL = 0  # non-PHYSICAL → use INT vs RES

# Module-level defs populated at startup
_CLASS_DEFS: dict = {}  # class_id → class dict (front_attacks, back_attacks, skills)
_ITEM_DEFS:  dict = {}  # item_id  → item dict (str/def/agi/int/res bonuses)


class _SUnit:
    """Mutable unit state for one simulated battle."""
    __slots__ = ("name", "class_id", "row", "col", "is_leader",
                 "hp", "max_hp", "strength", "defense", "agility",
                 "intelligence", "resistance", "is_alive", "_level",
                 "_attacks", "_skills")

    def __init__(self, d: dict) -> None:
        self.name         = d["name"]
        self.class_id     = d["class_id"]
        self.row          = d["row"]
        self.col          = d["col"]
        self.is_leader    = d.get("leader", False)
        self.hp           = d["hp"]
        self.max_hp       = d["max_hp"]
        self.strength     = d["str"]
        self.defense      = d["def"]
        self.agility      = d["agi"]
        self.intelligence = d["int"]
        self.resistance   = d.get("res", 1)
        self.is_alive     = d.get("alive", True)
        self._level       = d["level"]
        # Apply passive item stat bonuses (mirrors BattleResolver._get_stat)
        item_id = d.get("held_item", "")
        if item_id and item_id in _ITEM_DEFS:
            it = _ITEM_DEFS[item_id]
            self.strength     += it.get("str", 0)
            self.defense      += it.get("def", 0)
            self.agility      += it.get("agi", 0)
            self.intelligence += it.get("int", 0)
            self.resistance   += it.get("res", 0)
        cls = _CLASS_DEFS.get(self.class_id, {})
        self._attacks = (cls.get("front_attacks", []) if self.row == 0
                         else cls.get("back_attacks", []))
        self._skills  = cls.get("skills", [])

    @property
    def hp_frac(self) -> float:
        return self.hp / max(self.max_hp, 1)

    @property
    def is_wounded(self) -> bool:
        return self.hp_frac < 0.25


def _all_dead(units: list) -> bool:
    return all(not u.is_alive for u in units)

def _leader_dead(units: list) -> bool:
    return any(u.is_leader and not u.is_alive for u in units)

def _count_alive(units: list) -> int:
    return sum(1 for u in units if u.is_alive)

def _lowest_hp_ally(units: list):
    best, best_frac = None, 1.1
    for u in units:
        if u.is_alive and u.hp_frac < best_frac:
            best_frac, best = u.hp_frac, u
    return best

def _cond_met(sk: dict, actor: _SUnit, ctx: dict) -> bool:
    c = sk["condition"]
    if c == _SC_ALWAYS:       return True
    if c == _SC_HP_BELOW_50:  return ctx["hp_frac"] < 0.50
    if c == _SC_HP_ABOVE_75:  return ctx["hp_frac"] > 0.75
    if c == _SC_FIRST_ROUND:  return ctx["round"] == 1
    if c == _SC_LAST_ROUND:   return ctx["round"] == _ROUNDS
    if c == _SC_ALLY_DEAD:    return ctx["ally_dead"]
    if c == _SC_FRONT_EMPTY:  return ctx["enemy_front_empty"]
    return False

def _select_targets(atk: dict, enemies: list) -> list:
    alive_front = [u for u in enemies if u.is_alive and u.row == 0]
    alive_back  = [u for u in enemies if u.is_alive and u.row == 1]
    row = atk.get("row", _ROW_ANY)
    if row == _ROW_FRONT:
        pool = alive_front or alive_back
    elif row == _ROW_BACK:
        pool = alive_back or alive_front
    else:
        pool = alive_front + alive_back
    if not pool:
        return []
    if atk.get("all_row"):
        return pool
    if atk.get("all_col"):
        col = pool[0].col
        return [u for u in enemies if u.is_alive and u.col == col]
    return [random.choice(pool)]

def _calc_dmg(attacker: _SUnit, target: _SUnit, atk: dict, mult: float = 1.0) -> int:
    """Returns -1 on miss, else positive damage."""
    m = mult * (0.8 if attacker.is_wounded else 1.0)
    if atk.get("type", _DMG_PHYSICAL) == _DMG_PHYSICAL:
        stat, defense = attacker.strength, target.defense
    else:
        stat, defense = attacker.intelligence, target.resistance
    base = max(1.0, stat * atk["power"] - defense * _DEF_REDUCTION) * m
    base += base * _DMG_VARIANCE * (random.random() * 2.0 - 1.0)
    hit = max(0.5, min(1.0, _BASE_HIT + (attacker.agility - target.agility) * _HIT_PER_AGI))
    if random.random() > hit:
        return -1
    return max(1, int(base))

def _apply_guard(target: _SUnit, dmg: int) -> int:
    if dmg <= 0:
        return dmg
    ctx = {"hp_frac": target.hp_frac, "round": 0, "ally_dead": False, "enemy_front_empty": False}
    for sk in target._skills:
        if sk["effect"] == _SE_GUARD and _cond_met(sk, target, ctx):
            dmg = max(1, int(dmg * (1.0 - sk.get("dmg_red", 0.0))))
    return dmg

def _hit_target(target: _SUnit, dmg: int) -> None:
    if dmg < 0:
        return
    target.hp = max(0, target.hp - dmg)
    if target.hp <= 0:
        target.is_alive = False

def _execute_unit(unit: _SUnit, enemies: list, allies: list, round_num: int) -> None:
    alive_allies = sum(1 for u in allies if u.is_alive)
    front_alive  = sum(1 for u in enemies if u.is_alive and u.row == 0)
    ctx = {
        "round": round_num, "hp_frac": unit.hp_frac,
        "ally_dead": alive_allies < len(allies),
        "enemy_front_empty": front_alive == 0,
    }
    dmg_mult = 1.0
    for sk in unit._skills:
        if sk["effect"] == _SE_DMG_MULT and _cond_met(sk, unit, ctx):
            dmg_mult *= sk.get("power", 1.0)

    for atk in unit._attacks:
        if _all_dead(enemies):
            break
        if atk.get("is_heal", False):
            for _ in range(atk.get("hits", 1)):
                lowest = _lowest_hp_ally(allies)
                if lowest:
                    heal = max(1, int(unit.intelligence * atk["power"]))
                    lowest.hp = min(lowest.max_hp, lowest.hp + heal)
            continue
        tgts = _select_targets(atk, enemies)
        for _ in range(atk.get("hits", 1)):
            for tgt in tgts:
                if not tgt.is_alive:
                    continue
                dmg = _calc_dmg(unit, tgt, atk, dmg_mult)
                dmg = _apply_guard(tgt, dmg)
                _hit_target(tgt, dmg)

    # Post-attack skill effects
    ctx["hp_frac"] = unit.hp_frac
    ctx["ally_dead"] = sum(1 for u in allies if u.is_alive) < len(allies)
    for sk in unit._skills:
        if not _cond_met(sk, unit, ctx):
            continue
        eff = sk["effect"]
        if eff == _SE_HEAL_SELF:
            heal = max(1, int(unit.max_hp * sk.get("heal_pct", 0.0)))
            unit.hp = min(unit.max_hp, unit.hp + heal)
        elif eff == _SE_HEAL_ALLY:
            lowest = _lowest_hp_ally(allies)
            if lowest:
                heal = max(1, int(lowest.max_hp * sk.get("heal_pct", 0.0)))
                lowest.hp = min(lowest.max_hp, lowest.hp + heal)
        elif eff in (_SE_BONUS_DMG, _SE_EXTRA_ATK):
            live = [u for u in enemies if u.is_alive]
            if live:
                tgt = random.choice(live)
                fake = {"type": _DMG_PHYSICAL, "power": sk.get("power", 1.0)}
                dmg  = _calc_dmg(unit, tgt, fake)
                dmg  = _apply_guard(tgt, dmg)
                _hit_target(tgt, dmg)

def _resolve_battle(atk_units: list, def_units: list) -> dict:
    """Run 4 rounds. Returns {wiped: bool, xp_per_unit: int}."""
    for round_num in range(1, _ROUNDS + 1):
        if _all_dead(atk_units) or _all_dead(def_units):
            break
        queue = ([(u, atk_units, def_units) for u in atk_units if u.is_alive] +
                 [(u, def_units, atk_units) for u in def_units if u.is_alive])
        queue.sort(key=lambda x: x[0].agility, reverse=True)
        for unit, allies, enemies in queue:
            if not unit.is_alive:
                continue
            if _all_dead(enemies):
                break
            _execute_unit(unit, enemies, allies, round_num)

    atk_wiped  = _all_dead(atk_units) or _leader_dead(atk_units)
    def_avg_lvl = (sum(u._level for u in def_units) / len(def_units)) if def_units else 1.0
    xp = (_XP_WIN_BASE + int(def_avg_lvl * _XP_WIN_PER_LVL)) if not atk_wiped else 0
    return {"wiped": atk_wiped, "xp_per_unit": xp}

def _sim_run(atk_base: list, enemy_squads: list) -> tuple:
    """
    Simulate one full-map attempt. HP persists across encounters; each run
    starts at full HP. Returns (cleared: bool, run_xp: int, log: list[str]).
    """
    hp_state    = {d["name"]: d["max_hp"] for d in atk_base}
    alive_state = {d["name"]: True        for d in atk_base}
    run_xp = 0
    log    = []

    for e_idx, enemy_sq in enumerate(enemy_squads):
        atk = []
        for d in atk_base:
            if alive_state.get(d["name"], False):
                u = _SUnit(d)
                u.hp = hp_state[d["name"]]
                atk.append(u)
        if not atk:
            log.append(f"E{e_idx}:{RED}WIPE{RESET}")
            return False, 0, log

        def_units = [_SUnit(u) for u in enemy_sq.get("units", [])]
        result    = _resolve_battle(atk, def_units)

        if result["wiped"]:
            log.append(f"E{e_idx}:{RED}WIPE{RESET}")
            return False, 0, log

        for u in atk:
            hp_state[u.name]    = u.hp
            alive_state[u.name] = u.is_alive

        xp = result["xp_per_unit"]
        run_xp += xp
        log.append(f"E{e_idx}:{GREEN}WIN{RESET}(+{xp}xp)")

        # Between-encounter heal: revive dead @ 25%, then add 70% to all
        for d in atk_base:
            name, mhp = d["name"], d["max_hp"]
            if not alive_state[name]:
                hp_state[name]    = max(1, int(mhp * 0.25))
                alive_state[name] = True
            else:
                hp_state[name] = max(hp_state[name], int(mhp * 0.25))
            hp_state[name] = min(mhp, hp_state[name] + int(mhp * 0.70))

    return True, run_xp, log


# ── Popup handling ────────────────────────────────────────────────────────────

def _dismiss_popup_if_present() -> None:
    """Dismiss any active diplomacy popup by pressing 'Refuse'."""
    try:
        r = press_button("Refuse")
    except Exception:
        r = {"error": "no response"}
    if "error" not in r:
        info("Dismissed diplomacy popup (chose Refuse)")
        time.sleep(0.3)


# ── Section 0 — Starting roster analysis ──────────────────────────────────────

def check_starting_roster() -> None:
    header("0. Starting Roster Analysis")

    units = get_units()
    check("Roster deployed", len(units) > 0, f"{len(units)} units")

    info("Starting units:")
    for u in units:
        info(
            f"  {u['name']:10} [{u['class_name']:12}] L{u['level']:2}  "
            f"HP={u['hp']:3}/{u['max_hp']:3}  "
            f"STR={u['str']:3}  DEF={u['def']:3}  AGI={u['agi']:3}  INT={u['int']:3}"
        )

    roland = next((u for u in units if u["name"] == "Roland"), None)
    check("Roland present and is leader",
          roland is not None and roland.get("leader") is True,
          f"leader={roland.get('leader') if roland else 'missing'}")

    cs = get_campaign_state()
    check("campaign_run_active is true", cs.get("campaign_run_active") is True)
    check("Roster has 3 starting units",
          cs.get("roster_size", 0) == 3, f"size={cs.get('roster_size')}")


# ── Section 1-6 — Simulate each scenario ──────────────────────────────────────

def simulate_scenario(s_idx: int, s_name: str, win_thresh: float, win_cond: str,
                      expected_roster: int = 0) -> dict:
    header(f"Scenario {s_idx}: {s_name}  [need ≥ {win_thresh:.0%} clears | {win_cond}]")

    units_before      = get_units()
    roster_avg_before = _avg_level(units_before)
    before_xp_map     = {u["name"]: u.get("xp", 0) for u in units_before}

    if expected_roster > 0:
        cs_now        = get_campaign_state()
        actual_roster = cs_now.get("roster_size", 0)
        check(f"S{s_idx}: roster size = {expected_roster}",
              actual_roster == expected_roster, f"actual={actual_roster}")

    check(f"S{s_idx}: player squad deployed", len(units_before) > 0,
          f"{len(units_before)} units")

    squads     = get_squads()
    enemy_list = squads.get("enemy", [])
    num_enemies = len(enemy_list)
    check(f"S{s_idx}: enemy present", num_enemies > 0, f"{num_enemies} squads")

    if enemy_list:
        all_enemy_avgs = [_avg_level(sq.get("units", [])) for sq in enemy_list]
        enemy_avg      = sum(all_enemy_avgs) / len(all_enemy_avgs)
        squad_summary  = "  ".join(
            f"E{i}=L{a:.1f}({len(enemy_list[i].get('units',[]))}u)"
            for i, a in enumerate(all_enemy_avgs)
        )
        info(f"Roster L{roster_avg_before:.2f} ({len(units_before)}u) vs "
             f"{num_enemies} enemy squads: {squad_summary}")
    else:
        enemy_avg = 0.0

    # All units start at full HP for each run (tracked locally; no Godot HP writes per run)
    atk_base = [{**u, "hp": u["max_hp"], "alive": True} for u in units_before]

    # ── Parallel runs ─────────────────────────────────────────────────────────
    wins = losses = 0
    first_win_xp      = 0
    first_win_captured = False
    deepest_reach     = 0

    with ThreadPoolExecutor(max_workers=RUN_ATTEMPTS) as pool:
        future_to_idx = {pool.submit(_sim_run, atk_base, enemy_list): i
                         for i in range(RUN_ATTEMPTS)}
        indexed: dict = {}
        for future in as_completed(future_to_idx):
            indexed[future_to_idx[future]] = future.result()

    for run_idx in range(RUN_ATTEMPTS):
        cleared, run_xp, encounter_log = indexed[run_idx]
        won_count = sum(1 for e in encounter_log if "WIN" in e)
        deepest_reach = max(deepest_reach, won_count)
        if cleared:
            wins += 1
            if not first_win_captured:
                first_win_xp       = run_xp
                first_win_captured = True
        else:
            losses += 1
        info(f"  Run {run_idx+1}/{RUN_ATTEMPTS}: "
             f"{'MAP CLEAR' if cleared else 'FAILED'}  " +
             "  ".join(encounter_log))

    # ── Post-scenario: award XP for one clear if threshold met ────────────────
    win_rate = wins / RUN_ATTEMPTS if RUN_ATTEMPTS > 0 else 0.0

    if win_rate >= win_thresh and first_win_captured:
        for u in get_units():
            give_xp(u["name"], first_win_xp)
        heal_roster(fraction=1.0, revive=True)

    # ── Post-scenario checks ──────────────────────────────────────────────────
    check(f"S{s_idx}: ≥ 1 map clear (no hard wall)",
          wins >= 1, f"{wins}/{RUN_ATTEMPTS} clears")
    check(f"S{s_idx}: clear rate ≥ {win_thresh:.0%}",
          win_rate >= win_thresh, f"actual {win_rate:.0%} ({wins}/{RUN_ATTEMPTS})")

    if num_enemies > 1 and wins == 0:
        info(f"  Deepest reach: enemy squad {deepest_reach}/{num_enemies} — "
             f"{'first squad is a hard wall' if deepest_reach == 0 else f'gets past {deepest_reach} squad(s)'}")

    units_after       = get_units()
    roster_avg_after  = _avg_level(units_after)
    before_map        = {u["name"]: u["level"] for u in units_before}
    xp_progressed     = [u for u in units_after
                         if u["level"] > before_map.get(u["name"], u["level"])
                         or u.get("xp", 0) > before_xp_map.get(u["name"], 0)]

    check(f"S{s_idx}: ≥ 1 unit gained XP or leveled up",
          len(xp_progressed) > 0,
          f"{len(xp_progressed)} unit(s) progressed  "
          f"({roster_avg_before:.2f} → {roster_avg_after:.2f})")

    survived = [u for u in units_after if u.get("alive")]
    check(f"S{s_idx}: ≥ 2 roster units alive after runs",
          len(survived) >= 2, f"{len(survived)}/{len(units_after)} alive")

    avg_xp_per_fight = first_win_xp // max(num_enemies, 1)
    info(f"Avg XP per unit per fight: {avg_xp_per_fight}  (across {num_enemies} encounters/run)")
    info(f"Roster avg level after:    {roster_avg_after:.2f}")

    leveled_up = [u for u in xp_progressed if u["level"] > before_map.get(u["name"], u["level"])]
    if leveled_up:
        info("Leveled up: " + ", ".join(f"{u['name']} (→ L{u['level']})" for u in leveled_up))
    else:
        info("XP gained: " + ", ".join(
            f"{u['name']} (+{u.get('xp',0) - before_xp_map.get(u['name'],0)}xp)"
            for u in xp_progressed[:5]))

    return {
        "scenario_idx":     s_idx,
        "scenario_name":    s_name,
        "wins":             wins,
        "losses":           losses,
        "errors":           0,
        "win_rate":         win_rate,
        "win_threshold":    win_thresh,
        "avg_level_before": roster_avg_before,
        "avg_level_after":  roster_avg_after,
        "enemy_avg_level":  enemy_avg,
        "avg_xp_per_fight": avg_xp_per_fight,
        "roster_size":      len(units_before),
        "num_enemies":      num_enemies,
        "passed":           win_rate >= win_thresh,
    }


# ── Summary ───────────────────────────────────────────────────────────────────

def print_campaign_report(results: list) -> None:
    header("CAMPAIGN COMPLETABILITY REPORT")

    col = f"  {'Scenario':<22} {'Units':>5} {'Enems':>5} {'Lvl▶':>6} {'▶Lvl':>6} {'EnemyLvl':>9} {'Clear%':>7} {'Req':>5} {'XP/Fgt':>7}"
    print(col)
    print("  " + "-" * 78)

    for r in results:
        met   = r["win_rate"] >= r["win_threshold"]
        color = GREEN if met else RED
        print(
            f"  {r['scenario_name']:<22} "
            f"{r.get('roster_size', 0):>5} "
            f"{r.get('num_enemies', 0):>5} "
            f"{r['avg_level_before']:>6.2f} "
            f"{r['avg_level_after']:>6.2f} "
            f"{r['enemy_avg_level']:>9.2f} "
            f"{color}{r['win_rate']:>6.0%}{RESET} "
            f"{r['win_threshold']:>5.0%} "
            f"{r['avg_xp_per_fight']:>7}"
        )

    print()
    hard_walls   = [r for r in results if r["wins"] == 0]
    below_thresh = [r for r in results if r["win_rate"] < r["win_threshold"]]

    check("No hard walls (0-win scenarios)", len(hard_walls) == 0,
          f"walls: {[r['scenario_name'] for r in hard_walls]}" if hard_walls else "none")
    check("All scenarios meet win-rate threshold", len(below_thresh) == 0,
          f"below threshold: {[r['scenario_name'] for r in below_thresh]}" if below_thresh else "")

    total_levels_gained = sum(r["avg_level_after"] - r["avg_level_before"] for r in results)
    check("Roster gains ≥ 1.5 avg levels across campaign",
          total_levels_gained >= 1.5,
          f"total gain: {total_levels_gained:.2f} levels")

    final = results[-1]
    gap   = final["enemy_avg_level"] - final["avg_level_before"]
    if gap > 5:
        info(f"BALANCE WARNING: Final scenario enemies are {gap:.1f} levels above roster avg")
    elif gap < -3:
        info(f"NOTE: Final scenario enemies are {abs(gap):.1f} levels below roster — may be too easy")
    else:
        info(f"Final scenario level gap: {gap:+.1f} (roster vs enemy) — looks balanced")


def print_summary() -> bool:
    header("OVERALL SUMMARY")
    passed = sum(1 for _, ok in _results if ok)
    failed = sum(1 for _, ok in _results if not ok)
    total  = len(_results)
    print(f"\n  {passed}/{total} checks passed,  {failed} failed\n")
    if failed:
        print("  Failed checks:")
        for name, ok in _results:
            if not ok:
                print(f"    {RED}✗{RESET} {name}")
    return failed == 0


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("migs-battle  ·  Campaign Completability Simulation")
    print(f"6 scenarios  ·  {RUN_ATTEMPTS} full-map run attempts per scenario  "
          f"(parallel Python sim)")
    print("Connecting to DebugServer on 127.0.0.1:6560 ...\n")

    try:
        _ = get_state()
    except Exception as e:
        print(f"ERROR: Cannot reach DebugServer: {e}")
        print("Make sure Godot is running with the project open.")
        sys.exit(1)

    # Populate class and item defs once — used by all scenario sims
    _CLASS_DEFS.update({c["id"]: c for c in get_class_defs()})
    _ITEM_DEFS.update({it["id"]: it for it in get_item_defs()})
    if not _CLASS_DEFS:
        print("WARNING: No class definitions loaded — sim will use stat-only combat.")

    # Start fresh campaign
    r0 = start_campaign(scenario_idx=0, permadeath=False)
    if not r0.get("ok"):
        print(f"ERROR: start_campaign(0) failed: {r0}")
        sys.exit(1)
    time.sleep(0.5)

    check_starting_roster()

    results = []
    for s_idx, s_name, s_thresh, s_cond, s_expected_roster in SCENARIOS:
        if s_idx > 0:
            heal_roster(fraction=1.0, revive=True)
            r_sc = start_campaign(scenario_idx=s_idx, permadeath=False)
            if not r_sc.get("ok"):
                print(f"ERROR: start_campaign({s_idx}) failed: {r_sc}")
                break
            time.sleep(1.0)

        _dismiss_popup_if_present()

        r = simulate_scenario(s_idx, s_name, s_thresh, s_cond, s_expected_roster)
        results.append(r)
        if not r.get("passed", True):
            print(f"\n  Scenario {s_idx} did not meet win-rate threshold — stopping simulation.")
            break

    if len(results) == len(SCENARIOS):
        print_campaign_report(results)
    else:
        print(f"\nSimulation aborted after scenario {len(results) - 1}.")

    ok = print_summary()
    sys.exit(0 if ok else 1)
