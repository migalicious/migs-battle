#!/usr/bin/env python3
"""
play_campaign.py — REAL-overworld campaign playtest for migs-battle.

Unlike tools/test_campaign_sim.py (which reimplements BattleResolver in Python and
only simulates combat math), this script PLAYS THE LIVE GAME like a human:

  * sets up each scenario with start_campaign() (lands in a real Main overworld),
  * issues real move orders to live squads (move_squad -> Squad.set_destination),
  * lets the engine drive navigation -> collisions -> BattleManager battles ->
    town captures -> GameState.check_win_conditions(),
  * observes the real outcome (VICTORY / DEFEAT) and advances.

So it exercises the actual gameplay loop end-to-end — the parts the local sim never
touched. Tactics are deliberately simple ("greedy: grab the nearest objective"); the
goal is coverage and finding stalls/soft-locks, not optimal play.

Requires the game running with the project open (DebugServer on 127.0.0.1:6560).

Launch options:
  * Auto-launch (recommended): have Claude start the game with the godot-mcp
    `run_project` tool and confirm "[DebugServer] Listening" via `get_debug_output`,
    then run this script.
  * Manual: open the project in the Godot editor and press Play, then run this script.

Run:
    python3 tools/play_campaign.py [--runs N] [--speed S] [--permadeath] [--scenario K]
        --runs N       attempts per scenario before giving up        (default 1)
        --speed S      Engine.time_scale while playing               (default 6.0)
        --permadeath   play on permadeath difficulty                 (default off)
        --scenario K   only play scenario K (0-5) instead of all
"""

import sys
import time
sys.path.insert(0, ".")
from tools.migs_client import (
    send, overworld, move_squad, set_time_scale,
    start_campaign, get_campaign_state, heal_roster, press_button, get_relations,
)

# ── Config ──────────────────────────────────────────────────────────────────────

def _arg(flag, default, cast=str):
    return cast(sys.argv[sys.argv.index(flag) + 1]) if flag in sys.argv else default

RUNS        = _arg("--runs", 1, int)
SPEED       = _arg("--speed", 6.0, float)
PERMADEATH  = "--permadeath" in sys.argv
ONLY_SCEN   = _arg("--scenario", -1, int)

# Phase enum (GameState.Phase)
P_OVERWORLD, P_IN_BATTLE, P_PAUSED, P_VICTORY, P_DEFEAT = 0, 1, 2, 3, 4

CAPTURE_HOLD_RADIUS = 2.5    # don't re-task a squad parked this close to a town it's taking
POLL_DELAY          = 0.20   # wall-clock seconds between overworld snapshots
SETUP_TIMEOUT       = 12.0   # wait this long for a scenario to land in OVERWORLD
SCENARIO_TIMEOUT    = _arg("--timeout", 240.0, float)  # give up on a scenario after this much wall-clock
STALL_TICKS         = 60     # consecutive unchanged polls => declared stall

SCENARIOS = [
    (0, "Border Skirmish"),
    (1, "River Crossing"),
    (2, "Uneasy Allies"),
    (3, "Three Kingdoms"),
    (4, "The Shadow Rises"),
    (5, "The Final March"),
]

# ── Colours / logging ───────────────────────────────────────────────────────────

GREEN, RED, CYAN, YELLOW, RESET = (
    "\033[32m", "\033[31m", "\033[36m", "\033[33m", "\033[0m")
PASS, FAIL, INFO = f"{GREEN}PASS{RESET}", f"{RED}FAIL{RESET}", f"{CYAN}INFO{RESET}"

_results = []

def check(name, ok, detail=""):
    print(f"  [{PASS if ok else FAIL}] {name}" + (f"  — {detail}" if detail else ""))
    _results.append((name, ok))

def info(msg):
    print(f"  [{INFO}] {msg}")

def header(title):
    print(f"\n{'='*66}\n  {title}\n{'='*66}")

# ── Geometry / world-state helpers ──────────────────────────────────────────────

def _dist2(ax, az, bx, bz):
    dx, dz = ax - bx, az - bz
    return dx * dx + dz * dz

def _player_squads(ow):
    return [s for s in ow.get("squads", []) if s["faction"] == 0]

def _ownership_sig(ow):
    """A hashable signature of map control + squad positions, for stall detection."""
    own = tuple(sorted((k, v) for k, v in ow.get("town_ownership", {}).items()))
    pos = tuple(sorted((s["id"], round(s["x"], 1), round(s["z"], 1))
                       for s in _player_squads(ow)))
    return (own, pos)

def _capturable_towns(ow):
    return [t for t in ow.get("towns", []) if t.get("capturable_by_player")
            and t["faction"] != 0]

def _hostile_enemy_squads(ow):
    return [s for s in ow.get("squads", []) if s["faction"] != 0
            and s.get("hostile_to_player")]

def _nearest(items, x, z):
    return min(items, key=lambda i: _dist2(x, z, i["x"], i["z"])) if items else None

# ── One greedy decision tick ────────────────────────────────────────────────────

STUCK_LIMIT   = 12  # idle+unmoved ticks before a squad blacklists its target & reroutes
NUDGE_COOLDOWN = 5  # ticks between re-trigger nudges on a parked-but-not-capturing squad

def _drive_tick(ow, mem):
    """
    Issue move orders to all idle player squads. `mem` holds per-squad routing
    state {id: {last_pos, stuck, blacklist}} so we can route around targets a
    squad can't reach (e.g. a town across impassable water).

    Strategy: assault the enemy HQ first (that's the win for hq_capture and a
    necessary stronghold for all_strongholds); fall back to other capturable
    towns, then to chasing a hostile squad. Combat is gated on town assaults —
    roaming enemies rarely collide — so we keep pushing onto enemy-held towns.
    """
    towns   = _capturable_towns(ow)
    enemies = _hostile_enemy_squads(ow)
    orders  = 0

    for sq in _player_squads(ow):
        if sq["in_battle"] or sq["is_moving"]:
            continue  # busy — let it finish

        st = mem.setdefault(sq["id"],
                            {"last_pos": None, "stuck": 0, "nudge": 0, "blacklist": set()})

        # Squad parked on a capturable town.
        near_town = _nearest(ow.get("towns", []), sq["x"], sq["z"])
        if near_town and _dist2(sq["x"], sq["z"], near_town["x"], near_town["z"]) \
                <= CAPTURE_HOLD_RADIUS ** 2 \
                and near_town["faction"] != 0 and near_town.get("capturable_by_player"):
            st["stuck"] = 0
            if near_town.get("capture_owner") == 0:
                # Capture already in progress — HOLD. Re-issuing a move would
                # re-fire arrival -> begin_capture and reset the progress.
                st["nudge"] = 0
                continue
            # Parked but NOT capturing (e.g. just won the garrison battle, or
            # arrived just shy of the trigger). Re-trigger arrival on a cooldown
            # so we don't thrash, which would also reset an in-progress capture.
            st["nudge"] += 1
            if st["nudge"] >= NUDGE_COOLDOWN:
                st["nudge"] = 0
                move_squad(sq["id"], town_id=near_town["id"])
                orders += 1
            continue

        # Stuck detection: idle and position unchanged since last order.
        pos = (round(sq["x"], 1), round(sq["z"], 1))
        st["stuck"] = st["stuck"] + 1 if st["last_pos"] == pos else 0
        st["last_pos"] = pos

        candidates = [t for t in towns if t["id"] not in st["blacklist"]]
        if not candidates:                      # blacklisted everything — reset
            st["blacklist"].clear()
            candidates = towns

        # Prefer enemy HQs (town type 2), else nearest capturable town.
        hqs = [t for t in candidates if t.get("type") == 2]
        pool = hqs if hqs else candidates
        target = _nearest(pool, sq["x"], sq["z"])

        # If we've been unable to reach the current target, blacklist + reroute.
        if target and st["stuck"] >= STUCK_LIMIT:
            st["blacklist"].add(target["id"])
            st["stuck"] = 0
            rest = [t for t in candidates if t["id"] != target["id"]]
            target = _nearest(rest, sq["x"], sq["z"]) or target

        if target:
            move_squad(sq["id"], town_id=target["id"])
            orders += 1
        elif enemies:
            e = _nearest(enemies, sq["x"], sq["z"])
            move_squad(sq["id"], pos=(e["x"], e["z"]))
            orders += 1
    return orders

def _dismiss_popup():
    """Best-effort dismissal of a diplomacy popup (chooses Refuse)."""
    try:
        r = press_button("Refuse")
        if "error" not in r:
            info("Dismissed diplomacy popup (Refuse)")
            return True
    except Exception:
        pass
    return False

# ── Play one scenario attempt ────────────────────────────────────────────────────

def play_attempt(s_idx, s_name):
    """Play the live overworld until VICTORY / DEFEAT / stall / timeout."""
    # Wait for the scenario to be set up and land in the overworld.
    t0 = time.time()
    ow = {}
    while time.time() - t0 < SETUP_TIMEOUT:
        ow = overworld()
        if ow.get("phase") == P_OVERWORLD and _player_squads(ow):
            break
        time.sleep(0.3)
    if not _player_squads(ow):
        return {"outcome": "no_squads", "ticks": 0}

    set_time_scale(SPEED)

    conds = ow.get("active_conditions", [])
    info(f"Overworld up: {len(_player_squads(ow))} player squad(s), "
         f"{len(ow.get('towns', []))} towns, win={conds}")

    last_sig, stall = None, 0
    captures, battles_resolved = 0, 0
    route_mem = {}
    start = time.time()

    while time.time() - start < SCENARIO_TIMEOUT:
        ow = overworld()
        phase = ow.get("phase", P_OVERWORLD)

        if phase == P_VICTORY:
            return {"outcome": "victory", "winner": ow.get("winner"), "ticks": stall,
                    "captures": captures, "battles": battles_resolved, "ow": ow}
        if phase == P_DEFEAT:
            return {"outcome": "defeat", "winner": ow.get("winner"), "ticks": stall,
                    "captures": captures, "battles": battles_resolved, "ow": ow}

        # A battle is playing — it ends on a "Continue" result screen that waits for
        # a human click. Press it to return to the overworld (no-op until shown).
        # A battle is always progress, so it never counts toward a stall.
        if phase == P_IN_BATTLE:
            r = press_button("Continue")
            if isinstance(r, dict) and "error" not in r:
                battles_resolved += 1
            stall = 0
            time.sleep(POLL_DELAY)
            continue

        # A paused overworld (not a battle) is almost always a diplomacy popup.
        if ow.get("paused") and phase == P_OVERWORLD:
            _dismiss_popup()
            time.sleep(POLL_DELAY)
            continue

        if phase == P_OVERWORLD:
            _drive_tick(ow, route_mem)

        # Stall detection on map control + squad positions.
        sig = _ownership_sig(ow)
        player_towns = sum(1 for v in ow.get("town_ownership", {}).values() if v == 0)
        captures = max(captures, player_towns)
        if sig == last_sig:
            stall += 1
        else:
            stall = 0
            last_sig = sig
        if stall >= STALL_TICKS:
            return {"outcome": "stall", "ticks": stall, "captures": captures,
                    "battles": battles_resolved, "ow": ow}

        time.sleep(POLL_DELAY)

    return {"outcome": "timeout", "ticks": stall, "captures": captures,
            "battles": battles_resolved, "ow": ow}

# ── Scenario driver (handles setup + retries) ────────────────────────────────────

def play_scenario(s_idx, s_name, first):
    header(f"Scenario {s_idx}: {s_name}")

    # Set up the scenario. idx 0 fully resets; idx>0 carries the leveled roster +
    # delivers the previous scenario's reward units (mirrors real campaign advance).
    if not first:
        heal_roster(fraction=1.0, revive=not PERMADEATH)  # between-map recovery
    start_campaign(scenario_idx=s_idx, permadeath=PERMADEATH)
    time.sleep(1.0)

    cs = get_campaign_state()
    info(f"Roster size at start: {cs.get('roster_size')}  "
         f"gold={cs.get('player_gold')}  permadeath={cs.get('difficulty_permadeath')}")

    result = {}
    for attempt in range(1, RUNS + 1):
        if attempt > 1:
            info(f"Retry {attempt}/{RUNS} — re-setting up scenario")
            heal_roster(fraction=1.0, revive=not PERMADEATH)
            start_campaign(scenario_idx=s_idx, permadeath=PERMADEATH)
            time.sleep(1.0)
        result = play_attempt(s_idx, s_name)
        oc = result["outcome"]
        tag = (GREEN if oc == "victory" else
               YELLOW if oc in ("stall", "timeout") else RED)
        info(f"Attempt {attempt}: {tag}{oc.upper()}{RESET}  "
             f"player_towns={result.get('captures', 0)}  "
             f"battles={result.get('battles', '?')}")
        if oc == "victory":
            break

    oc = result.get("outcome")
    check(f"S{s_idx} ({s_name}): reached a real win/lose state",
          oc in ("victory", "defeat"),
          f"outcome={oc}")
    check(f"S{s_idx} ({s_name}): cleared the scenario (real win conditions fired)",
          oc == "victory",
          f"winner={result.get('winner')}  player_towns={result.get('captures', 0)}")

    if oc == "victory":
        check(f"S{s_idx}: winner is PLAYER (0)", result.get("winner") == 0,
              f"winner={result.get('winner')}")

    return {
        "idx": s_idx, "name": s_name,
        "outcome": oc, "winner": result.get("winner"),
        "captures": result.get("captures", 0),
        "battles": result.get("battles", 0),
        "roster_size": cs.get("roster_size"),
        "passed": oc == "victory",
    }

# ── Reporting ────────────────────────────────────────────────────────────────────

def print_report(results):
    header("REAL-PLAY CAMPAIGN REPORT")
    print(f"  {'Scenario':<22} {'Roster':>6} {'Outcome':>9} {'P.Towns':>8} {'Battles':>8}")
    print("  " + "-" * 60)
    for r in results:
        oc = r["outcome"] or "?"
        color = GREEN if r["passed"] else (YELLOW if oc in ("stall", "timeout") else RED)
        print(f"  {r['name']:<22} {str(r['roster_size']):>6} "
              f"{color}{oc:>9}{RESET} {r['captures']:>8} {r['battles']:>8}")
    print()
    stalls  = [r for r in results if r["outcome"] in ("stall", "timeout")]
    defeats = [r for r in results if r["outcome"] == "defeat"]
    check("No soft-locks / stalls (greedy play kept making progress)",
          not stalls, f"stalled: {[r['name'] for r in stalls]}" if stalls else "none")
    check("No unexpected defeats", not defeats,
          f"lost: {[r['name'] for r in defeats]}" if defeats else "none")

def print_summary():
    header("OVERALL SUMMARY")
    passed = sum(1 for _, ok in _results if ok)
    print(f"\n  {passed}/{len(_results)} checks passed\n")
    fails = [n for n, ok in _results if not ok]
    if fails:
        print("  Failed checks:")
        for n in fails:
            print(f"    {RED}✗{RESET} {n}")
    return not fails

# ── Entry point ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("migs-battle  ·  Real-Overworld Campaign Playtest")
    print(f"speed={SPEED}x  runs/scenario={RUNS}  permadeath={PERMADEATH}")
    print("Connecting to DebugServer on 127.0.0.1:6560 ...\n")

    try:
        _ = send({"action": "state"})
    except Exception as e:
        print(f"ERROR: cannot reach DebugServer: {e}")
        print("Start the game first (godot-mcp run_project, or open the project and Play).")
        sys.exit(1)

    scen_list = ([(ONLY_SCEN, dict(SCENARIOS)[ONLY_SCEN])]
                 if ONLY_SCEN >= 0 else SCENARIOS)

    results = []
    try:
        for i, (s_idx, s_name) in enumerate(scen_list):
            r = play_scenario(s_idx, s_name, first=(i == 0))
            results.append(r)
            if not r["passed"] and ONLY_SCEN < 0:
                info(f"Scenario {s_idx} not cleared — stopping campaign run.")
                break
    finally:
        set_time_scale(1.0)  # always restore real-time before exiting

    print_report(results)
    ok = print_summary()
    sys.exit(0 if ok else 1)
