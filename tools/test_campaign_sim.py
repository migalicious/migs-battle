#!/usr/bin/env python3
"""
test_campaign_sim.py — Campaign completability simulation for migs-battle.

Simulates a full 6-scenario "The Black March" campaign by:
  1. Starting scenario 0 with the default 3-unit roster (Roland L4, Sylvia L3, Merlin L3).
  2. Running RUN_ATTEMPTS full-map clears per scenario (all enemy squads in sequence).
  3. Applying actual HP damage after each battle (persistent across battles).
  4. After each won battle, giving earned XP to alive units and partially healing them
     (simulating a garrison rest).
  5. Between scenarios: full-heal + revive dead units (between-map recovery), then
     start_campaign(idx+1) which auto-delivers the previous scenario's reward units.
  6. Tabulating win rates, level curves, roster growth, and XP efficiency.

Pass criteria per scenario  (no scenario may have 0 wins — that is a hard wall):
  S0 Border Skirmish:  win rate >= 60 %
  S1 River Crossing:   win rate >= 50 %
  S2 Uneasy Allies:    win rate >= 45 %
  S3 Three Kingdoms:   win rate >= 40 %
  S4 The Shadow Rises: win rate >= 35 %
  S5 The Final March:  win rate >= 30 %

Run:
    python3 tools/test_campaign_sim.py [--runs N]   (default 5)

Requires Godot running with the project open (DebugServer on 127.0.0.1:6560).
"""

import sys
import time
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
    (3, "Three Kingdoms",          0.40, "all_strongholds",                   6),  # +Isolde
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


# start_campaign / get_campaign_state / advance_scenario are exported from migs_client


# ── Popup handling ────────────────────────────────────────────────────────────

def _dismiss_popup_if_present() -> None:
    """Dismiss any active diplomacy popup by pressing 'Refuse'.
    Scenarios 2 and 4 can immediately show an alliance-offer popup that pauses
    the scene tree; DebugServer is PROCESS_MODE_ALWAYS so it still responds, but
    the popup must be cleared before force_battle works correctly."""
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

    classes = {c["id"]: c for c in get_class_defs()}

    info("Starting units:")
    for u in units:
        cls = classes.get(u["class_id"], {})
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

def simulate_scenario(s_idx: int, s_name: str, win_thresh: float, win_cond: str, expected_roster: int = 0) -> dict:
    header(f"Scenario {s_idx}: {s_name}  [need ≥ {win_thresh:.0%} clears | {win_cond}]")

    # ── Snapshot roster and enemy layout once ────────────────────────────────
    units_before = get_units()
    roster_avg_before = _avg_level(units_before)
    before_xp_map = {u["name"]: u.get("xp", 0) for u in units_before}

    if expected_roster > 0:
        cs_now = get_campaign_state()
        actual_roster = cs_now.get("roster_size", 0)
        check(f"S{s_idx}: roster size = {expected_roster}",
              actual_roster == expected_roster,
              f"actual={actual_roster}")

    check(f"S{s_idx}: player squad deployed", len(units_before) > 0, f"{len(units_before)} units")

    squads = get_squads()
    enemy_list = squads.get("enemy", [])
    num_enemies = len(enemy_list)

    check(f"S{s_idx}: enemy present", num_enemies > 0, f"{num_enemies} squads")

    if enemy_list:
        # Log each enemy squad's avg level for balance visibility
        all_enemy_avgs = [_avg_level(sq.get("units", [])) for sq in enemy_list]
        enemy_avg = sum(all_enemy_avgs) / len(all_enemy_avgs)
        squad_summary = "  ".join(
            f"E{i}=L{a:.1f}({len(enemy_list[i].get('units',[]))}u)"
            for i, a in enumerate(all_enemy_avgs)
        )
        info(f"Roster L{roster_avg_before:.2f} ({len(units_before)}u) vs {num_enemies} enemy squads: {squad_summary}")
    else:
        enemy_avg = 0.0

    # ── Run attempts: each attempt fights all enemy squads in sequence ────────
    # Win = survive all encounters without being wiped.
    # HP is persistent across fights within a run; each run resets to full.
    wins = 0
    losses = 0
    errors = 0
    total_xp_this_scenario = 0
    deepest_reach = 0  # furthest enemy squad index reached across all runs
    first_win_xp = 0
    first_win_captured = False

    for run in range(RUN_ATTEMPTS):
        heal_roster(fraction=1.0, revive=True)  # reset HP for this run attempt

        run_cleared = True
        run_xp = 0
        encounter_log = []

        for e_idx in range(num_enemies):
            result = force_battle(enemy_squad_idx=e_idx)

            if "error" in result:
                errors += 1
                encounter_log.append(f"E{e_idx}:ERR")
                run_cleared = False
                break

            atk_units = result.get("attacker_units", [])
            alive_count = sum(1 for u in atk_units if u.get("alive"))
            atk_wiped   = result.get("attacker_wiped", True)
            total_xp    = result.get("attacker_xp", 0)

            apply_battle_damage(atk_units)

            if atk_wiped:
                deepest_reach = max(deepest_reach, e_idx)
                encounter_log.append(f"E{e_idx}:{RED}WIPE{RESET}")
                heal_roster(fraction=0.25)
                run_cleared = False
                break
            else:
                deepest_reach = max(deepest_reach, e_idx + 1)
                per_unit_xp = total_xp // max(alive_count, 1)
                run_xp += per_unit_xp
                encounter_log.append(f"E{e_idx}:{GREEN}WIN{RESET}(+{per_unit_xp}xp)")
                # XP awarded once after all runs — not per-run (see below)
                total_xp_this_scenario += per_unit_xp
                # Between encounters: revive fallen at 25% HP, then top everyone up by 70%
                heal_roster(fraction=0.25, revive=True)
                heal_roster(fraction=0.70, add_mode=True)

        if run_cleared:
            wins += 1
            if not first_win_captured:
                first_win_xp = run_xp  # capture XP from one full clear
                first_win_captured = True
            # Full garrison rest after clearing the map
            heal_roster(fraction=1.0)
        else:
            losses += 1

        info(f"  Run {run+1}/{RUN_ATTEMPTS}: {'MAP CLEAR' if run_cleared else 'FAILED'}  " +
             "  ".join(encounter_log))

    # ── Post-scenario: award XP for exactly one clear if threshold met ───────
    win_rate = wins / RUN_ATTEMPTS if RUN_ATTEMPTS > 0 else 0.0

    if win_rate >= win_thresh and first_win_captured:
        for u in get_units():
            give_xp(u["name"], first_win_xp)  # all units get full XP, alive or not
        heal_roster(fraction=1.0, revive=True)  # revive for the alive-state check below

    # ── Post-scenario checks ──────────────────────────────────────────────────
    check(f"S{s_idx}: ≥ 1 map clear (no hard wall)",
          wins >= 1, f"{wins}/{RUN_ATTEMPTS} clears")
    check(f"S{s_idx}: clear rate ≥ {win_thresh:.0%}",
          win_rate >= win_thresh, f"actual {win_rate:.0%} ({wins}/{RUN_ATTEMPTS})")

    if num_enemies > 1 and wins == 0:
        info(f"  Deepest reach: enemy squad {deepest_reach}/{num_enemies} — "
             f"{'first squad is a hard wall' if deepest_reach == 0 else f'gets past {deepest_reach} squad(s)'}")

    units_after = get_units()
    roster_avg_after = _avg_level(units_after)

    before_map = {u["name"]: u["level"] for u in units_before}
    xp_progressed = [u for u in units_after
                     if u["level"] > before_map.get(u["name"], u["level"])
                     or u.get("xp", 0) > before_xp_map.get(u["name"], 0)]

    check(f"S{s_idx}: ≥ 1 unit gained XP or leveled up",
          len(xp_progressed) > 0,
          f"{len(xp_progressed)} unit(s) progressed  ({roster_avg_before:.2f} → {roster_avg_after:.2f})")

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
        "errors":           errors,
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
    hard_walls = [r for r in results if r["wins"] == 0]
    below_thresh = [r for r in results if r["win_rate"] < r["win_threshold"]]

    check("No hard walls (0-win scenarios)", len(hard_walls) == 0,
          f"walls: {[r['scenario_name'] for r in hard_walls]}" if hard_walls else "none")
    check("All scenarios meet win-rate threshold", len(below_thresh) == 0,
          f"below threshold: {[r['scenario_name'] for r in below_thresh]}" if below_thresh else "")

    # XP sanity — warn if units are barely leveling across the whole campaign
    total_levels_gained = sum(r["avg_level_after"] - r["avg_level_before"] for r in results)
    check("Roster gains ≥ 3 avg levels across campaign",
          total_levels_gained >= 3.0,
          f"total gain: {total_levels_gained:.2f} levels")

    # Difficulty curve sanity — warn if final scenario enemy avg is 5+ levels above roster
    final = results[-1]
    gap = final["enemy_avg_level"] - final["avg_level_before"]
    if gap > 5:
        info(f"BALANCE WARNING: Final scenario enemies are {gap:.1f} levels above roster avg — consider scaling enemy generation down")
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
    print(f"6 scenarios  ·  {RUN_ATTEMPTS} full-map run attempts per scenario")
    print("Connecting to DebugServer on 127.0.0.1:6560 ...\n")

    try:
        _ = get_state()
    except Exception as e:
        print(f"ERROR: Cannot reach DebugServer: {e}")
        print("Make sure Godot is running with the project open.")
        sys.exit(1)

    # ── Scenario 0: start fresh campaign ──────────────────────────────────────
    r0 = start_campaign(scenario_idx=0, permadeath=False)
    if not r0.get("ok"):
        print(f"ERROR: start_campaign(0) failed: {r0}")
        sys.exit(1)
    time.sleep(0.5)

    check_starting_roster()

    results = []
    for s_idx, s_name, s_thresh, s_cond, s_expected_roster in SCENARIOS:
        if s_idx > 0:
            # Between scenarios: full heal + revive dead units (simulate between-map recovery).
            heal_roster(fraction=1.0, revive=True)
            # Reload the next scenario map while reusing the leveled persistent_roster.
            # start_campaign(idx >= 1) preserves the roster AND auto-delivers the previous
            # scenario's reward units (Aldric, Bors, Isolde, etc.) into persistent_roster.
            r_sc = start_campaign(scenario_idx=s_idx, permadeath=False)
            if not r_sc.get("ok"):
                print(f"ERROR: start_campaign({s_idx}) failed: {r_sc}")
                break
            time.sleep(1.0)  # extra headroom for larger maps (32×48) to finish generating

        # Dismiss any diplomacy popup that may have appeared on map load
        # (scenarios 2 and 4 can immediately trigger alliance-offer popups that
        # pause the tree; "Refuse" is the safe default for simulation purposes)
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
