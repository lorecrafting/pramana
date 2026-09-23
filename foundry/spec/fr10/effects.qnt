// FR-10 commit 0: the effect / claim / receipt / reconciliation protocol AS DESIGNED in
// foundry/docs/fr-10/FR10-DESIGN-2026-09-23.md (D1-D5, operator answers Q2-Q4), not today's
// code. Every store action cites the protected operation it models in
// foundry/lib/pramana_foundry/durable_store/protected_primitives.ex ("PP:<line>", lines at
// 33395c92). Design-only actions cite the design section.
//
// Scope (design section 7): one ticket and attempt, one semantic operation with ordinals
// 0 (effect 0) and 1 (its retry, effect 1), two writer epochs, one reservation of one unit
// per effect on a two-unit ledger. One claim per effect: claim_effect needs a pending effect
// (PP:1344) and cancelling a claim cancels its effect (PP:1771-1793), so an effect never
// gets a second claim; the claim is folded into the effect record.
//
// Three variants share the actions and differ only in a flag record (see README.md):
//   step               - the design as written, with conflicting observations injected.
//   stepDesignHonest   - the design as written, no conflicting observations.
//   stepFixed          - two proposed corrections (F1, F2), no conflicting observations.
//   stepFixedAdversary - stepFixed with conflicting observations injected.
//   stepQ3Bug          - stepFixedAdversary with 69614867 reverted: the red control for I9.
module effects {
  pure val EFFECTS = Set(0, 1)
  pure val EPOCHS = Set(0, 1)
  pure val TOTAL = 2
  pure val RECQ = "reconciliation_required"
  // @closed_effect_statuses, PP:8
  pure val TERMINAL = Set("succeeded", "failed", "non_started", "cancelled")
  pure val KNOWN = Set("succeeded", "failed", "non_started")

  type Variant = {
    // F1: quiescence needs the issuer AND the delivery channel quiet (D3 accepts either).
    channelEvidence: bool,
    // F2: an `unknown` receipt after a known outcome is absorbed, not quarantined.
    absorbStaleUnknown: bool,
    // 69614867: a reconciliation_required claim re-quarantines on any non-exact receipt.
    q3Guard: bool,
    // Conflicting observations (same receipt id, different digest) are injected.
    adversary: bool,
  }
  pure val DESIGN = { channelEvidence: false, absorbStaleUnknown: false, q3Guard: true, adversary: true }
  pure val FIXED = { channelEvidence: true, absorbStaleUnknown: true, q3Guard: true, adversary: false }

  type Eff = {
    st: str,           // none | pending | claimed | issued | unknown | RECQ | TERMINAL
    claimEpoch: int,   // claim.writer_epoch; -1 before claim
    issuedBy: int,     // epoch whose worker holds the issued operation; -1 before issue
    res: str,          // none | reserved | issued_unknown | consumed | released
    exec: str,         // D1 execution: none | pending | running | unknown | closed
    log: Set[str],     // stored receipt outcomes (receipt id = (effect, outcome))
    quarantined: bool, // entered RECQ and not yet recovered (Q3)
    dispatched: bool,  // the worker handed the operation to the delivery channel
    ext: str,          // external world: none | started | done
    extOut: str,       // succeeded | failed once done
    starts: int,       // external starts of this effect
    resSettles: int,   // terminal settlements of this effect's reservation
  }

  var eff: int -> Eff
  var avail: int
  var held: int
  var consumed: int
  var epoch: int
  var alive: int -> bool         // the worker (issuer) process of each epoch
  var channel: Set[int]          // deliveries in flight: they survive their issuer
  var inflight: Set[(int, str)]  // receipts in flight; kept after delivery, so they duplicate
  var attemptClosed: bool
  var lastReceipt: int           // effect named by the receipt delivered this step, else -1
  var touched: Set[int]          // effects whose record the last step changed

  pure val NONE: Eff = { st: "none", claimEpoch: -1, issuedBy: -1, res: "none", exec: "none",
    log: Set(), quarantined: false, dispatched: false, ext: "none", extOut: "",
    starts: 0, resSettles: 0 }

  action init = all {
    eff' = EFFECTS.mapBy(_ => NONE),
    avail' = TOTAL, held' = 0, consumed' = 0,
    epoch' = 0,
    alive' = Map(0 -> true, 1 -> false),
    channel' = Set(), inflight' = Set(),
    attemptClosed' = false, lastReceipt' = -1, touched' = Set(),
  }

  // ---------- pure settlement logic ----------

  type Out = { r: Eff, da: int, dh: int, dc: int }
  pure def same(r: Eff): Out = { r: r, da: 0, dh: 0, dc: 0 }

  // quarantine_conflicting_receipt PP:2001-2016: status -> RECQ, leases retained, no units
  // move, and the conflicting receipt is NOT stored.
  pure def quarantine(r: Eff): Out = same({ ...r, st: RECQ, quarantined: true })

  // first_settlement PP:1970 / reconciled_settlement PP:1936: status := outcome, receipt
  // stored; settle_reservations PP:3898-3920 (unknown moves nothing); reservation_settlement
  // PP:3922-3936 (succeeded/failed consume, non_started releases); settle_leases PP:3938.
  // D1: succeeded -> running, non_started -> closed, unknown -> unknown.
  // ASSUMPTION (D1 is silent): failed -> running, and a closed execution never reopens.
  pure def apply(r: Eff, o: str): Out =
    val exec2 = if (not(Set("pending", "unknown").contains(r.exec))) r.exec
                else if (o == "non_started") "closed"
                else if (o == "unknown") "unknown"
                else "running"
    val base = { ...r, st: o, log: r.log.union(Set(o)), exec: exec2 }
    if (o == "unknown") same(base)
    else if (o == "non_started")
      { r: { ...base, res: "released", resSettles: r.resSettles + 1 }, da: 1, dh: -1, dc: 0 }
    else
      { r: { ...base, res: "consumed", resSettles: r.resSettles + 1 }, da: 0, dh: -1, dc: 1 }

  // settle_claim PP:1501-1539 -> settle_with_receipts PP:1885-1921.
  pure def settle(r: Eff, o: str, v: Variant): Out =
    if (r.log.contains(o)) same(r)                        // exact duplicate, PP:1893-1902
    else if (v.q3Guard and r.st == RECQ) quarantine(r)    // 69614867, PP:1907-1908
    else if (r.log != Set())
      if (o != "unknown" and r.log.forall(x => x == "unknown"))
        // reconciled_settlement PP:1911-1913; settle_reservations needs issued_unknown PP:3905
        (if (r.res == "issued_unknown") apply(r, o) else same(r))
      else if (v.absorbStaleUnknown and o == "unknown")
        same({ ...r, log: r.log.union(Set(o)) })          // F2 (proposal, not code)
      else quarantine(r)                                   // PP:1914-1916
    else if (Set("issued", "unknown").contains(r.st))      // first_settlement PP:1973
      apply(r, o)
    else same(r)                                           // rejected, no mutation

  // predecessor_guard PP:3425-3458 (terminal set PP:3454) at create; predecessor_current?
  // PP:3463-3486 at claim and issue.
  def predOk(e: int): bool = e == 0 or TERMINAL.contains(eff.get(0).st)

  // D3. As designed, non-start evidence is EITHER (a) the issuer's epoch is fenced and its
  // OS identity observed gone, OR (b) the backend reports no start (it sees its own channel).
  // Either way the backend must show nothing started. F1 requires (a) AND (b).
  def fenced(e: int): bool =
    val r = eff.get(e)
    r.issuedBy >= 0 and r.issuedBy < epoch and not(alive.get(r.issuedBy))
  def nonStartEvidence(e: int, v: Variant): bool =
    eff.get(e).ext == "none" and (
      if (v.channelEvidence) fenced(e) and not(channel.contains(e))
      else fenced(e) or not(channel.contains(e)))

  // ---------- frames ----------

  action commit(ne: int -> Eff, a: int, h: int, c: int, lr: int): bool = all {
    eff' = ne, avail' = a, held' = h, consumed' = c,
    touched' = EFFECTS.filter(x => ne.get(x) != eff.get(x)), lastReceipt' = lr,
    epoch' = epoch, alive' = alive, channel' = channel, inflight' = inflight,
    attemptClosed' = attemptClosed,
  }
  action putEff(e: int, r: Eff): bool = commit(eff.set(e, r), avail, held, consumed, -1)
  action putOut(e: int, x: Out, lr: int): bool =
    commit(eff.set(e, x.r), avail + x.da, held + x.dh, consumed + x.dc, lr)

  action env(ch: Set[int], inf: Set[(int, str)], ne: int -> Eff, ep: int, al: int -> bool): bool = all {
    channel' = ch, inflight' = inf, eff' = ne, epoch' = ep, alive' = al,
    avail' = avail, held' = held, consumed' = consumed, attemptClosed' = attemptClosed,
    lastReceipt' = -1, touched' = Set(),
  }

  // ---------- store actions (protected operations) ----------

  // create_effect PP:1211-1336: attempt open (attempt_open PP:3320), one semantic
  // (generation, ordinal) (PP:3383-3419), predecessor terminal, reservation activated.
  // D1: opens the execution as pending.
  action createEffect(e: int): bool = all {
    not(attemptClosed), eff.get(e).st == "none", avail >= 1, predOk(e),
    commit(eff.set(e, { ...eff.get(e), st: "pending", res: "reserved", exec: "pending" }),
           avail - 1, held + 1, consumed, -1),
  }

  // claim_effect PP:1338-1396: pending, predecessor current, reservations reserved; the
  // claim is stamped with the current writer epoch (PP:1344, :1359-1363).
  action claimEffect(e: int): bool = all {
    eff.get(e).st == "pending", predOk(e), eff.get(e).res == "reserved",
    putEff(e, { ...eff.get(e), st: "claimed", claimEpoch: epoch }),
  }

  // issue_claim PP:1398-1447: claimed, claim epoch == current epoch (PP:1402-1403),
  // reservations -> issued_unknown (PP:1419). The current epoch's worker now holds it.
  action issueClaim(e: int): bool = all {
    eff.get(e).st == "claimed", eff.get(e).claimEpoch == epoch, predOk(e),
    putEff(e, { ...eff.get(e), st: "issued", res: "issued_unknown", issuedBy: epoch }),
  }

  // reclaim_claim PP:1449-1499: claimed, from a prior epoch, proof issuer_quiescent
  // (PP:1455); D3 turns the token into evidence that the old issuer is gone.
  action reclaimClaim(e: int): bool = all {
    eff.get(e).st == "claimed", eff.get(e).claimEpoch < epoch,
    not(alive.get(eff.get(e).claimEpoch)),
    putEff(e, { ...eff.get(e), claimEpoch: epoch }),
  }

  // cancel_effect PP:1762-1769 (pending, unissued) and PP:1771-1793 (claimed,
  // issuer_quiescent), releasing via release_many PP:1863-1883. ASSUMPTION (D1 silent): the
  // execution of a never-issued effect closes. issued + control_ack (PP:1746-1760) only
  // reports the outstanding claim and changes nothing, so it is not an action.
  action cancelEffect(e: int): bool = all {
    Set("pending", "claimed").contains(eff.get(e).st),
    commit(eff.set(e, { ...eff.get(e), st: "cancelled", res: "released", exec: "closed",
                        resSettles: eff.get(e).resSettles + 1 }),
           avail + 1, held - 1, consumed, -1),
  }

  // An ordinary receipt reaches settle_claim. Provenance (settlement_provenance
  // PP:1923-1934) holds for the original issuer's actor whatever its epoch, so an
  // old-epoch worker's receipt is accepted.
  action deliverReceipt(e: int, o: str, v: Variant): bool = all {
    inflight.contains((e, o)),
    putOut(e, settle(eff.get(e), o, v), e),
  }

  // A second observation under an existing receipt id with a different digest
  // (observation_conflict? PP:1517, :1593-1601) or a request id bound to another claim
  // (PP:1520) quarantines whatever the claim's status. Adversarial input.
  action conflictingReceipt(e: int, v: Variant): bool = all {
    v.adversary, eff.get(e).issuedBy >= 0,
    putOut(e, quarantine(eff.get(e)), e),
  }

  // D4 + Q2: after restart the root recovery principal reconciles an outstanding claim of
  // a prior epoch. Exact backend observation -> its outcome; D3 non-start evidence ->
  // non_started; anything else -> unknown (holds stay). It settles through settle_claim.
  action recoverySettle(e: int, v: Variant): bool = all {
    Set("issued", "unknown").contains(eff.get(e).st),
    eff.get(e).issuedBy >= 0, eff.get(e).issuedBy < epoch,
    val o = if (eff.get(e).ext == "done") eff.get(e).extOut
            else if (nonStartEvidence(e, v)) "non_started"
            else "unknown"
    putOut(e, settle(eff.get(e), o, v), -1),
  }

  // Q3: the explicit recovery operation, the only exit from RECQ. Same evidence as D4. It
  // settles the reservation once if still held; an already-settled reservation keeps its
  // settlement and only a consistent outcome is restored.
  action recoverQuarantine(e: int, v: Variant): bool = {
    val r = eff.get(e)
    val o = if (r.ext == "done") r.extOut else if (nonStartEvidence(e, v)) "non_started" else ""
    val consistent = (r.res == "consumed" and Set("succeeded", "failed").contains(o))
                  or (r.res == "released" and o == "non_started")
    all {
      r.st == RECQ, o != "",
      if (r.res == "issued_unknown")
        putOut(e, apply({ ...r, quarantined: false }, o), -1)
      else all {
        consistent,
        putEff(e, { ...r, st: o, log: r.log.union(Set(o)), quarantined: false }),
      },
    }
  }

  // D1 close_execution: running or unknown -> closed only with termination evidence.
  action closeExecution(e: int, v: Variant): bool = all {
    (eff.get(e).exec == "running" and eff.get(e).ext == "done")
      or (eff.get(e).exec == "unknown" and (eff.get(e).ext == "done" or nonStartEvidence(e, v))),
    putEff(e, { ...eff.get(e), exec: "closed" }),
  }

  // close_attempt PP:1559-1588: every effect terminal (PP:1571), every activated
  // reservation consumed/released/retired (PP:1573); D1 adds every execution closed.
  // Closing an attempt with no effect is legal but dead-ends every simulation trace, so the
  // model requires E0 to exist.
  action closeAttempt: bool = all {
    not(attemptClosed), eff.get(0).st != "none",
    EFFECTS.forall(e => eff.get(e).st == "none" or (TERMINAL.contains(eff.get(e).st)
      and Set("consumed", "released").contains(eff.get(e).res) and eff.get(e).exec == "closed")),
    attemptClosed' = true,
    eff' = eff, avail' = avail, held' = held, consumed' = consumed, epoch' = epoch,
    alive' = alive, channel' = channel, inflight' = inflight, lastReceipt' = -1, touched' = Set(),
  }

  // ---------- environment ----------

  // The worker holding an issued operation hands it to the channel. It does not consult
  // the store again (AgentServer calls the adapter directly, design section 3).
  action dispatch(e: int): bool = all {
    eff.get(e).issuedBy >= 0, not(eff.get(e).dispatched), alive.get(eff.get(e).issuedBy),
    env(channel.union(Set(e)), inflight, eff.set(e, { ...eff.get(e), dispatched: true }), epoch, alive),
  }

  action externalStart(e: int): bool = all {
    channel.contains(e),
    env(channel.exclude(Set(e)), inflight,
        eff.set(e, { ...eff.get(e), ext: "started", starts: eff.get(e).starts + 1 }), epoch, alive),
  }

  action externalFinish(e: int, o: str): bool = all {
    eff.get(e).ext == "started",
    env(channel, inflight, eff.set(e, { ...eff.get(e), ext: "done", extOut: o }), epoch, alive),
  }

  // A live worker reports unknown at any time after dispatch (timeout, lost reply) and the
  // exact outcome once the external action is done.
  action workerReceipt(e: int, o: str): bool = all {
    eff.get(e).issuedBy >= 0, eff.get(e).dispatched, alive.get(eff.get(e).issuedBy),
    o == "unknown" or (eff.get(e).ext == "done" and eff.get(e).extOut == o),
    env(channel, inflight.union(Set((e, o))), eff, epoch, alive),
  }

  action dropReceipt(e: int, o: str): bool = all {
    inflight.contains((e, o)),
    env(channel, inflight.exclude(Set((e, o))), eff, epoch, alive),
  }

  // Gateway/Coordinator crash: a fresh writer epoch (gateway.ex:486-489). Durable state
  // survives; the old worker process may survive too and keep delivering.
  action crash: bool = all {
    epoch == 0,
    env(channel, inflight, eff, 1, alive.set(1, true)),
  }

  action hardKill(k: int): bool = all {
    alive.get(k),
    env(channel, inflight, eff, epoch, alive.set(k, false)),
  }

  // The simulator draws the nondet picks once per step and ends the trace when no branch is
  // enabled for them; stuttering lets the next step draw again.
  action stutter: bool = env(channel, inflight, eff, epoch, alive)

  action stepV(v: Variant): bool = {
    nondet e = EFFECTS.oneOf()
    nondet k = EPOCHS.oneOf()
    nondet fo = Set("succeeded", "failed").oneOf()
    nondet ro = Set("succeeded", "failed", "unknown").oneOf()
    any {
      createEffect(e), claimEffect(e), issueClaim(e), reclaimClaim(e), cancelEffect(e),
      deliverReceipt(e, ro, v), conflictingReceipt(e, v), recoverySettle(e, v),
      recoverQuarantine(e, v), closeExecution(e, v), closeAttempt,
      dispatch(e), externalStart(e), externalFinish(e, fo), workerReceipt(e, ro),
      dropReceipt(e, ro), crash, hardKill(k), stutter,
    }
  }
  action step = stepV(DESIGN)
  action stepDesignHonest = stepV(HONEST)
  action stepFixed = stepV(FIXED)
  action stepFixedAdversary = stepV(FIXED_ADV)
  action stepQ3Bug = stepV(Q3BUG)

  // ---------- invariants (design section 7, plus I9 for the Q3 answer) ----------

  def live(e: int): bool = eff.get(e).ext == "started" or channel.contains(e)

  // I1: at most one external start per claim and per semantic (generation, ordinal), and
  // no retry is live while its predecessor can still start or is running (no blind relaunch).
  val I1 = EFFECTS.forall(e => eff.get(e).starts <= 1) and not(live(0) and live(1))

  // I2: ledger conservation, and the ledger agrees with the reservations.
  val I2 = avail + held + consumed == TOTAL
    and held == EFFECTS.filter(e => Set("reserved", "issued_unknown").contains(eff.get(e).res)).size()
    and consumed == EFFECTS.filter(e => eff.get(e).res == "consumed").size()

  // I3: a released reservation means its external action never started.
  val I3 = EFFECTS.forall(e => eff.get(e).res == "released" implies eff.get(e).ext == "none")

  // I4: each reservation settles at most once.
  val I4 = EFFECTS.forall(e => eff.get(e).resSettles <= 1)

  // I5: an unknown or quarantined claim with no known outcome keeps its unit held.
  val I5 = EFFECTS.forall(e =>
    (Set("unknown", RECQ).contains(eff.get(e).st) and eff.get(e).log.intersect(KNOWN) == Set())
      implies eff.get(e).res == "issued_unknown")

  // I6: a live retry (pending, claimed or issued) has a terminal predecessor.
  val I6 = Set("pending", "claimed", "issued").contains(eff.get(1).st)
    implies TERMINAL.contains(eff.get(0).st)

  // I7: a delivered receipt, from any epoch, changes only its own claim.
  val I7 = lastReceipt >= 0 implies touched.subseteq(Set(lastReceipt))

  // I8: after close_attempt every execution is closed and no external action is pending.
  val I8 = attemptClosed implies EFFECTS.forall(e => eff.get(e).st == "none" or
    (eff.get(e).exec == "closed" and eff.get(e).ext != "started" and not(channel.contains(e))))

  // I9 (Q3): a claim leaves reconciliation_required only through recoverQuarantine.
  val I9 = EFFECTS.forall(e => eff.get(e).quarantined implies eff.get(e).st == RECQ)

  val allInvariants = I1 and I2 and I3 and I4 and I5 and I6 and I7 and I8 and I9

  // ---------- witness runs (`quint test`): paths too long for random simulation ----------

  pure val HONEST = { ...DESIGN, adversary: false }
  pure val FIXED_ADV = { ...FIXED, adversary: true }
  pure val Q3BUG = { ...FIXED, adversary: true, q3Guard: false }

  // Issue E0 and hand it to the channel; the worker reports a timeout (unknown), which
  // settles; a conflicting observation quarantines; then the action really succeeds and
  // the worker reports it.
  run quarantinePrefix(v: Variant): bool =
    init.then(createEffect(0)).then(claimEffect(0)).then(issueClaim(0)).then(dispatch(0))
      .then(workerReceipt(0, "unknown")).then(deliverReceipt(0, "unknown", v))
      .then(conflictingReceipt(0, v))
      .then(externalStart(0)).then(externalFinish(0, "succeeded"))
      .then(workerReceipt(0, "succeeded"))

  // Red control: with 69614867 reverted, the ordinary receipt settles the quarantined
  // claim (consuming its unit) and I9 fails.
  run q3RedControlTest =
    quarantinePrefix(Q3BUG).then(deliverReceipt(0, "succeeded", Q3BUG))
      .expect(not(I9) and eff.get(0).st == "succeeded" and eff.get(0).res == "consumed")

  // The same path with the guard: the receipt re-quarantines, no unit moves, I9 holds.
  run q3GuardHoldsTest =
    quarantinePrefix(FIXED_ADV).then(deliverReceipt(0, "succeeded", FIXED_ADV))
      .expect(I9 and eff.get(0).st == RECQ and eff.get(0).res == "issued_unknown")

  // Finding A: E0 is in the channel when its worker dies; after restart D3(a) (fenced and
  // gone) proves a non-start, the unit is released, the retry launches and E0 still starts.
  run channelPrefix(v: Variant): bool =
    init.then(createEffect(0)).then(claimEffect(0)).then(issueClaim(0)).then(dispatch(0))
      .then(crash).then(hardKill(0)).then(recoverySettle(0, v))

  run blindRelaunchTest =
    channelPrefix(HONEST)
      .then(createEffect(1)).then(claimEffect(1)).then(issueClaim(1)).then(dispatch(1))
      .then(externalStart(0))
      .expect(not(I1) and not(I3))

  // With F1 the same evidence settles only `unknown`: the unit stays held, no retry.
  run channelEvidenceHoldsTest =
    channelPrefix(FIXED)
      .expect(eff.get(0).st == "unknown" and eff.get(0).res == "issued_unknown" and I1 and I3)
}
