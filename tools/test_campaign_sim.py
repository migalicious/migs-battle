#!/usr/bin/env python3
"""
test_campaign_sim.py — Campaign completability simulation for migs-battle.

Simulates a full 6-scenario "The Black March" campaign by:
  1. Starting scenario 0 with the default 3-unit roster (Roland L4, Sylvia L3, Merlin L3).
  2. Running BATTLES_PER_SCENARIO force_battles per scenario.
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
    python3 tools/test_campaign_sim.py [--battles N]   (default 5)

Requires Godot running with the project open (DebugServer on 127.0.0.1:6560).
"""

import sys
import time
sys.path.insert(0, ".")
from tools.migs_client import *

# ── Config ────────────────────────────────────────────────────────────────────

BATTLES_PER_SCENARIO = int(sys.argv[sys.argv.index("--battles") + 1]) if "--battles" in sys.argv else 5

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
    header(f"Scenario {s_idx}: {s_name}  [need ≥ {win_thresh:.0%} wins | {win_cond}]")

    # ── Snapshot roster before battles ──
    units_before = get_units()
    roster_avg_before = _avg_level(units_before)
    info(f"Roster avg level: {roster_avg_before:.2f}  ({len(units_before)} units)")

    # ── Inspect first enemy squad ──
    squads = get_squads()
    enemy_list = squads.get("enemy", [])
    if enemy_list:
        enemy_units_0 = enemy_list[0].get("units", [])
        enemy_avg = _avg_level(enemy_units_0)
        info(
            f"Enemy squad 0:    avg level {enemy_avg:.2f}  ({len(enemy_units_0)} units)"
            + (f"  (+ {len(enemy_list)-1} more enemy squads)" if len(enemy_list) > 1 else "")
        )
    else:
        enemy_avg = 0.0
        info("No enemy squads found on this map")

    check(f"S{s_idx}: player squad deployed", len(units_before) > 0, f"{len(units_before)} units")
    if expected_roster > 0:
        cs_now = get_campaign_state()
        actual_roster = cs_now.get("roster_size", 0)
        check(f"S{s_idx}: roster size = {expected_roster}",
              actual_roster == expected_roster,
              f"actual={actual_roster}")
    check(f"S{s_idx}: enemy present",         len(enemy_list) > 0,   f"{len(enemy_list)} squads")

    level_delta = roster_avg_before - enemy_avg
    if level_delta < -3:
        info(f"  WARNING: roster is {abs(level_delta):.1f} levels BELOW first enemy squad — "
             "may be a hard wall")
    elif level_delta > 3:
        info(f"  NOTE: roster is {level_delta:.1f} levels ABOVE first enemy — "
             "should be comfortable")

    # ── Run battles ──────────────────────────────────────────────────────────
    wins = 0
    losses = 0
    errors = 0
    total_xp_per_unit = 0

    for b in range(BATTLES_PER_SCENARIO):
        result = force_battle()

        if "error" in result:
            errors += 1
            info(f"  Battle {b+1}/{BATTLES_PER_SCENARIO}: ERROR — {result['error']}")
            continue

        atk_units_result = result.get("attacker_units", [])
        alive_after = [u for u in atk_units_result if u.get("alive")]
        dead_after  = [u for u in atk_units_result if not u.get("alive")]
        atk_wiped   = result.get("attacker_wiped", True)
        def_wiped   = result.get("defender_wiped", False)
        total_xp    = result.get("attacker_xp", 0)

        # Make battle damage persistent so later battles see worn-down units.
        apply_battle_damage(atk_units_result)

        if not atk_wiped:
            wins += 1
            # Per-unit XP = (XP_WIN_BASE + int(enemy_avg_level * XP_WIN_PER_LEVEL))
            # BattleResolver puts total_xp = per_unit * alive_count, so divide back:
            alive_count  = max(len(alive_after), 1)
            per_unit_xp  = total_xp // alive_count

            # Give XP to alive units, then simulate a garrison rest (partial heal).
            all_roster = get_units()
            for u in all_roster:
                if u.get("alive"):
                    give_xp(u["name"], per_unit_xp)
            heal_roster(fraction=0.75)

            total_xp_per_unit += per_unit_xp
            outcome = f"{GREEN}WIN {RESET}"
        else:
            losses += 1
            per_unit_xp = 0
            # Survivors limp on; dead units remain dead.
            heal_roster(fraction=0.25)
            outcome = f"{RED}LOSS{RESET}"

        info(
            f"  Battle {b+1}/{BATTLES_PER_SCENARIO}: [{outcome}]  "
            f"alive={len(alive_after)}/{len(atk_units_result)}  "
            f"dead={len(dead_after)}  "
            f"def_wiped={def_wiped}  "
            f"xp/unit={per_unit_xp}"
        )

    # ── Post-battle checks ────────────────────────────────────────────────────
    effective_battles = BATTLES_PER_SCENARIO - errors
    win_rate = wins / effective_battles if effective_battles > 0 else 0.0

    check(f"S{s_idx}: ≥ 1 win (no hard wall)",
          wins >= 1, f"{wins}/{effective_battles} wins")
    check(f"S{s_idx}: win rate ≥ {win_thresh:.0%}",
          win_rate >= win_thresh, f"actual {win_rate:.0%} ({wins}/{effective_battles})")

    # Level progression
    units_after = get_units()
    roster_avg_after = _avg_level(units_after)

    # Compare levels by name
    before_map = {u["name"]: u["level"] for u in units_before}
    leveled_up = [u for u in units_after if u["level"] > before_map.get(u["name"], u["level"])]
    survived   = [u for u in units_after if u.get("alive")]

    if wins > 0:
        check(f"S{s_idx}: ≥ 1 unit leveled up",
              len(leveled_up) > 0,
              f"{len(leveled_up)} unit(s) leveled  "
              f"({roster_avg_before:.2f} → {roster_avg_after:.2f})")
    else:
        info(f"S{s_idx}: 0 wins — skipping level-up check")

    check(f"S{s_idx}: ≥ 2 roster units alive after battles",
          len(survived) >= 2,
          f"{len(survived)}/{len(units_after)} alive")

    avg_xp_per_win = total_xp_per_unit // wins if wins > 0 else 0
    info(f"Avg XP per unit per win: {avg_xp_per_win}")
    info(f"Roster avg level after:  {roster_avg_after:.2f}")
    if leveled_up:
        info("Leveled up: " + ", ".join(
            f"{u['name']} (→ L{u['level']})" for u in leveled_up
        ))

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
        "avg_xp_per_win":   avg_xp_per_win,
        "roster_size":      len(units_before),
    }


# ── Summary ───────────────────────────────────────────────────────────────────

def print_campaign_report(results: list) -> None:
    header("CAMPAIGN COMPLETABILITY REPORT")

    col = f"  {'Scenario':<22} {'Units':>5} {'Lvl▶':>6} {'▶Lvl':>6} {'EnemyLvl':>9} {'WinRate':>8} {'WinReq':>7} {'XP/Win':>7}"
    print(col)
    print("  " + "-" * 74)

    for r in results:
        met   = r["win_rate"] >= r["win_threshold"]
        color = GREEN if met else RED
        print(
            f"  {r['scenario_name']:<22} "
            f"{r.get('roster_size', 0):>5} "
            f"{r['avg_level_before']:>6.2f} "
            f"{r['avg_level_after']:>6.2f} "
            f"{r['enemy_avg_level']:>9.2f} "
            f"{color}{r['win_rate']:>7.0%}{RESET} "
            f"{r['win_threshold']:>7.0%} "
            f"{r['avg_xp_per_win']:>7}"
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
    print(f"6 scenarios  ·  {BATTLES_PER_SCENARIO} battles per scenario")
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

    if len(results) == len(SCENARIOS):
        print_campaign_report(results)
    else:
        print(f"\nSimulation aborted after scenario {len(results) - 1}.")

    ok = print_summary()
    sys.exit(0 if ok else 1)
