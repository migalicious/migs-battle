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
    snapshot_roster, restore_roster, get_units, get_item_defs, give_item,
    equip_item, set_gold, use_item, get_inventory,
)

# ── Config ──────────────────────────────────────────────────────────────────────

def _arg(flag, default, cast=str):
    return cast(sys.argv[sys.argv.index(flag) + 1]) if flag in sys.argv else default

RUNS        = _arg("--runs", 3, int)     # attempts per scenario for the win-RATE measure
SPEED       = _arg("--speed", 6.0, float)
PERMADEATH  = "--permadeath" in sys.argv
ONLY_SCEN   = _arg("--scenario", -1, int)
SQUADS      = _arg("--squads", 3, int)
FREE_DEPLOY = "--free-deploy" in sys.argv
STRATEGY    = _arg("--strategy", "auto", str)  # spread | pairs | auto
#   spread : each squad takes a distinct objective (force-concentration cap of 2 on strongholds)
#   pairs  : squads operate in coordinated pairs sharing one stronghold target (serial assault)
#   auto   : pairs on all_strongholds maps, spread elsewhere
WIN_THRESHOLD = _arg("--threshold", 0.60, float)  # target win rate (average player should beat it)
EQUIP_FRACTION    = 0.30  # share of gold an "average player" spends on passive gear up front
CONSUMABLE_BUDGET = 0.40  # share of gold spent on healing/revive consumables up front
# Combat is now DECISIVE (post-battle knockback ends the old machine-gun grind), so recovery via a
# field kit matters far more than a marginal extra stat point — a small army with no heals nibbles a
# garrison and dies by attrition. Shifted budget from gear → consumables and retreat earlier so
# squads survive the now-meaningful 4-round exchanges instead of fighting until wiped.
CONSUMABLE_USE_HP = 0.60  # use a heal consumable on a squad parked/idle below this hp fraction

P_OVERWORLD, P_IN_BATTLE, P_PAUSED, P_VICTORY, P_DEFEAT = 0, 1, 2, 3, 4

CAPTURE_HOLD_RADIUS = 2.5
POLL_DELAY          = 0.20
SETUP_TIMEOUT       = 12.0
SCENARIO_TIMEOUT    = _arg("--timeout", 240.0, float)
STALL_TICKS         = 120    # raised: decisive combat grinds slower (knockback walk-back + heal
                             #         round-trips), so a progressing assault needs more patience
                             #         before it's scored a stall (squads healing sit static a while)
STUCK_LIMIT         = 12
NUDGE_COOLDOWN      = 5
HEAL_LOW            = 0.45   # retreat to heal below this hp fraction (decisive combat: survive, but
                             #         not so eager that both squads idle-heal together and stall)
HEAL_HIGH           = 0.85   # rejoin the fight above this hp fraction
DEPLOY_EVERY        = 25     # ticks between reserve-deploy attempts (economy permitting)
# ── Tactical autoplayer (HQ defense, stalemate-breaking, enemy-infighting) ──
HQ_DEFEND_RADIUS    = 3.5    # an enemy this close to the HQ (or actively capturing it) = repel it
                             #   (tight: a passing roamer shouldn't pin a defender home for good)
ABANDON_COOLDOWN    = 70     # ticks an abandoned stronghold stays off the target list
# Battle-count stalemate metric: ticks under-count an assault (most of it is spent IN_BATTLE, where
# the driver isn't called), so escalate on actual BATTLES fought at a stronghold without it falling.
STALEMATE_BATTLES_GANG   = 4   # battles at one stronghold w/o capture → gang it (extra squad)
STALEMATE_BATTLES_ABANDON = 8  # battles w/o capture → temp-abandon (hq_capture maps only)
FINAL_PUSH_STRONGHOLDS   = 2   # all_strongholds: when <= this many enemy strongholds remain, all
                               #   squads converge on ONE to finish it decisively (no enemy heal)

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

def _target_cap(town, n_squads, n_strongholds):
    # FORCE CONCENTRATION: let up to 2 squads converge on a defended STRONGHOLD so they
    # assault it in succession. Battles are 1-squad-vs-1-squad, but enemy garrisons never
    # heal (asymmetric design), so a second squad arriving finishes off what the first
    # wore down — instead of each squad dying alone at a separate stronghold.
    # Gang up (cap 2 on strongholds) when EITHER:
    #   * the army is big enough (>=3 squads) to spare two for one target and still cover
    #     other objectives (the big-map / all-strongholds case), OR
    #   * there's only one stronghold left to take — then splitting buys nothing, so a
    #     small (2-squad) army should pool its force on that last garrison (the hq_capture
    #     opener case, where a lone squad otherwise coin-flips the HQ and often stalls).
    # Otherwise keep squads split so a small army doesn't over-commit to one place and
    # abandon the rest of a multi-stronghold map. Plain towns are undefended → always 1.
    if town.get("is_stronghold") and (n_squads >= 3 or n_strongholds <= 1):
        return 2
    return 1

def _effective_mode(ow, n_squads):
    # Resolve the active strategy for this scenario. 'auto' picks the coordinated-PAIRS strategy ONLY
    # for small (<=2 squad) all_strongholds maps — the case a lone squad can't solo and loses
    # piecemeal (e.g. S1 River Crossing). A 3+ squad army already concentrates fine under SPREAD
    # (force-concentration cap of 2 on strongholds) AND needs to cover a big multi-stronghold map;
    # forcing it into one pair would pile every squad on a single garrison and surrender the rest of
    # the map (this regressed S3 Three Kingdoms to 0%). Everything else uses SPREAD.
    if STRATEGY in ("spread", "pairs"):
        return STRATEGY
    if "all_strongholds" in ow.get("active_conditions", []) and n_squads <= 2:
        return "pairs"
    return "spread"

def _pair_targets(psquads, towns, enemies, mem):
    # Group squads into ordered pairs [s0,s1],[s2,s3],… (an odd squad joins the previous pair → trio)
    # and give every member of a pair ONE shared target: the nearest not-yet-owned stronghold to the
    # pair's centroid. Both squads converge on the same garrison and grind it down together (enemy
    # garrisons never heal, so the second arrival finishes what the first wore down). Falls back to
    # nearest capturable town, then nearest hostile squad, when no strongholds remain.
    strongholds = [t for t in towns if t.get("is_stronghold")]
    out = {}  # squad id -> ("town", town_id) | ("pos", (x, z))
    # Ordered pairs [s0,s1],[s2,s3],… A lone trailing squad stays SOLO (its own group) and takes its
    # own nearest stronghold — never merged into a trio, which would over-concentrate the army.
    groups = [psquads[i:i + 2] for i in range(0, len(psquads), 2)]
    for grp in groups:
        cx = sum(s["x"] for s in grp) / len(grp)
        cz = sum(s["z"] for s in grp) / len(grp)
        # Skip strongholds blacklisted by every member of the pair (stuck-avoidance carries over).
        bl = set.intersection(*[mem.get(s["id"], {}).get("blacklist", set()) for s in grp]) \
            if grp else set()
        pool = [t for t in strongholds if t["id"] not in bl] or strongholds
        tgt = _nearest(pool, cx, cz) or _nearest(towns, cx, cz)
        for s in grp:
            if tgt:
                out[s["id"]] = ("town", tgt["id"])
            elif enemies:
                e = _nearest(enemies, s["x"], s["z"])
                out[s["id"]] = ("pos", (e["x"], e["z"]))
    return out

def _player_hq(ow):
    # The player stronghold whose loss ends the game (hq_capture LOSS) — prefer an id that names the
    # HQ, else any owned stronghold. Used to post a defender when an enemy threatens home.
    phqs = [t for t in ow.get("towns", []) if t["faction"] == 0 and t.get("is_stronghold")]
    if not phqs:
        return None
    return next((t for t in phqs if "hq" in str(t["id"]).lower()), phqs[0])

def _enemy_on(town, enemies):
    # Is a hostile squad currently sitting on this stronghold (i.e. it's actively garrisoned)?
    # An UNdefended enemy stronghold (garrison off fighting another faction) is a free objective —
    # preferring those is how we exploit enemy-vs-enemy infighting on three_way maps.
    return any(_dist2(town["x"], town["z"], e["x"], e["z"]) <= 2.0 ** 2 for e in enemies)

def _update_assault(ow, mem, towns, psquads, allow_abandon):
    # Track BATTLES fought at each enemy stronghold without it falling (a true stalemate signal —
    # earlier tick-based counting under-measured, since most of an assault is spent IN_BATTLE where
    # the driver isn't called, so the escalation rarely fired). The `assault` counter drives GANG
    # (throw an extra squad once a garrison has resisted several battles). When `allow_abandon`
    # (hq_capture maps only — you can skip a hard stronghold and still win via the HQ), a stalemated
    # stronghold is temp-abandoned; on all_strongholds you must take EVERY stronghold, so there we
    # only gang harder, never skip (the FINAL-PUSH concentrates force instead).
    assault = mem.setdefault("_assault", {})        # stronghold id -> battles fought there w/o capture
    abandon = mem.setdefault("_abandon", {})
    for tid in list(abandon):                       # decay temp-abandon cooldowns
        abandon[tid] -= 1
        if abandon[tid] <= 0:
            del abandon[tid]
    live = {t["id"] for t in towns}                 # still enemy-held & capturable
    for tid in list(assault):                       # a stronghold that flipped (captured) resets
        if tid not in live:
            del assault[tid]
    # Attribute a NEW battle (battle count rose since last tick) to the nearest stronghold that has a
    # player squad adjacent — that's the garrison being assaulted.
    battles_now = mem.get("_battles", 0)
    new_battle = battles_now > mem.get("_battles_prev", 0)
    mem["_battles_prev"] = battles_now
    if new_battle:
        adj = [t for t in towns if t.get("is_stronghold") and any(
            _dist2(t["x"], t["z"], s["x"], s["z"]) <= (CAPTURE_HOLD_RADIUS + 1.5) ** 2 for s in psquads)]
        if adj:
            tgt = min(adj, key=lambda t: min(_dist2(t["x"], t["z"], s["x"], s["z"]) for s in psquads))
            assault[tgt["id"]] = assault.get(tgt["id"], 0) + 1
            if allow_abandon and assault[tgt["id"]] >= STALEMATE_BATTLES_ABANDON \
                    and tgt["id"] not in abandon:
                abandon[tgt["id"]] = ABANDON_COOLDOWN   # give up on this one a while; go elsewhere
                assault[tgt["id"]] = 0
    return assault, abandon

def _drive_tick(ow, mem):
    towns   = _capturable_towns(ow)
    enemies = _hostile_enemy_squads(ow)
    owned   = _owned_towns(ow)
    psquads = sorted(_player_squads(ow), key=lambda s: s["id"])
    n_squads = len(psquads)
    n_strongholds = sum(1 for t in towns if t.get("is_stronghold"))
    mode = _effective_mode(ow, n_squads)
    # On all_strongholds maps the win condition is pure offense (take every stronghold) against a
    # clock, so posting a home defender or skipping a stronghold both backfire (they starve the
    # offense and cause timeouts — observed S5 100%→50%). Reserve HQ-defense + abandon for pure
    # hq_capture maps, where an HQ-snipe is the real loss and skipping a hard stronghold is viable.
    hq_only = "hq_capture" in ow.get("active_conditions", []) \
        and "all_strongholds" not in ow.get("active_conditions", [])
    pair_tgt = _pair_targets(psquads, towns, enemies, mem) if mode == "pairs" else {}
    assault, abandon = _update_assault(ow, mem, towns, psquads, allow_abandon=hq_only)
    claimed = {}  # town id -> # of squads targeting it this tick (capped per _target_cap)

    # ── FINAL PUSH: on an all_strongholds map, once only a few enemy strongholds remain, the spread
    #    driver keeps rotating squads off the last defended HQs (retreat-heal) and never overwhelms
    #    one — the army "survives but doesn't finish". When <= FINAL_PUSH_STRONGHOLDS remain, point
    #    EVERY squad at a single one (prefer an undefended one, else nearest to the army centroid) so
    #    they grind it down together (enemy garrisons don't heal). Retreat-heal still applies, so a
    #    near-dead squad peels off and rejoins rather than feeding itself in. ──
    push_target = None
    estrongs = [t for t in towns if t.get("is_stronghold")]
    if "all_strongholds" in ow.get("active_conditions", []) and 1 <= len(estrongs) <= FINAL_PUSH_STRONGHOLDS:
        cx = sum(s["x"] for s in psquads) / max(1, len(psquads))
        cz = sum(s["z"] for s in psquads) / max(1, len(psquads))
        estrongs.sort(key=lambda t: (_enemy_on(t, enemies), _dist2(cx, cz, t["x"], t["z"])))
        push_target = estrongs[0]

    # ── HQ DEFENSE: post ONE squad home to repel an HQ-snipe (the bot otherwise loses maps when an
    #    enemy takes its HQ while the whole army is away). Trigger is PRECISE — only when the HQ is
    #    actively being captured (capture_owner is an enemy) or an enemy is right on top of it — so it
    #    works on EVERY map (an HQ-snipe is a loss condition everywhere) without pinning a defender
    #    for mere proximity on dense maps (that over-defense starved S5's offense → timeouts).
    #    Skipped in pairs mode (2-squad all_strongholds, e.g. S1) where peeling a squad off guts the
    #    coordinated assault. ──
    defender_id = None
    hq = _player_hq(ow)
    if hq and mode != "pairs" and n_squads >= 2:
        cap_owner = hq.get("capture_owner", -2)
        being_capped = cap_owner not in (-2, 0)         # an enemy faction is capturing our HQ
        enemy_on_hq = any(_dist2(hq["x"], hq["z"], e["x"], e["z"]) <= HQ_DEFEND_RADIUS ** 2
                          for e in enemies)
        if being_capped or enemy_on_hq:
            on_hq = [s for s in psquads
                     if _dist2(hq["x"], hq["z"], s["x"], s["z"]) <= CAPTURE_HOLD_RADIUS ** 2]
            if on_hq:                                   # already someone home — keep them there
                defender_id = on_hq[0]["id"]
            else:                                       # send the nearest still-healthy squad home
                cand = [s for s in psquads if s["hp_frac"] >= HEAL_LOW] or psquads
                d = _nearest(cand, hq["x"], hq["z"])
                defender_id = d["id"] if d else None

    def _claim(tid):
        claimed[tid] = claimed.get(tid, 0) + 1
    def _full(town):
        cap = _target_cap(town, n_squads, n_strongholds)
        if town.get("is_stronghold") and assault.get(town["id"], 0) >= STALEMATE_BATTLES_GANG:
            cap += 1   # garrison has resisted several battles → allow an extra squad to gang it down
        return claimed.get(town["id"], 0) >= cap

    # Pre-claim towns squads are actively capturing so others don't over-stack them.
    for sq in psquads:
        nt = _nearest(ow.get("towns", []), sq["x"], sq["z"])
        if nt and _dist2(sq["x"], sq["z"], nt["x"], nt["z"]) <= CAPTURE_HOLD_RADIUS ** 2 \
                and nt["faction"] != 0 and nt.get("capturable_by_player") \
                and nt.get("capture_owner") == 0:
            _claim(nt["id"])

    bag = mem.setdefault("_bag", {})

    for sq in psquads:
        st = mem.setdefault(sq["id"], {"last_pos": None, "stuck": 0, "nudge": 0,
                                       "recovering": False, "blacklist": set()})

        # ── Field consumables: revive the fallen / heal before retreating ──
        if bag:
            _maybe_use_consumable(sq, st, bag)

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

        # ── HQ DEFENSE: the posted defender returns home and holds until the threat clears ──
        if sq["id"] == defender_id and hq:
            if not sq["in_battle"] \
                    and _dist2(sq["x"], sq["z"], hq["x"], hq["z"]) > CAPTURE_HOLD_RADIUS ** 2:
                move_squad(sq["id"], town_id=hq["id"])   # else: already home, sit and intercept
            continue

        if sq["in_battle"] or sq["is_moving"]:
            continue

        # ── Parked on a capturable town: hold while capturing, else nudge ──
        near = _nearest(ow.get("towns", []), sq["x"], sq["z"])
        if near and _dist2(sq["x"], sq["z"], near["x"], near["z"]) <= CAPTURE_HOLD_RADIUS ** 2 \
                and near["faction"] != 0 and near.get("capturable_by_player"):
            st["stuck"] = 0
            _claim(near["id"])
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

        # ── FINAL PUSH override: send this squad to the shared last-stronghold target. (Skipped in
        #    pairs mode, which already concentrates, and for the HQ defender.) ──
        if push_target and mode != "pairs" and sq["id"] != defender_id:
            _claim(push_target["id"])
            move_squad(sq["id"], town_id=push_target["id"])
            continue

        # ── PAIRS strategy: follow this squad's coordinated-pair target (a shared stronghold). ──
        if mode == "pairs" and sq["id"] in pair_tgt:
            kind, val = pair_tgt[sq["id"]]
            if kind == "town":
                if st["stuck"] >= STUCK_LIMIT:
                    st["blacklist"].add(val)   # recomputed away from on the next tick's _pair_targets
                    st["stuck"] = 0
                else:
                    move_squad(sq["id"], town_id=val)
            else:
                move_squad(sq["id"], pos=val)
            continue

        # ── Assign objective: prefer enemy STRONGHOLDS, allowing up to 2 squads each so
        #    they gang up on tough garrisons (de-dup only kicks in past the per-town cap).
        #    `abandon` drops stalemated strongholds from the pool for a cooldown. ──
        blocked = st["blacklist"] | set(abandon.keys())
        avail = [t for t in towns if not _full(t) and t["id"] not in blocked]
        if not avail:
            avail = [t for t in towns if t["id"] not in blocked] \
                or [t for t in towns if t["id"] not in st["blacklist"]] or towns
        # Prefer enemy STRONGHOLDS (HQ/castle) — owning all of them wins both hq_capture and
        # all_strongholds. Among strongholds, prefer UNDEFENDED ones (garrison off fighting another
        # faction) then nearest — exploits enemy infighting on three_way maps (validated 5/6 config).
        strongholds = [t for t in avail if t.get("is_stronghold")]
        if strongholds:
            strongholds.sort(key=lambda t: (_enemy_on(t, enemies),
                                            _dist2(sq["x"], sq["z"], t["x"], t["z"])))
            target = strongholds[0]
        else:
            target = _nearest(avail, sq["x"], sq["z"])
        if target and st["stuck"] >= STUCK_LIMIT:
            st["blacklist"].add(target["id"])
            st["stuck"] = 0
            rest = [t for t in avail if t["id"] != target["id"]]
            target = _nearest(rest, sq["x"], sq["z"]) or target
        if target:
            _claim(target["id"])
            move_squad(sq["id"], town_id=target["id"])
        elif enemies:
            e = _nearest(enemies, sq["x"], sq["z"])
            move_squad(sq["id"], pos=(e["x"], e["z"]))

def _dismiss_popup():
    # Try the known labels in turn — robust to whatever popup is up so it can never hard-stall the
    # run. ACCEPT a diplomacy alliance offer FIRST (an ally is always good for the player: fewer
    # enemies, and on all_strongholds maps the ally's strongholds drop from the win requirement),
    # then fall back to neutral dismissals for non-alliance popups.
    for label in ("Accept Alliance", "Continue", "OK", "Close", "Refuse", "Decline"):
        try:
            if "error" not in press_button(label):
                info(f"Dismissed popup ({label})")
                return
        except Exception:
            pass

def _try_accept_alliance(mem):
    # The alliance-offer popup deliberately does NOT pause the overworld, so the paused-popup path
    # never fires for it — poll-press "Accept Alliance" to take a standing offer. No-op when none is up.
    try:
        if "error" not in press_button("Accept Alliance"):
            if not mem.get("_allied"):
                mem["_allied"] = True
                info("Accepted alliance offer")
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

def play_attempt(s_idx, s_name, start_gold, bag=None):
    # Consumables live in the bag, not the roster snapshot — re-stock each run so
    # every attempt starts from the identical pre-scenario kit.
    for iid, qty in (bag or {}).items():
        if qty > 0:
            give_item(iid, qty)

    t0 = time.time()
    ow = {}
    while time.time() - t0 < SETUP_TIMEOUT:
        ow = overworld()
        if ow.get("paused"):
            _dismiss_popup()          # a start-of-map diplomacy offer must not stall setup
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
    mem = {"_bag": dict(bag or {})}   # local copy of the kit; decremented as items are used
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
        mem["_battles"] = battles   # expose live battle count to the stalemate metric (battle-based)
        _drive_tick(ow, mem)

        tick += 1
        if tick % DEPLOY_EVERY == 0:
            _do_deploy(stats)  # income may now afford more squads
        if not mem.get("_allied") and tick % 8 == 0:
            _try_accept_alliance(mem)   # accept a standing alliance offer (non-pausing popup)

        # ── Early concede (anti-wander): on an all_strongholds map a lone surviving squad can never
        #    satisfy the win condition (take EVERY stronghold) — it just wanders to the 240s timeout
        #    racking inconclusive battles (the "stuck in a loop" symptom). If the army has COLLAPSED
        #    from >=2 squads down to 1 with >=2 strongholds still enemy-held, the run is lost: concede
        #    now instead of burning the clock. (Same non-win outcome, seconds instead of minutes.) ──
        if "all_strongholds" in ow.get("active_conditions", []) and tick > 150 and max_squads >= 2 \
                and len(_player_squads(ow)) <= 1 \
                and sum(1 for t in _capturable_towns(ow) if t.get("is_stronghold")) >= 2:
            return _result("defeat", ow, stall, captures, battles, stats, max_squads)

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

# ── Average-player equipment model ───────────────────────────────────────────────

def _buy_equipment(fraction):
    """Model an average player buying gear: spend ~`fraction` of gold on the best
    affordable passive items and equip unequipped units. Persists via the snapshot.
    Returns gold spent."""
    items = [i for i in get_item_defs() if i.get("type") == 0 and i.get("cost", 0) > 0]
    if not items:
        return 0
    def val(i):
        return (i.get("def", 0) + i.get("str", 0) + i.get("int", 0)
                + i.get("agi", 0) + i.get("res", 0) + i.get("hp", 0) // 3)
    items.sort(key=val, reverse=True)
    gold = get_campaign_state().get("player_gold", 0)
    budget = int(gold * fraction)
    spent = 0
    for u in get_units():
        if u.get("held_item"):
            continue
        for it in items:
            if it["cost"] <= budget - spent:
                give_item(it["id"], 1)
                equip_item(u["name"], it["id"])
                spent += it["cost"]
                break
    if spent > 0:
        set_gold(max(0, gold - spent))
    return spent

# ── Average-player consumable model (buy healing/revive items, use them in field) ──

_consumable_order = None   # cached ([heal item ids], [revive item ids])

def _classify_consumables():
    """Order consumable item ids the way a player would reach for them: squad-wide
    heals first (best value), then strong single heals; revives separately."""
    global _consumable_order
    if _consumable_order is not None:
        return _consumable_order
    cons = [i for i in get_item_defs() if i.get("type") == 1 and i.get("cost", 0) > 0]
    heals = [i for i in cons if i.get("heal_pct", 0) > 0]
    revives = [i for i in cons if i.get("revive_pct", 0) > 0]
    heals.sort(key=lambda i: (not i.get("squad_wide"), -i.get("heal_pct", 0)))
    revives.sort(key=lambda i: -i.get("revive_pct", 0))
    _consumable_order = ([i["id"] for i in heals], [i["id"] for i in revives])
    return _consumable_order

def _buy_consumables(fraction):
    """Model the average player stocking a field kit: spend ~`fraction` of gold on a
    spread of healing + revive consumables. Returns (bag {item_id: qty}, gold spent).
    The bag is NOT part of the roster snapshot, so play_attempt re-gives it each run."""
    cons = {i["id"]: i for i in get_item_defs() if i.get("type") == 1 and i.get("cost", 0) > 0}
    if not cons:
        return {}, 0
    heal_ids, revive_ids = _classify_consumables()
    # Round-robin priority: a squad-wide heal, a single heal, a revive, repeat.
    priority = []
    if heal_ids:
        priority.append(heal_ids[0])                       # squad-wide / best heal
    priority += revive_ids[:1]                             # one revive
    priority += heal_ids[1:2]                              # a cheaper single heal
    priority = [iid for iid in priority if iid in cons] or list(cons.keys())
    gold = get_campaign_state().get("player_gold", 0)
    budget = int(gold * fraction)
    bag, spent, i = {}, 0, 0
    while spent < budget and priority:
        iid = priority[i % len(priority)]
        cost = cons[iid]["cost"]
        if cost <= budget - spent:
            give_item(iid, 1)
            bag[iid] = bag.get(iid, 0) + 1
            spent += cost
        i += 1
        if i > len(priority) * 12:   # stop once nothing cheap enough remains
            break
    if spent > 0:
        set_gold(max(0, gold - spent))
    return bag, spent

def _maybe_use_consumable(sq, st, bag):
    """Field-use a consumable on a squad: revive a fallen unit, or top up HP so the
    squad can keep fighting instead of trekking back across the map to a garrison.
    This is the ONLY healing besides garrisons (no free pre-battle heals) — so a
    player who buys items should survive longer. Decrements the local bag on use."""
    if sq["in_battle"]:
        return
    heal_ids, revive_ids = _classify_consumables()
    # Revive when a unit has fallen (alive_count dropped below the squad's peak).
    st["max_alive"] = max(st.get("max_alive", sq["alive_count"]), sq["alive_count"])
    if sq["alive_count"] < st["max_alive"]:
        for iid in revive_ids:
            if bag.get(iid, 0) > 0 and use_item(sq["id"], iid).get("ok"):
                bag[iid] -= 1
                st["max_alive"] = sq["alive_count"] + 1
                return
    # Heal a worn-down squad before it would otherwise retreat.
    if sq["hp_frac"] < CONSUMABLE_USE_HP:
        for iid in heal_ids:
            if bag.get(iid, 0) > 0 and use_item(sq["id"], iid).get("ok"):
                bag[iid] -= 1
                return

# ── Scenario driver: win RATE over N runs from the same pre-scenario state ─────────

def play_scenario(s_idx, s_name, first):
    header(f"Scenario {s_idx}: {s_name}")
    # start_campaign(idx) delivers (idx-1)'s rewards ONCE onto the carried roster.
    start_campaign(scenario_idx=s_idx, permadeath=PERMADEATH, num_squads=SQUADS)
    time.sleep(1.0)
    roster = get_campaign_state().get("roster_size")
    # Stock the field kit FIRST: under decisive combat, a small army's survival hinges on heals/
    # revives more than on a marginal stat point, so consumables get first call on the gold.
    bag, cons_spent = _buy_consumables(CONSUMABLE_BUDGET)
    gear_spent = _buy_equipment(EQUIP_FRACTION)         # ...then gear up with what remains
    snapshot_roster()                                   # capture the equipped pre-scenario state
    start_gold = get_campaign_state().get("player_gold", 0)
    bag_str = ", ".join(f"{q}×{i}" for i, q in bag.items()) or "none"
    info(f"Roster {roster}  gold(after gear+kit)={start_gold}  gear_spent={gear_spent}  "
         f"kit_spent={cons_spent} [{bag_str}]  squads={SQUADS}  target={WIN_THRESHOLD:.0%}  "
         f"deploy={'FREE' if FREE_DEPLOY else 'paid'}  strategy={STRATEGY}")

    wins = surv_sum = battles_sum = deploys_sum = 0
    for attempt in range(1, RUNS + 1):
        if attempt > 1:
            restore_roster()
            start_campaign(scenario_idx=s_idx, permadeath=PERMADEATH, num_squads=SQUADS, skip_rewards=True)
            time.sleep(1.0)
        set_gold(start_gold)                            # identical economy each run
        r = play_attempt(s_idx, s_name, start_gold, bag)
        oc = r.get("outcome")
        wins += 1 if oc == "victory" else 0
        surv_sum += r.get("alive_end", 0)
        battles_sum += r.get("battles", 0)
        deploys_sum += r.get("deploys", 0)
        tag = GREEN if oc == "victory" else (YELLOW if oc in ("stall", "timeout") else RED)
        info(f"  run {attempt}/{RUNS}: {tag}{oc.upper()}{RESET}  alive={r.get('alive_end')}  "
             f"battles={r.get('battles')}  squads={r.get('squads')}  p.towns={r.get('captures')}")

    restore_roster()  # leave roster at the pre-scenario state for the next scenario's reward delivery
    win_rate = wins / RUNS if RUNS else 0.0
    avg_surv = surv_sum / RUNS if RUNS else 0.0
    passed = win_rate >= WIN_THRESHOLD
    check(f"S{s_idx} ({s_name}): win rate >= {WIN_THRESHOLD:.0%}", passed,
          f"{win_rate:.0%} ({wins}/{RUNS})  avg_surv={avg_surv:.1f}")
    return {"idx": s_idx, "name": s_name, "roster_size": roster, "win_rate": win_rate,
            "avg_surv": avg_surv, "battles": battles_sum // max(1, RUNS),
            "deploys": deploys_sum // max(1, RUNS), "gear_spent": gear_spent, "passed": passed}

# ── Reporting ────────────────────────────────────────────────────────────────────

def print_report(results):
    header("WINNABILITY REPORT  (win rate over N real multi-squad runs)")
    hdr = (f"  {'Scenario':<20}{'Roster':>7}{'Win%':>7}{'AvgSurv':>9}{'Battles':>8}"
           f"{'Deploys':>8}{'Gear':>6}  {'Verdict':<6}")
    print(hdr); print("  " + "-" * (len(hdr) - 2))
    for r in results:
        ok = r["passed"]
        c = GREEN if ok else RED
        print(f"  {r['name']:<20}{str(r.get('roster_size')):>7}{c}{r['win_rate']*100:>6.0f}%{RESET}"
              f"{r.get('avg_surv',0):>9.1f}{str(r.get('battles')):>8}{str(r.get('deploys')):>8}"
              f"{str(r.get('gear_spent')):>6}  {c}{'PASS' if ok else 'FAIL':<6}{RESET}")
    print()
    won = [r for r in results if r["passed"]]
    info(f"Verdict: {len(won)}/{len(results)} scenarios >= {WIN_THRESHOLD:.0%} win rate  "
         f"({'FREE-deploy' if FREE_DEPLOY else 'realistic economy'}, {SQUADS} squads, {RUNS} runs)")
    below = [r for r in results if not r["passed"]]
    if below:
        info("Below target: " + ", ".join(f"{r['name']} {r['win_rate']:.0%}" for r in below))

def print_summary():
    header("SUMMARY")
    passed = sum(1 for _, ok in _results if ok)
    print(f"\n  {passed}/{len(_results)} scenarios met the win-rate target\n")
    for n, ok in _results:
        if not ok:
            print(f"    {RED}✗{RESET} {n}")
    return passed == len(_results)

# ── Entry point ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("migs-battle  ·  Multi-Squad Win-Rate Harness  (equip + retreat = average player)")
    print(f"squads={SQUADS}  runs/scenario={RUNS}  target={WIN_THRESHOLD:.0%}  "
          f"deploy={'FREE' if FREE_DEPLOY else 'paid'}  speed={SPEED}x")
    print("Connecting to DebugServer on 127.0.0.1:6560 ...\n")
    try:
        send({"action": "state"})
    except Exception as e:
        print(f"ERROR: cannot reach DebugServer: {e}")
        sys.exit(1)

    scen_list = ([(ONLY_SCEN, dict(SCENARIOS)[ONLY_SCEN])] if ONLY_SCEN >= 0 else SCENARIOS)
    results = []
    try:
        # Measure ALL scenarios (rewards advance via start_campaign, not via winning),
        # so we get the full difficulty curve even where the win rate is low.
        for i, (s_idx, s_name) in enumerate(scen_list):
            results.append(play_scenario(s_idx, s_name, first=(i == 0)))
    finally:
        set_time_scale(1.0)

    print_report(results)
    ok = print_summary()
    sys.exit(0 if ok else 1)
