#!/usr/bin/env python3
"""
play_campaign.py — REAL-overworld, MULTI-SQUAD campaign winnability harness.

Unlike tools/test_campaign_sim.py (which reimplements BattleResolver in Python and
only simulates combat math — NOT a balance oracle), this script PLAYS THE LIVE GAME
like a human and is the source of truth for "is the campaign winnable?":

  * splits the roster into multiple squads (start_campaign num_squads),
  * deploys reserve squads from the HQ under the real GOLD economy (or --free-deploy),
  * drives each squad to a DISTINCT objective (one pushes the enemy HQ),
  * RETREATS damaged squads to owned towns to garrison-heal, then sends them back,
  * lets the engine run real navigation/collisions/battles/captures/win-conditions,
  * resolves battle result screens (presses "Continue"),
  * reports a per-scenario winnability verdict.

Requires the game running with the project open (DebugServer on 127.0.0.1:6560) —
auto-launch via godot-mcp run_project, or open the project and press Play.

Run:
    python3 tools/play_campaign.py [options]
        --squads N      split roster into up to N squads          (default 3)
        --free-deploy   deploy all reserves for free (isolate combat from economy)
        --speed S       Engine.time_scale while playing           (default 6.0)
        --timeout T     wall-clock seconds per scenario           (default 240)
        --scenario K    only play scenario K (0-5)
        --runs N        attempts per scenario                     (default 1)
        --permadeath    permadeath difficulty
"""

import sys
import time
sys.path.insert(0, ".")
from tools.migs_client import (
    send, overworld, move_squad, set_time_scale, deploy_squad,
    start_campaign, get_campaign_state, heal_roster, press_button,
)

# ── Config ──────────────────────────────────────────────────────────────────────

def _arg(flag, default, cast=str):
    return cast(sys.argv[sys.argv.index(flag) + 1]) if flag in sys.argv else default

RUNS        = _arg("--runs", 1, int)
SPEED       = _arg("--speed", 6.0, float)
PERMADEATH  = "--permadeath" in sys.argv
ONLY_SCEN   = _arg("--scenario", -1, int)
SQUADS      = _arg("--squads", 3, int)
FREE_DEPLOY = "--free-deploy" in sys.argv

P_OVERWORLD, P_IN_BATTLE, P_PAUSED, P_VICTORY, P_DEFEAT = 0, 1, 2, 3, 4

CAPTURE_HOLD_RADIUS = 2.5
POLL_DELAY          = 0.20
SETUP_TIMEOUT       = 12.0
SCENARIO_TIMEOUT    = _arg("--timeout", 240.0, float)
STALL_TICKS         = 80
STUCK_LIMIT         = 12
NUDGE_COOLDOWN      = 5
HEAL_LOW            = 0.40   # retreat to heal below this hp fraction
HEAL_HIGH           = 0.85   # rejoin the fight above this hp fraction
DEPLOY_EVERY        = 25     # ticks between reserve-deploy attempts (economy permitting)

SCENARIOS = [
    (0, "Border Skirmish"), (1, "River Crossing"), (2, "Uneasy Allies"),
    (3, "Three Kingdoms"), (4, "The Shadow Rises"), (5, "The Final March"),
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
    print(f"\n{'='*72}\n  {title}\n{'='*72}")

# ── World-state helpers ──────────────────────────────────────────────────────────

def _dist2(ax, az, bx, bz):
    dx, dz = ax - bx, az - bz
    return dx * dx + dz * dz

def _player_squads(ow):
    return [s for s in ow.get("squads", []) if s["faction"] == 0]

def _capturable_towns(ow):
    return [t for t in ow.get("towns", []) if t.get("capturable_by_player") and t["faction"] != 0]

def _owned_towns(ow):
    return [t for t in ow.get("towns", []) if t["faction"] == 0]

def _hostile_enemy_squads(ow):
    return [s for s in ow.get("squads", []) if s["faction"] != 0 and s.get("hostile_to_player")]

def _nearest(items, x, z):
    return min(items, key=lambda i: _dist2(x, z, i["x"], i["z"])) if items else None

def _ownership_sig(ow):
    own = tuple(sorted((k, v) for k, v in ow.get("town_ownership", {}).items()))
    pos = tuple(sorted((s["id"], round(s["x"], 1), round(s["z"], 1)) for s in _player_squads(ow)))
    return (own, pos)

# ── Multi-squad greedy driver: distinct objectives + retreat-to-heal ─────────────

def _drive_tick(ow, mem):
    towns   = _capturable_towns(ow)
    enemies = _hostile_enemy_squads(ow)
    owned   = _owned_towns(ow)
    psquads = sorted(_player_squads(ow), key=lambda s: s["id"])
    claimed = set()  # town ids already targeted this tick (objective de-dup)

    # Pre-claim towns squads are actively capturing so others don't pile on.
    for sq in psquads:
        nt = _nearest(ow.get("towns", []), sq["x"], sq["z"])
        if nt and _dist2(sq["x"], sq["z"], nt["x"], nt["z"]) <= CAPTURE_HOLD_RADIUS ** 2 \
                and nt["faction"] != 0 and nt.get("capturable_by_player") \
                and nt.get("capture_owner") == 0:
            claimed.add(nt["id"])

    for sq in psquads:
        st = mem.setdefault(sq["id"], {"last_pos": None, "stuck": 0, "nudge": 0,
                                       "recovering": False, "blacklist": set()})

        # ── Retreat-to-heal state machine ──
        if st["recovering"]:
            if sq["hp_frac"] >= HEAL_HIGH:
                st["recovering"] = False  # healed — fall through to objective logic
            else:
                if sq["in_battle"] or sq["is_moving"] or sq["is_garrisoned"]:
                    continue  # en route, fighting, or garrisoned+healing → hold
                dest = _nearest(owned, sq["x"], sq["z"])
                if dest:
                    move_squad(sq["id"], town_id=dest["id"])
                continue
        elif sq["hp_frac"] < HEAL_LOW and not sq["in_battle"] and owned:
            st["recovering"] = True
            if not sq["is_moving"]:
                dest = _nearest(owned, sq["x"], sq["z"])
                if dest:
                    move_squad(sq["id"], town_id=dest["id"])
            continue

        if sq["in_battle"] or sq["is_moving"]:
            continue

        # ── Parked on a capturable town: hold while capturing, else nudge ──
        near = _nearest(ow.get("towns", []), sq["x"], sq["z"])
        if near and _dist2(sq["x"], sq["z"], near["x"], near["z"]) <= CAPTURE_HOLD_RADIUS ** 2 \
                and near["faction"] != 0 and near.get("capturable_by_player"):
            st["stuck"] = 0
            claimed.add(near["id"])
            if near.get("capture_owner") == 0:
                st["nudge"] = 0
                continue
            st["nudge"] += 1
            if st["nudge"] >= NUDGE_COOLDOWN:
                st["nudge"] = 0
                move_squad(sq["id"], town_id=near["id"])
            continue

        # ── Stuck detection ──
        pos = (round(sq["x"], 1), round(sq["z"], 1))
        st["stuck"] = st["stuck"] + 1 if st["last_pos"] == pos else 0
        st["last_pos"] = pos

        # ── Assign nearest UNCLAIMED objective (dedup), prefer enemy HQ ──
        avail = [t for t in towns if t["id"] not in claimed and t["id"] not in st["blacklist"]]
        if not avail:
            avail = [t for t in towns if t["id"] not in st["blacklist"]] or towns
        hqs = [t for t in avail if t.get("type") == 2]
        pool = hqs if hqs else avail
        target = _nearest(pool, sq["x"], sq["z"])
        if target and st["stuck"] >= STUCK_LIMIT:
            st["blacklist"].add(target["id"])
            st["stuck"] = 0
            rest = [t for t in avail if t["id"] != target["id"]]
            target = _nearest(rest, sq["x"], sq["z"]) or target
        if target:
            claimed.add(target["id"])
            move_squad(sq["id"], town_id=target["id"])
        elif enemies:
            e = _nearest(enemies, sq["x"], sq["z"])
            move_squad(sq["id"], pos=(e["x"], e["z"]))

def _dismiss_popup():
    try:
        if "error" not in press_button("Refuse"):
            info("Dismissed diplomacy popup (Refuse)")
    except Exception:
        pass

def _do_deploy(stats):
    """Deploy reserve squads from the HQ; track count + approx gold spent."""
    r = deploy_squad(index="all", free=FREE_DEPLOY)
    if isinstance(r, dict) and r.get("deployed"):
        n = len(r["deployed"])
        stats["deploys"] += n
        new_gold = r.get("gold", stats["gold"])
        stats["gold_spent"] += max(0, stats["gold"] - new_gold)
        stats["gold"] = new_gold
        info(f"Deployed {n} reserve squad(s)  (gold {new_gold}, reserve left "
             f"{r.get('reserve_remaining')})")
    elif isinstance(r, dict):
        stats["gold"] = r.get("gold", stats["gold"])

# ── Play one scenario attempt ────────────────────────────────────────────────────

def play_attempt(s_idx, s_name, start_gold):
    t0 = time.time()
    ow = {}
    while time.time() - t0 < SETUP_TIMEOUT:
        ow = overworld()
        if ow.get("phase") == P_OVERWORLD and _player_squads(ow):
            break
        time.sleep(0.3)
    if not _player_squads(ow):
        return {"outcome": "no_squads"}

    set_time_scale(SPEED)
    stats = {"deploys": 0, "gold_spent": 0, "gold": start_gold}
    _do_deploy(stats)  # field reserves up front

    info(f"Overworld up: {len(_player_squads(ow))} active squad(s) after deploy, "
         f"{len(ow.get('towns', []))} towns, win={ow.get('active_conditions')}")

    last_sig, stall, battles, captures, max_squads = None, 0, 0, 0, 0
    mem = {}
    start = time.time()
    tick = 0

    while time.time() - start < SCENARIO_TIMEOUT:
        ow = overworld()
        phase = ow.get("phase", P_OVERWORLD)

        if phase in (P_VICTORY, P_DEFEAT):
            return _result("victory" if phase == P_VICTORY else "defeat",
                           ow, stall, captures, battles, stats, max_squads)

        if phase == P_IN_BATTLE:
            # Battles end on a "Continue" result screen (under the tree root) that
            # waits for a click. Press it to resolve; a battle is always progress.
            r = press_button("Continue")
            if isinstance(r, dict) and "error" not in r:
                battles += 1
            stall = 0
            time.sleep(POLL_DELAY)
            continue

        if ow.get("paused"):
            _dismiss_popup()
            time.sleep(POLL_DELAY)
            continue

        max_squads = max(max_squads, len(_player_squads(ow)))
        _drive_tick(ow, mem)

        tick += 1
        if tick % DEPLOY_EVERY == 0:
            _do_deploy(stats)  # income may now afford more squads

        sig = _ownership_sig(ow)
        captures = max(captures, sum(1 for v in ow.get("town_ownership", {}).values() if v == 0))
        if sig == last_sig:
            stall += 1
        else:
            stall, last_sig = 0, sig
        if stall >= STALL_TICKS:
            return _result("stall", ow, stall, captures, battles, stats, max_squads)

        time.sleep(POLL_DELAY)

    return _result("timeout", ow, stall, captures, battles, stats, max_squads)

def _result(outcome, ow, stall, captures, battles, stats, max_squads):
    alive = sum(s.get("alive_count", 0) for s in _player_squads(ow))
    return {"outcome": outcome, "winner": ow.get("winner"), "ticks": stall,
            "captures": captures, "battles": battles, "deploys": stats["deploys"],
            "gold_spent": stats["gold_spent"], "squads": max_squads, "alive_end": alive}

# ── Scenario driver ──────────────────────────────────────────────────────────────

def play_scenario(s_idx, s_name, first):
    header(f"Scenario {s_idx}: {s_name}")
    if not first:
        heal_roster(fraction=1.0, revive=not PERMADEATH)
    start_campaign(scenario_idx=s_idx, permadeath=PERMADEATH, num_squads=SQUADS)
    time.sleep(1.0)

    cs = get_campaign_state()
    roster = cs.get("roster_size")
    start_gold = cs.get("player_gold", 0)
    info(f"Roster {roster}  gold={start_gold}  squads={SQUADS}  "
         f"deploy={'FREE' if FREE_DEPLOY else 'paid'}  permadeath={PERMADEATH}")

    result = {}
    for attempt in range(1, RUNS + 1):
        if attempt > 1:
            info(f"Retry {attempt}/{RUNS}")
            heal_roster(fraction=1.0, revive=not PERMADEATH)
            start_campaign(scenario_idx=s_idx, permadeath=PERMADEATH, num_squads=SQUADS)
            time.sleep(1.0)
            cs = get_campaign_state()
            start_gold = cs.get("player_gold", 0)
        result = play_attempt(s_idx, s_name, start_gold)
        oc = result["outcome"]
        tag = GREEN if oc == "victory" else (YELLOW if oc in ("stall", "timeout") else RED)
        info(f"Attempt {attempt}: {tag}{oc.upper()}{RESET}  squads={result.get('squads')}  "
             f"deploys={result.get('deploys')}  battles={result.get('battles')}  "
             f"p.towns={result.get('captures')}  alive={result.get('alive_end')}")
        if oc == "victory":
            break

    oc = result.get("outcome")
    check(f"S{s_idx} ({s_name}): cleared (real win conditions fired)",
          oc == "victory", f"outcome={oc} winner={result.get('winner')}")
    return {"idx": s_idx, "name": s_name, "roster_size": roster, "passed": oc == "victory", **result}

# ── Reporting ────────────────────────────────────────────────────────────────────

def print_report(results):
    header("WINNABILITY REPORT  (real multi-squad play)")
    hdr = f"  {'Scenario':<20}{'Roster':>7}{'Squads':>7}{'Deploys':>8}{'Battles':>8}{'P.Towns':>8}{'AliveEnd':>9}  {'Outcome':<9}"
    print(hdr); print("  " + "-" * (len(hdr) - 2))
    for r in results:
        oc = r.get("outcome") or "?"
        color = GREEN if r["passed"] else (YELLOW if oc in ("stall", "timeout") else RED)
        print(f"  {r['name']:<20}{str(r.get('roster_size')):>7}{str(r.get('squads')):>7}"
              f"{str(r.get('deploys')):>8}{str(r.get('battles')):>8}{str(r.get('captures')):>8}"
              f"{str(r.get('alive_end')):>9}  {color}{oc:<9}{RESET}")
    print()
    won = [r for r in results if r["passed"]]
    info(f"Verdict: {len(won)}/{len(results)} scenarios winnable "
         f"({'FREE-deploy' if FREE_DEPLOY else 'realistic economy'}, {SQUADS} squads)")
    not_won = [r for r in results if not r["passed"]]
    if not_won:
        info("Not cleared: " + ", ".join(f"{r['name']}({r.get('outcome')})" for r in not_won))

def print_summary():
    header("SUMMARY")
    passed = sum(1 for _, ok in _results if ok)
    print(f"\n  {passed}/{len(_results)} scenario checks passed\n")
    for n, ok in _results:
        if not ok:
            print(f"    {RED}✗{RESET} {n}")
    return passed == len(_results)

# ── Entry point ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("migs-battle  ·  Multi-Squad Winnability Harness")
    print(f"squads={SQUADS}  deploy={'FREE' if FREE_DEPLOY else 'paid'}  "
          f"speed={SPEED}x  timeout={SCENARIO_TIMEOUT}s")
    print("Connecting to DebugServer on 127.0.0.1:6560 ...\n")
    try:
        send({"action": "state"})
    except Exception as e:
        print(f"ERROR: cannot reach DebugServer: {e}")
        sys.exit(1)

    scen_list = ([(ONLY_SCEN, dict(SCENARIOS)[ONLY_SCEN])] if ONLY_SCEN >= 0 else SCENARIOS)
    results = []
    try:
        for i, (s_idx, s_name) in enumerate(scen_list):
            r = play_scenario(s_idx, s_name, first=(i == 0))
            results.append(r)
            if not r["passed"] and ONLY_SCEN < 0:
                info(f"Scenario {s_idx} not cleared — stopping campaign run.")
                break
    finally:
        set_time_scale(1.0)

    print_report(results)
    ok = print_summary()
    sys.exit(0 if ok else 1)
