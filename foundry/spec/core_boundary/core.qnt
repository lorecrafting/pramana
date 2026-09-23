// Core's guarantees under an adversarial controller.
//
// One ticket, two attempts, two effects (effect e runs execution e), one start ledger, one
// policy revision change, root control active/cancel_requested. The controller is
// ADVERSARIAL: every step it may submit any well-formed protected command or atomic bundle
// (plan or proposal carrier, any discriminator kind, bound or literal slot facts, any
// branch label, any expected revision). Core's checks are the only guards. SQL is
// abstracted away: one step is one committed Gateway transaction.
//
// Line citations are foundry/lib/pramana_foundry/durable_store/<file>:<line> at df1ac5f8.
// PP = protected_primitives.ex, TP = transition_plan.ex, GW = gateway.ex.
//
// Two step relations:
//   step       Core as built at df1ac5f8.
//   stepFixed  Core plus one proposed rule (FIX below): a slot-typed event may carry its
//              slot only through a binding, so literal settlements are refused.
// Red controls: delete the line tagged RED-A or RED-B (see README.md).
module core {
  pure val EFFECTS = Set(1, 2)
  pure val ATTEMPTS = Set(1, 2)
  pure val GRANT = 2
  pure val MAX_REV = 3
  // infrastructure_attempt_limits[role] per policy revision; the one revision change lowers it.
  pure def limitAt(rev: int): int = if (rev == 0) 2 else 1
  pure val TERMINAL = Set("non_started", "succeeded", "failed", "cancelled") // PP:8
  pure val CLOSED_RESV = Set("consumed", "released", "retired", "none")      // PP:9

  type Effect = {
    st: str,          // none pending claimed issued non_started succeeded unknown cancelled
    att: int,
    ord: int,         // lineage operation_ordinal
    pred: int,        // predecessor effect, 0 = none
    polRev: int,      // policy_revision the effect names
    ctlRev: int,      // control_revision the effect names
    units: int,       // reserved start units
    resv: str,        // none proposed reserved issued_unknown consumed released
    nsOrd: int,       // settlement ordinal if non_started (PP:214)
    createdAt: int,
    // ghosts: truth recorded at commit, independent of the guard that admitted it
    polAtCreate: int,
    ctlAtCreate: int,
    issueOk: bool     // at issue: control active, both revisions current, predecessor terminal
  }

  // A committed domain event, reduced to what Core's guarantees talk about.
  type Event = {
    kind: str,        // launch_settled attempt_settled launch_planned control
    exec: int,        // execution the event names
    fact: int,        // effect (or attempt) the carried fact names
    branch: str,      // below / reached for a settlement
    exhausted: bool,  // attempt_settled(exhausted), a controller disposition
    expRev: int,      // ticket projection revision the command expected
    preRev: int,      // ticket projection revision actually current at commit
    // controller-side context at commit
    domPaused: bool,
    domCancel: bool,
    avail: int
  }

  type State = {
    eff: int -> Effect,
    avail: int,
    polRev: int,
    ctlRev: int,
    ctlActive: bool,        // root control status == "active" (PP:3171)
    closedAt: int -> int,   // root_attempt_closures, 0 = open
    clock: int,
    ticketRev: int,         // durable revision of the ticket projection
    events: List[Event],
    domPaused: bool,        // kernel control entity: controller state
    domCancel: bool         // ticket cancel_requested: controller state
  }

  var s: State

  pure val NONE_EFFECT: Effect = {
    st: "none", att: 0, ord: 0, pred: 0, polRev: 0, ctlRev: 0, units: 0, resv: "none",
    nsOrd: 0, createdAt: 0, polAtCreate: 0, ctlAtCreate: 0, issueOk: false
  }

  action init = s' = {
    eff: EFFECTS.mapBy(_ => NONE_EFFECT),
    avail: GRANT,
    polRev: 0,
    ctlRev: 0,
    ctlActive: true,
    closedAt: ATTEMPTS.mapBy(_ => 0),
    clock: 1,
    ticketRev: 0,
    events: [],
    domPaused: false,
    domCancel: false
  }

  // ---------------------------------------------------------------- Core checks (pure)

  pure def limitBranch(ordinal: int, limit: int): str =   // PP:332-352
    if (ordinal < limit) "below" else "reached"

  pure def lineage(st: State, a: int): Set[int] =
    EFFECTS.filter(f => st.eff.get(f).st != "none" and st.eff.get(f).att == a)

  pure def nonstarts(st: State, a: int): int =
    lineage(st, a).filter(f => st.eff.get(f).st == "non_started").size()

  // PP:3203-3228: count < limit at the CURRENT policy, or no prior non-start.
  pure def allowanceOk(st: State, a: int): bool =
    nonstarts(st, a) == 0 or nonstarts(st, a) < limitAt(st.polRev)

  // PP:3435-3470 predecessor_guard: first in lineage has ord 0 and no predecessor; otherwise
  // the predecessor is the latest in lineage and terminal, and ord is its ord + 1.
  pure def predGuard(st: State, a: int, pred: int, ord: int): bool =
    val lin = lineage(st, a)
    if (lin.size() == 0) ord == 0 and pred == 0
    else lin.exists(l =>
      lin.forall(m => st.eff.get(m).ord <= st.eff.get(l).ord)
      and pred == l and ord == st.eff.get(l).ord + 1 and TERMINAL.contains(st.eff.get(l).st))

  // PP:3473-3494 predecessor_current?
  pure def predCurrent(st: State, e: int): bool =
    val x = st.eff.get(e)
    (x.ord == 0 and x.pred == 0) or (x.pred != 0 and x.pred != e
      and TERMINAL.contains(st.eff.get(x.pred).st)
      and st.eff.get(x.pred).att == x.att and st.eff.get(x.pred).ord + 1 == x.ord)

  // claim_effect PP:1347-1356 and issue_claim PP:1405-1413 share these.
  pure def launchChecks(st: State, e: int): bool =
    val x = st.eff.get(e)
    st.polRev == x.polRev and st.ctlRev == x.ctlRev and st.ctlActive
      and predCurrent(st, e) and x.resv == "reserved"

  pure def attemptOpen(st: State, a: int): bool = st.closedAt.get(a) == 0  // PP:3326-3337

  pure def tick(st: State): State = { ...st, clock: st.clock + 1 }

  pure def setEff(st: State, e: int, x: Effect): State = { ...st, eff: st.eff.set(e, x) }

  // ------------------------------------------------ protected commands (any order, any args)

  action reserve(e: int, units: int): bool = all {        // PP:998-1036
    s.eff.get(e).resv == "none", s.eff.get(e).st == "none",
    units > 0, units <= s.avail,                          // PP:1006
    s' = tick({ ...setEff(s, e, { ...s.eff.get(e), resv: "proposed", units: units }),
                avail: s.avail - units })
  }

  action createEffect(e: int, a: int, pred: int, ord: int, pr: int, cr: int): bool = all {
    s.eff.get(e).st == "none",
    s.eff.get(e).resv == "proposed",                      // load_effect_reservations
    attemptOpen(s, a),                                    // PP:1229  RED-B
    predGuard(s, a, pred, ord),                           // PP:1232
    pr == s.polRev, cr == s.ctlRev,                       // PP:1254-1255
    s.ctlActive,                                          // PP:1256 -> PP:3171
    allowanceOk(s, a),                                    // PP:1257
    s' = tick(setEff(s, e, { ...s.eff.get(e),
      st: "pending", att: a, ord: ord, pred: pred, polRev: pr, ctlRev: cr,
      resv: "reserved", createdAt: s.clock, polAtCreate: s.polRev, ctlAtCreate: s.ctlRev }))
  }

  action claimEffect(e: int): bool = all {                // PP:1338-1396
    s.eff.get(e).st == "pending", launchChecks(s, e),
    s' = tick(setEff(s, e, { ...s.eff.get(e), st: "claimed" }))
  }

  // issue_claim PP:1398-1447. Also reached inside a launch bundle (launchBundle).
  pure def issued(st: State, e: int): State =
    val x = st.eff.get(e)
    val ok = st.ctlActive and st.ctlRev == x.ctlRev and st.polRev == x.polRev
      and predCurrent(st, e)
    setEff(st, e, { ...x, st: "issued", resv: "issued_unknown", issueOk: ok })

  action issueClaim(e: int): bool = all {
    s.eff.get(e).st == "claimed", launchChecks(s, e),
    s' = tick(issued(s, e))
  }

  action cancelPending(e: int): bool = all {              // PP:1762-1769
    s.eff.get(e).st == "pending",
    s' = tick({ ...setEff(s, e, { ...s.eff.get(e), st: "cancelled", resv: "released" }),
                avail: s.avail + s.eff.get(e).units })
  }

  // settle_claim PP:1501-1539; the non-start ordinal counts this one (PP:208-214).
  pure def settled(st: State, e: int, outcome: str): State =
    val x = st.eff.get(e)
    if (outcome == "non_started")
      { ...setEff(st, e, { ...x, st: "non_started", resv: "released",
                           nsOrd: nonstarts(st, x.att) + 1 }),
        avail: st.avail + x.units }
    else if (outcome == "succeeded")
      setEff(st, e, { ...x, st: "succeeded", resv: "consumed" })
    else setEff(st, e, { ...x, st: "unknown" })

  action settleClaim(e: int, outcome: str): bool = all {
    s.eff.get(e).st == "issued",
    s' = tick(settled(s, e, outcome))
  }

  pure def closable(st: State, a: int): bool =            // PP:1563-1573
    attemptOpen(st, a)
      and lineage(st, a).forall(f => TERMINAL.contains(st.eff.get(f).st)
                                     and CLOSED_RESV.contains(st.eff.get(f).resv))

  action closeAttempt(a: int): bool = all {
    closable(s, a),
    s' = tick({ ...s, closedAt: s.closedAt.set(a, s.clock) })
  }

  action setControl(active: bool): bool = all {           // set_control, PP:745
    s.ctlRev < MAX_REV,
    s' = tick({ ...s, ctlActive: active, ctlRev: s.ctlRev + 1 })
  }

  action revisePolicy: bool = all {                       // set_policy, PP:741
    s.polRev == 0,
    s' = tick({ ...s, polRev: 1 })
  }

  // --------------------------------------------------------------- atomic bundles

  // CAS on the ticket projection the bundle writes: GW:1874-1893, required reads GW:1895-1906.
  pure def emit(st: State, ev: Event, exp: int): State =
    { ...st, events: st.events.append({ ...ev, expRev: exp, preRev: st.ticketRev,
        domPaused: st.domPaused, domCancel: st.domCancel, avail: st.avail }),
      ticketRev: st.ticketRev + 1 }

  pure val EV: Event = { kind: "", exec: 0, fact: 0, branch: "", exhausted: false, expRev: 0,
    preRev: 0, domPaused: false, domCancel: false, avail: 0 }

  // Settle bundle: stages settle_claim(e, outcome) and commits a launch_settled.
  //  carrier "plan": bound -> the fact is derived from the staged result (TP:184-198);
  //                  unbound -> the event carries the controller's literal `forged`.
  //  carrier "proposal": the event is the controller's, verbatim (GW:1294-1295).
  //  disc: "limit" (infrastructure_limit_v1) or "uncond" (unconditional_v1).
  //  wb: the branch the controller writes when Core does not derive one.
  pure def settleBundleOk(st: State, fixed: bool, e: int, outcome: str, carrier: str,
                          disc: str, bound: bool, exec: int): bool = and {
    st.eff.get(e).st == "issued",
    if (carrier == "proposal") not(fixed)                          // FIX
    else if (bound) and {
      outcome == "non_started",                    // only non-starts yield the fact (GW:936-949)
      disc == "limit",                             // TP:382-384  RED-A
      exec == e                                    // TP:705-718 settlement_execution_mismatch
    }
    else and {
      disc == "uncond",                            // limit with no binding: GW:1338-1352
      not(fixed)                                   // FIX
    }
  }

  action settleBundle(fixed: bool, e: int, outcome: str, carrier: str, disc: str,
                      bound: bool, exec: int, forged: int, wb: str, exp: int): bool = all {
    settleBundleOk(s, fixed, e, outcome, carrier, disc, bound, exec),
    exp == s.ticketRev,                                            // GW:1885
    val post = settled(s, e, outcome)
    val x = post.eff.get(e)
    val fact = if (carrier == "plan" and bound) e else forged
    val branch = if (carrier == "plan" and disc == "limit")
                   limitBranch(x.nsOrd, limitAt(x.polRev))         // PP:346, GW:1314-1326
                 else wb
    s' = tick(emit(post, { ...EV, kind: "launch_settled", exec: exec, fact: fact,
                           branch: branch }, exp))
  }

  // Launch bundle: stages issue_claim(e) and commits launch_planned with its authority
  // (launch_authority_v1, TP:55). The reserve/create/claim legs are the commands above.
  action launchBundle(fixed: bool, e: int, carrier: str, bound: bool, forged: int,
                      exp: int): bool = all {
    s.eff.get(e).st == "claimed", launchChecks(s, e),
    if (carrier == "plan" and bound) true else not(fixed),         // FIX
    exp == s.ticketRev,
    val fact = if (carrier == "plan" and bound) e else forged
    s' = tick(emit(issued(s, e), { ...EV, kind: "launch_planned", exec: fact, fact: fact },
                   exp))
  }

  // Close bundle: stages close_attempt(a) when bound; commits attempt_settled. The
  // disposition (exhausted or not) is the controller's.
  action closeBundle(fixed: bool, a: int, carrier: str, bound: bool, forged: int,
                     exhausted: bool, exp: int): bool = all {
    if (carrier == "plan" and bound) closable(s, a) else not(fixed),  // FIX
    exp == s.ticketRev,
    val pre = if (carrier == "plan" and bound) { ...s, closedAt: s.closedAt.set(a, s.clock) }
              else s
    val fact = if (carrier == "plan" and bound) a else forged
    s' = tick(emit(pre, { ...EV, kind: "attempt_settled", fact: fact, exhausted: exhausted },
                   exp))
  }

  // Controller-only domain state: pause/drain entity and ticket cancel_requested. Core
  // never reads either (the kernel's control entity is not protected, GW:1284-1293).
  action controllerControl(paused: bool, cancel: bool, exp: int): bool = all {
    exp == s.ticketRev,
    s' = tick({ ...emit(s, { ...EV, kind: "control" }, exp),
                domPaused: paused, domCancel: cancel })
  }

  // ------------------------------------------------------------------ the adversary

  action adversary(fixed: bool): bool = {
    nondet e = EFFECTS.oneOf()
    nondet f = EFFECTS.oneOf()
    nondet a = ATTEMPTS.oneOf()
    nondet pred = Set(0, 1, 2).oneOf()
    nondet ord = Set(0, 1).oneOf()
    nondet units = Set(1, 2).oneOf()
    nondet pr = Set(s.polRev, 1 - s.polRev).oneOf()              // current or stale
    nondet cr = Set(s.ctlRev, s.ctlRev - 1).oneOf()              // current or stale
    nondet outcome = Set("non_started", "succeeded", "unknown").oneOf()
    nondet carrier = Set("plan", "proposal").oneOf()
    nondet disc = Set("limit", "uncond").oneOf()
    nondet bound = Set(true, false).oneOf()
    nondet wb = Set("below", "reached").oneOf()
    nondet flag = Set(true, false).oneOf()
    nondet flag2 = Set(true, false).oneOf()
    nondet exp = Set(s.ticketRev, s.ticketRev - 1).oneOf()       // current or stale
    any {
      reserve(e, units),
      createEffect(e, a, pred, ord, pr, cr),
      claimEffect(e),
      issueClaim(e),
      cancelPending(e),
      settleClaim(e, outcome),
      closeAttempt(a),
      setControl(flag),
      revisePolicy,
      settleBundle(fixed, e, outcome, carrier, disc, bound, f, f, wb, exp),
      launchBundle(fixed, e, carrier, bound, f, exp),
      closeBundle(fixed, a, carrier, bound, f, flag, exp),
      controllerControl(flag, flag2, exp),
      // Well-formed instances of the moves above. They add no behaviour (each is one of
      // the adversary's choices); they only steer the simulator into deep states.
      createEffect(e, a, latest(s, a), nextOrd(s, a), s.polRev, s.ctlRev),
      settleBundle(fixed, e, "non_started", "plan", "limit", true, e, f, wb, s.ticketRev),
      closeBundle(fixed, a, "plan", true, f, flag, s.ticketRev),
    }
  }

  pure def latest(st: State, a: int): int =
    lineage(st, a).fold(0, (acc, l) =>
      if (acc == 0 or st.eff.get(l).ord > st.eff.get(acc).ord) l else acc)

  pure def nextOrd(st: State, a: int): int =
    if (latest(st, a) == 0) 0 else st.eff.get(latest(st, a)).ord + 1

  action step = adversary(false)
  action stepFixed = adversary(true)

  // ================================================================ Core's guarantees
  // Design status block (C3) and protected items spec.

  pure def evs(st: State): Set[Event] = st.events.indices().map(i => st.events[i])

  // Revisions/CAS: every committed domain event's expected revision was current.
  val casCurrent = evs(s).forall(ev => ev.expRev == ev.preRev)

  // Revisions: every effect names the policy and control revisions current at creation.
  val createdAtCurrentRevisions = EFFECTS.forall(e => s.eff.get(e).st == "none" or
    (s.eff.get(e).polRev == s.eff.get(e).polAtCreate
     and s.eff.get(e).ctlRev == s.eff.get(e).ctlAtCreate))

  // Control status + predecessor currency: nothing is issued unless root control was
  // active, both revisions were current, and the predecessor was terminal, at issue.
  pure val ISSUED_OR_LATER = Set("issued", "non_started", "succeeded", "unknown")
  val issuedUnderActiveControl = EFFECTS.forall(e =>
    ISSUED_OR_LATER.contains(s.eff.get(e).st) implies s.eff.get(e).issueOk)

  // Allocation at reserve: units are conserved and never overdrawn.
  val allocationConserved = s.avail >= 0 and
    s.avail + EFFECTS.fold(0, (acc, e) =>
      acc + (if (Set("proposed", "reserved", "issued_unknown", "consumed")
                   .contains(s.eff.get(e).resv)) s.eff.get(e).units else 0)) == GRANT

  // Predecessor currency (lineage): each non-first effect follows a terminal predecessor
  // in the same attempt with the previous ordinal.
  val lineageWellFormed = EFFECTS.forall(e => s.eff.get(e).st == "none" or
    (s.eff.get(e).ord == 0 and s.eff.get(e).pred == 0) or
    (s.eff.get(e).pred != 0 and s.eff.get(s.eff.get(e).pred).att == s.eff.get(e).att
     and s.eff.get(s.eff.get(e).pred).ord + 1 == s.eff.get(e).ord
     and TERMINAL.contains(s.eff.get(s.eff.get(e).pred).st)))

  // Non-start allowance: an effect exists after n prior non-starts in its attempt only if
  // n == 0 or n < the limit at the policy revision it was created under.
  val nonstartAllowance = EFFECTS.forall(e => s.eff.get(e).st == "none" or {
    val x = s.eff.get(e)
    val n = EFFECTS.filter(f => s.eff.get(f).st == "non_started" and s.eff.get(f).att == x.att
                                and s.eff.get(f).ord < x.ord).size()
    n == 0 or n < limitAt(x.polRev)
  })

  // Attempt closure is terminal: no effect under a closed attempt was created after the
  // close, and every effect under it is terminal.
  val closureTerminal = EFFECTS.forall(e => {
    val x = s.eff.get(e)
    x.st == "none" or s.closedAt.get(x.att) == 0 or
      (x.createdAt < s.closedAt.get(x.att) and TERMINAL.contains(x.st))
  })

  // Infrastructure-limit branch: a committed launch_settled's branch equals the limit
  // comparison at the settled effect's own policy revision.
  val limitBranchHolds = evs(s).forall(ev => ev.kind != "launch_settled" or {
    val x = s.eff.get(ev.fact)
    x.st == "non_started" and ev.branch == limitBranch(x.nsOrd, limitAt(x.polRev))
  })

  // Settlement-to-execution identity: a launch_settled names the execution whose effect it
  // settled, and that effect is a proved non-start.
  val settlementIdentity = evs(s).forall(ev => ev.kind != "launch_settled" or
    (ev.exec == ev.fact and s.eff.get(ev.fact).st == "non_started"))

  // Attempt closure as a fact: an attempt_settled names an attempt Core closed.
  val attemptSettledIsClosed = evs(s).forall(ev => ev.kind != "attempt_settled" or
    (ATTEMPTS.contains(ev.fact) and s.closedAt.get(ev.fact) > 0))

  // Launch authority: a launch_planned names an effect Core issued.
  val launchPlannedIsIssued = evs(s).forall(ev => ev.kind != "launch_planned" or
    ISSUED_OR_LATER.contains(s.eff.get(ev.fact).st))

  val coreInvariants = and {
    casCurrent, createdAtCurrentRevisions, issuedUnderActiveControl, allocationConserved,
    lineageWellFormed, nonstartAllowance, closureTerminal, limitBranchHolds,
    settlementIdentity, attemptSettledIsClosed, launchPlannedIsIssued
  }

  // ======================================== controller-side: Core does NOT claim these
  // Expected to FAIL under the adversary; a pass would mean the model is too weak.

  val ctlNoLaunchWhilePaused = evs(s).forall(ev => ev.kind != "launch_planned" or not(ev.domPaused))
  val ctlNoLaunchWhileCancel = evs(s).forall(ev => ev.kind != "launch_planned" or not(ev.domCancel))
  val ctlExhaustedOnlyWhenShort =
    evs(s).forall(ev => ev.kind != "attempt_settled" or not(ev.exhausted) or ev.avail == 0)

  // ===================================== scripted traces (quint test): reachability + gaps
  action check(p: bool): bool = all { assert(p), s' = s }

  // Non-start below the limit, retry, second non-start at the limit, then close.
  run boundSettleTest =
    init
      .then(reserve(1, 1)).then(createEffect(1, 1, 0, 0, 0, 0)).then(claimEffect(1))
      .then(issueClaim(1))
      .then(settleBundle(true, 1, "non_started", "plan", "limit", true, 1, 1, "reached", 0))
      .then(check(s.events[0].branch == "below" and coreInvariants))
      .then(reserve(2, 1)).then(createEffect(2, 1, 1, 1, 0, 0)).then(claimEffect(2))
      .then(issueClaim(2))
      .then(settleBundle(true, 2, "non_started", "plan", "limit", true, 2, 2, "below", 1))
      .then(check(s.events[1].branch == "reached" and coreInvariants))
      .then(closeBundle(true, 1, "plan", true, 1, true, 2))
      .then(check(coreInvariants and not(witnessClosedWithEffect)))

  // Under the as-built rules an unbound unconditional plan commits a forged settlement.
  run unboundBypassTest =
    init
      .then(reserve(1, 1)).then(createEffect(1, 1, 0, 0, 0, 0)).then(claimEffect(1))
      .then(issueClaim(1))
      .then(settleBundle(false, 1, "non_started", "plan", "uncond", false, 2, 2, "below", 0))
      .then(check(not(settlementIdentity) and not(limitBranchHolds)))

  // ================================ vacuity witnesses: each MUST be violated (reachable)
  // A retry (ordinal 1) created after a proved non-start in the same attempt.
  val witnessRetry = not(EFFECTS.exists(e => s.eff.get(e).ord == 1
    and s.eff.get(s.eff.get(e).pred).st == "non_started"))
  // A launch_settled committed through a bound plan, on each branch.
  val witnessBelow = not(evs(s).exists(ev => ev.kind == "launch_settled" and ev.branch == "below"))
  val witnessReached = not(evs(s).exists(ev => ev.kind == "launch_settled" and ev.branch == "reached"))
  // An attempt closed with an effect under it.
  val witnessClosedWithEffect = not(EFFECTS.exists(e => s.eff.get(e).st != "none"
    and s.closedAt.get(s.eff.get(e).att) > 0))
}
