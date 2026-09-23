// Quint model of Foundry's R5 budget ledger, as the CODE implements it.
//
// Source: foundry/lib/pramana_foundry/durable_store/protected_primitives.ex at df1ac5f8
// (cited below as PP:<line>). Contract: foundry/docs/WORKFLOW-CONTRACT.md "Budget ledger — R5".
// Where the two disagree the code is modelled and the disagreement is marked DISAGREE.
//
// Bounds: fixed tree root -> obj -> tkt, generations 0..1, one dimension, units 1..2,
// two reservations, two effects (one claim per effect; claim status == effect status, which
// validate_effect_relations PP:6105 enforces). Every operation is one transaction: a guard
// that fails in the code is a disabled action here.
//
// Omitted deliberately: the per-ledger write guard conserved? (PP:3019, used by
// update_ledger). Leaving it out makes PerNodeConservation check each action's arithmetic
// instead of holding by construction. Leases, policy/control revisions, writer epochs, read
// sets and reclaim_claim move no units and are not modelled.
module ledger {
  type LKey = (str, int)
  type Ledger = { exists: bool, parent: str, pgen: int, open: bool, auth: int, avail: int,
                  held: int, cons: int, deleg: int, ret: int, authAtClose: int }
  type Res = { status: str, node: str, gen: int, units: int, owner: str, bound: bool,
               explicit: bool }
  // Trace label only; gen/units are -1/0 where not applicable.
  type Act = { op: str, id: str, gen: int, units: int, detail: str }
  pure def act(op: str, id: str, gen: int, units: int, detail: str): Act =
    { op: op, id: id, gen: gen, units: units, detail: detail }
  // qHeld (ghost): when first quarantined, the claim still held every one of its units.
  type Eff = { status: str, resIds: Set[str], receipts: Set[str], hasClaim: bool, qHeld: bool }

  // Red control switch: true seeds "reset refunds held units" into the root reset.
  pure val SEEDED_BUG = false

  pure val NODES = Set("root", "obj", "tkt")
  pure val CHILD = Map("root" -> "obj", "obj" -> "tkt")
  pure val GENS = 0.to(1)
  pure val KEYS = tuples(NODES, GENS)
  pure val RESV = Set("r1", "r2")
  pure val EFFS = Set("e1", "e2")
  pure val UNITS = 1.to(2)
  pure val OUTCOMES = Set("succeeded", "failed", "non_started", "unknown")
  pure val KNOWN = Set("succeeded", "failed", "non_started")

  pure val NOLEDGER: Ledger = { exists: false, parent: "", pgen: -1, open: false, auth: 0,
    avail: 0, held: 0, cons: 0, deleg: 0, ret: 0, authAtClose: 0 }
  pure val NORES: Res = { status: "absent", node: "", gen: -1, units: 0, owner: "",
    bound: false, explicit: false }
  pure val NOEFF: Eff = { status: "absent", resIds: Set(), receipts: Set(), hasClaim: false,
    qHeld: false }

  var ledgers: LKey -> Ledger
  var res: str -> Res
  var eff: str -> Eff
  var granted: int          // sum of grant_ledger units: the only source of authority
  var attemptClosed: bool   // one (ticket, attempt) owns both effects
  var lastAction: Act

  pure def sumOver(s: Set[a], f: a => int): int = s.fold(0, (acc, x) => acc + f(x))
  def L(k: LKey): Ledger = ledgers.get(k)
  def R(r: str): Res = res.get(r)
  def E(e: str): Eff = eff.get(e)
  def keyOf(r: str): LKey = (R(r).node, R(r).gen)

  // current_generation PP:2908: max generation for the id.
  def curGen(n: str): int = if (L((n, 1)).exists) 1 else 0
  def children(k: LKey): Set[LKey] =
    KEYS.filter(c => L(c).exists and L(c).parent == k._1 and L(c).pgen == k._2)
  // subtree_ledgers PP:1611 (recursive CTE). Depth is at most 3 here.
  def subtree(k: LKey): Set[LKey] =
    Set(k).union(children(k)).union(children(k).fold(Set(), (s, c) => s.union(children(c))))
  // reservations_for_effect PP:3740 (by owner) and reservations_for_claim PP:3751 (by claim_id).
  def resOf(e: str): Set[str] = RESV.filter(r => R(r).status != "absent" and R(r).owner == e)
  def boundOf(e: str): Set[str] = resOf(e).filter(r => R(r).bound)
  // reservations_open? PP:3133
  def resOpenCurrent(rs: Set[str]): bool =
    rs.forall(r => L(keyOf(r)).open and curGen(R(r).node) == R(r).gen)

  // release_hold PP:3152: held -> available if open, held -> retired if closed.
  pure def releaseHold(l: Ledger, u: int): Ledger =
    if (l.open) { ...l, held: l.held - u, avail: l.avail + u }
    else { ...l, held: l.held - u, ret: l.ret + u }

  // close_subtree PP:1657. Pass 1: for each open ledger, revoke_unissued_generation PP:1689
  // releases its "reserved" reservations (ledger still open, so held -> available, status
  // "released") and cancel_unissued_effect_owners PP:1703 cancels their pending/claimed
  // owner effects (and claims). issued_unknown holds are untouched. Pass 2: every open
  // ledger closes and moves available -> retired.
  def closeSubtree(k: LKey): (LKey -> Ledger, str -> Res, str -> Eff) = {
    val openSub = subtree(k).filter(c => L(c).open)
    val revoked = RESV.filter(r => R(r).status == "reserved" and openSub.contains(keyOf(r)))
    val owners = revoked.map(r => R(r).owner).filter(e => Set("pending", "claimed").contains(E(e).status))
    val l2 = KEYS.mapBy(c =>
      if (openSub.contains(c)) {
        val lc = L(c)
        val freed = sumOver(revoked.filter(r => keyOf(r) == c), r => R(r).units)
        { ...lc, held: lc.held - freed, avail: 0, ret: lc.ret + lc.avail + freed, open: false,
          authAtClose: lc.auth }
      } else L(c))
    val r2 = RESV.mapBy(r => if (revoked.contains(r)) { ...R(r), status: "released" } else R(r))
    val e2 = EFFS.mapBy(e => if (owners.contains(e)) { ...E(e), status: "cancelled" } else E(e))
    (l2, r2, e2)
  }

  action init = all {
    ledgers' = KEYS.mapBy(k => NOLEDGER),
    res' = RESV.mapBy(r => NORES),
    eff' = EFFS.mapBy(e => NOEFF),
    granted' = 0,
    attemptClosed' = false,
    lastAction' = act("init", "", -1, 0, ""),
  }

  // grant_ledger PP:866: a root ledger at an absent (id, generation).
  action grantRoot(g: int, u: int): bool = all {
    not(L(("root", g)).exists),
    ledgers' = ledgers.set(("root", g), { ...NOLEDGER, exists: true, open: true, auth: u, avail: u }),
    granted' = granted + u,
    res' = res, eff' = eff, attemptClosed' = attemptClosed,
    lastAction' = act("grant_ledger", "root", g, u, ""),
  }

  // delegate_allocation PP:897: parent open, 0 < units <= parent.available, child absent.
  // Model restriction: the child id is the fixed tree child; the code accepts any other id
  // and any child generation.
  action delegate(p: str, pg: int, cg: int, u: int): bool = all {
    p != "tkt",
    val pk = (p, pg)
    val ck = (CHILD.get(p), cg)
    all {
      L(pk).exists, L(pk).open, u <= L(pk).avail, not(L(ck).exists),
      ledgers' = ledgers
        .set(pk, { ...L(pk), avail: L(pk).avail - u, deleg: L(pk).deleg + u })
        .set(ck, { ...NOLEDGER, exists: true, parent: p, pgen: pg, open: true, auth: u, avail: u }),
      lastAction' = act("delegate_allocation", ck._1, cg, u, p),
    },
    res' = res, eff' = eff, granted' = granted, attemptClosed' = attemptClosed,
  }

  // return_allocation PP:952: child and parent open, units <= child.available, child
  // held == 0 and delegated == 0 (stricter than the contract, which forbids only returning
  // held/consumed units).
  action returnAlloc(c: str, cg: int, u: int): bool = all {
    c != "root",
    val ck = (c, cg)
    val pk = (L(ck).parent, L(ck).pgen)
    all {
      L(ck).exists, L(ck).open, L(pk).open, u <= L(ck).avail,
      L(ck).held == 0, L(ck).deleg == 0, L(pk).deleg - u >= 0,
      ledgers' = ledgers
        .set(ck, { ...L(ck), auth: L(ck).auth - u, avail: L(ck).avail - u })
        .set(pk, { ...L(pk), deleg: L(pk).deleg - u, avail: L(pk).avail + u }),
      lastAction' = act("return_allocation", c, cg, u, ""),
    },
    res' = res, eff' = eff, granted' = granted, attemptClosed' = attemptClosed,
  }

  // reserve PP:998: ledger open, units <= available, id fresh. Status "proposed"; NO units
  // move. DISAGREE: the contract's absent -> reserved moves available -> held; the code defers
  // that to create_effect's activation. The owner effect need not exist, and may already
  // exist (owner_id is not checked against effect state).
  action reserve(r: str, n: str, g: int, u: int, e: str): bool = all {
    R(r).status == "absent", L((n, g)).exists, L((n, g)).open, u <= L((n, g)).avail,
    res' = res.set(r, { ...NORES, status: "proposed", node: n, gen: g, units: u, owner: e }),
    ledgers' = ledgers, eff' = eff, granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("reserve", r, g, u, n),
  }

  // release_reservation PP:1039 with proof "unissued": status proposed/reserved/issued_unknown;
  // release_guard PP:3125 admits it only with no claim or a still-"claimed" claim. A
  // proposed reservation moves no units. Target released/retired by ledger status.
  action releaseReservation(r: str): bool = all {
    Set("proposed", "reserved", "issued_unknown").contains(R(r).status),
    not(R(r).bound) or E(R(r).owner).status == "claimed",
    ledgers' = if (R(r).status == "proposed") ledgers
               else ledgers.set(keyOf(r), releaseHold(L(keyOf(r)), R(r).units)),
    res' = res.set(r, { ...R(r), status: if (L(keyOf(r)).open) "released" else "retired", explicit: true }),
    eff' = eff, granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("release_reservation", r, -1, 0, ""),
  }

  // create_effect PP:1211: attempt open (attempt_open), effect id fresh, every listed
  // reservation proposed/unbound/owned by this effect (load_effect_reservations PP:3234),
  // then activate_reservations PP:3265: each ledger open and units <= available, moving
  // available -> held. Activation is sequential, so two reservations on one ledger must fit
  // together. Listing a subset of the owner's reservations is allowed; reservations on
  // different ledgers are allowed (reservation_dimensions PP:3498 checks only the dimension).
  action createEffect(e: str, ids: Set[str]): bool = all {
    not(attemptClosed), E(e).status == "absent", ids.size() > 0,
    ids.forall(r => R(r).status == "proposed" and R(r).owner == e and not(R(r).bound)),
    ids.forall(r => L(keyOf(r)).open),
    KEYS.forall(k => sumOver(ids.filter(r => keyOf(r) == k), r => R(r).units) <= L(k).avail),
    ledgers' = KEYS.mapBy(k => {
      val u = sumOver(ids.filter(r => keyOf(r) == k), r => R(r).units)
      { ...L(k), avail: L(k).avail - u, held: L(k).held + u } }),
    res' = RESV.mapBy(r => if (ids.contains(r)) { ...R(r), status: "reserved" } else R(r)),
    eff' = eff.set(e, { ...NOEFF, status: "pending", resIds: ids }),
    granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("create_effect", e, -1, 0, ""),
  }

  // claim_effect PP:1338: effect pending; ALL reservations owned by the effect are
  // "reserved" and unbound; each ledger open and current (PP:3133); binds them to the claim.
  action claimEffect(e: str): bool = all {
    E(e).status == "pending", resOf(e).size() > 0,
    resOf(e).forall(r => R(r).status == "reserved" and not(R(r).bound)),
    resOpenCurrent(resOf(e)),
    res' = RESV.mapBy(r => if (resOf(e).contains(r)) { ...R(r), bound: true } else R(r)),
    eff' = eff.set(e, { ...E(e), status: "claimed", hasClaim: true }),
    ledgers' = ledgers, granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("claim_effect", e, -1, 0, ""),
  }

  // issue_claim PP:1398: claim claimed, bound reservations all "reserved", open and current;
  // reservations -> issued_unknown, hold unchanged.
  action issueClaim(e: str): bool = all {
    E(e).status == "claimed", boundOf(e).size() > 0,
    boundOf(e).forall(r => R(r).status == "reserved"), resOpenCurrent(boundOf(e)),
    res' = RESV.mapBy(r => if (boundOf(e).contains(r)) { ...R(r), status: "issued_unknown" } else R(r)),
    eff' = eff.set(e, { ...E(e), status: "issued" }),
    ledgers' = ledgers, granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("issue_claim", e, -1, 0, ""),
  }

  // cancel_effect PP:1541 -> PP:1762 (pending, "unissued": release_many PP:1864 over ALL
  // owned reservations) and PP:1771 (claimed, "issuer_quiescent": over the claim's).
  // release_many fails the transaction unless every one is "reserved". PP:1746 (issued,
  // "control_ack") moves nothing and is omitted.
  action cancelEffect(e: str): bool = all {
    Set("pending", "claimed").contains(E(e).status),
    val rs = if (E(e).status == "pending") resOf(e) else boundOf(e)
    all {
      rs.forall(r => R(r).status == "reserved"),
      ledgers' = KEYS.mapBy(k => rs.filter(r => keyOf(r) == k)
        .fold(L(k), (l, r) => releaseHold(l, R(r).units))),
      res' = RESV.mapBy(r => if (rs.contains(r))
        { ...R(r), status: if (L(keyOf(r)).open) "released" else "retired" } else R(r)),
    },
    eff' = eff.set(e, { ...E(e), status: "cancelled" }),
    granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("cancel_effect", e, -1, 0, ""),
  }

  // settle_reservations PP:3910 / reservation_settlement PP:3932,3943: every claim
  // reservation must be issued_unknown or the transaction fails. succeeded/failed:
  // held -> consumed. non_started: release_hold (retired if the generation is closed).
  // "unknown" moves nothing (PP:3908).
  def settleOk(e: str): bool = boundOf(e).forall(r => R(r).status == "issued_unknown")
  def settleLedgers(e: str, o: str): LKey -> Ledger =
    if (o == "unknown") ledgers
    else KEYS.mapBy(k => boundOf(e).filter(r => keyOf(r) == k).fold(L(k), (l, r) =>
      if (o == "non_started") releaseHold(l, R(r).units)
      else { ...l, held: l.held - R(r).units, cons: l.cons + R(r).units }))
  def settleRes(e: str, o: str): str -> Res =
    if (o == "unknown") res
    else RESV.mapBy(r => if (boundOf(e).contains(r))
      { ...R(r), status: if (o != "non_started") "consumed" else if (L(keyOf(r)).open) "released" else "retired" }
      else R(r))

  // quarantine_conflicting_receipt PP:2001: claim/effect -> reconciliation_required; no
  // receipt stored, no units moved.
  action quarantine(e: str, why: str): bool = all {
    eff' = eff.set(e, { ...E(e), status: "reconciliation_required",
      qHeld: if (E(e).status == "reconciliation_required") E(e).qHeld
             else boundOf(e).forall(r => Set("reserved", "issued_unknown").contains(R(r).status)) }),
    ledgers' = ledgers, res' = res, granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("settle_claim", e, -1, 0, why),
  }

  action settleApply(e: str, o: str, how: str): bool = all {
    settleOk(e),
    ledgers' = settleLedgers(e, o), res' = settleRes(e, o),
    eff' = eff.set(e, { ...E(e), status: o, receipts: E(e).receipts.union(Set(o)) }),
    granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("settle_claim", e, -1, 0, how),
  }

  // settle_claim PP:1501 with a well-formed proof for the outcome (settlement_proof PP:3903).
  // `dup` = the receipt is an exact duplicate of a stored one. Branch order follows
  // settle_with_receipts PP:1885: exact duplicate; quarantined claim re-quarantines (the fix
  // at 69614867); unknown-only history + known outcome reconciles (reconciled_settlement
  // PP:1936); other history quarantines; no history -> first_settlement PP:1970 (claim must
  // be issued or unknown).
  action settle(e: str, o: str, dup: bool): bool = all {
    E(e).hasClaim,
    if (dup and E(e).receipts.contains(o)) all {
      ledgers' = ledgers, res' = res, eff' = eff, granted' = granted,
      attemptClosed' = attemptClosed, lastAction' = act("settle_claim", e, -1, 0, "exact duplicate"),
    } else if (E(e).status == "reconciliation_required") quarantine(e, "already quarantined")
    else if (E(e).receipts.size() > 0) {
      if (o != "unknown" and E(e).receipts == Set("unknown")) settleApply(e, o, "reconciled")
      else quarantine(e, "conflicting receipt")
    } else all {
      Set("issued", "unknown").contains(E(e).status),
      settleApply(e, o, "first"),
    }
  }

  // settle_claim PP:1501 whose receipt_id already belongs to another claim's receipt:
  // observation_conflict? PP:1595 is tested BEFORE any claim-status check, so a claim in
  // any status (including "claimed", never issued) is quarantined.
  action settleForeignReceipt(e: str): bool = all {
    E(e).hasClaim,
    EFFS.exists(x => x != e and E(x).receipts.size() > 0),
    quarantine(e, "receipt_id of another claim"),
  }

  // close_generation PP:1080: the named ledger is open; close_subtree over its subtree.
  action closeGeneration(n: str, g: int): bool = all {
    L((n, g)).exists, L((n, g)).open,
    val t = closeSubtree((n, g))
    all { ledgers' = t._1, res' = t._2, eff' = t._3 },
    granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("close_generation", n, g, 0, ""),
  }

  // reset_generation, root PP:1097: old open and current, units <= old.available, new
  // generation = old + 1 absent; close_subtree then a fresh root generation with `units`.
  // DISAGREE: the contract's transfer "decreases old authorized/retired"; the code leaves the
  // old generation's retired intact and grants the new generation fresh authority bounded by
  // the old available (transfer_kind "explicit_root_reset_unused_authority").
  action resetRoot(u: int): bool = all {
    L(("root", 0)).exists, L(("root", 0)).open, curGen("root") == 0, u <= L(("root", 0)).avail,
    not(L(("root", 1)).exists),
    val t = closeSubtree(("root", 0))
    val refund = if (SEEDED_BUG) L(("root", 0)).held else 0
    all {
      ledgers' = t._1.set(("root", 1), { ...NOLEDGER, exists: true, open: true, auth: u + refund, avail: u + refund }),
      res' = t._2, eff' = t._3,
    },
    granted' = granted, attemptClosed' = attemptClosed,
    lastAction' = act("reset_generation", "root", 1, u, ""),
  }

  // reset_generation, child PP:1150: old open and current, parent open, units <=
  // parent.available (checked before the close); close_subtree(old); parent available ->
  // delegated; fresh child generation under the SAME parent generation.
  action resetChild(n: str, u: int): bool = all {
    n != "root",
    val ok = (n, 0)
    val pk = (L(ok).parent, L(ok).pgen)
    all {
      L(ok).exists, L(ok).open, curGen(n) == 0, not(L((n, 1)).exists),
      L(pk).open, u <= L(pk).avail,
      val t = closeSubtree(ok)
      all {
        ledgers' = t._1
          .set(pk, { ...t._1.get(pk), avail: t._1.get(pk).avail - u, deleg: t._1.get(pk).deleg + u })
          .set((n, 1), { ...NOLEDGER, exists: true, parent: pk._1, pgen: pk._2, open: true, auth: u, avail: u }),
        res' = t._2, eff' = t._3,
      },
      lastAction' = act("reset_generation", n, 1, u, ""),
    },
    granted' = granted, attemptClosed' = attemptClosed,
  }

  // close_attempt PP:1559: every effect closed (@closed_effect_statuses PP:8) and every
  // activated reservation consumed/released/retired (PP:9). Moves no units.
  action closeAttempt: bool = all {
    not(attemptClosed),
    EFFS.forall(e => E(e).status == "absent" or Set("succeeded", "failed", "non_started", "cancelled").contains(E(e).status)),
    EFFS.forall(e => E(e).resIds.forall(r => Set("consumed", "released", "retired").contains(R(r).status))),
    attemptClosed' = true,
    ledgers' = ledgers, res' = res, eff' = eff, granted' = granted,
    lastAction' = act("close_attempt", "", -1, 0, ""),
  }

  // Each branch draws its own parameters, so one unlucky draw disables one branch, not the
  // step, and random traces run to --max-steps instead of dying early.
  action step = any {
    nondet g = GENS.oneOf()
    nondet u = UNITS.oneOf()
    grantRoot(g, u),
    nondet p = Set("root", "obj").oneOf()
    nondet g = GENS.oneOf()
    nondet g2 = GENS.oneOf()
    nondet u = UNITS.oneOf()
    delegate(p, g, g2, u),
    nondet n = Set("obj", "tkt").oneOf()
    nondet g = GENS.oneOf()
    nondet u = UNITS.oneOf()
    returnAlloc(n, g, u),
    nondet r = RESV.oneOf()
    nondet n = NODES.oneOf()
    nondet g = GENS.oneOf()
    nondet u = UNITS.oneOf()
    nondet e = EFFS.oneOf()
    reserve(r, n, g, u, e),
    nondet r = RESV.oneOf()
    releaseReservation(r),
    nondet e = EFFS.oneOf()
    nondet ids = RESV.powerset().oneOf()
    createEffect(e, ids),
    nondet e = EFFS.oneOf()
    claimEffect(e),
    nondet e = EFFS.oneOf()
    issueClaim(e),
    nondet e = EFFS.oneOf()
    cancelEffect(e),
    nondet e = EFFS.oneOf()
    nondet o = OUTCOMES.oneOf()
    nondet dup = Bool.oneOf()
    settle(e, o, dup),
    nondet e = EFFS.oneOf()
    settleForeignReceipt(e),
    nondet n = NODES.oneOf()
    nondet g = GENS.oneOf()
    closeGeneration(n, g),
    nondet u = UNITS.oneOf()
    resetRoot(u),
    nondet n = Set("obj", "tkt").oneOf()
    nondet u = UNITS.oneOf()
    resetChild(n, u),
    closeAttempt,
  }

  // ---------------- invariants ----------------

  // Contract: authorized = available + held + consumed + delegated + retired.
  val PerNodeConservation = KEYS.forall(k => not(L(k).exists) or
    L(k).auth == L(k).avail + L(k).held + L(k).cons + L(k).deleg + L(k).ret)

  val NoNegative = KEYS.forall(k => L(k).auth >= 0 and L(k).avail >= 0 and L(k).held >= 0 and
    L(k).cons >= 0 and L(k).deleg >= 0 and L(k).ret >= 0)

  // Contract: root authorized = sum of available+held+consumed+retired over its tree.
  val TreeConservation = GENS.forall(g => not(L(("root", g)).exists) or
    L(("root", g)).auth == sumOver(subtree(("root", g)), k => L(k).avail + L(k).held + L(k).cons + L(k).ret))

  // Code's restart check validate_ledger_tree PP:6072.
  val DelegatedMatchesChildren = KEYS.forall(k => not(L(k).exists) or
    L(k).deleg == sumOver(children(k), c => L(c).auth))

  // Code's restart check validate_reservations PP:6090: held and consumed equal the sums of
  // the live (reserved/issued_unknown) and consumed reservations on that ledger. Each
  // reservation names exactly one ledger, so every held unit is backed exactly once.
  val HeldBacked = KEYS.forall(k => not(L(k).exists) or all {
    L(k).held == sumOver(RESV.filter(r => keyOf(r) == k and Set("reserved", "issued_unknown").contains(R(r).status)), r => R(r).units),
    L(k).cons == sumOver(RESV.filter(r => keyOf(r) == k and R(r).status == "consumed"), r => R(r).units),
  })

  // No reset/return/close creates spendable or spent units beyond what grant_ledger issued.
  val NoUnitsCreated = sumOver(KEYS, k => L(k).avail + L(k).held + L(k).cons) <= granted

  // A closed generation never gains units: no availability, authority frozen at close.
  val ClosedNeverGains = KEYS.forall(k => not(L(k).exists) or L(k).open or
    (L(k).avail == 0 and L(k).auth == L(k).authAtClose))

  // Fix at 69614867: a claim quarantined while it held its units, with no known-outcome
  // receipt, keeps them held until an explicit recovery operation (FR-10).
  val QuarantineKeepsHeld = EFFS.forall(e => E(e).status != "reconciliation_required" or
    not(E(e).qHeld) or E(e).receipts.intersect(KNOWN).size() > 0 or
    boundOf(e).forall(r => Set("reserved", "issued_unknown").contains(R(r).status)))

  // A held reservation has a live owner that can still settle or cancel it.
  val HeldOwnerLive = RESV.forall(r =>
    (R(r).status != "reserved" or Set("pending", "claimed").contains(E(R(r).owner).status)) and
    (R(r).status != "issued_unknown" or Set("issued", "unknown", "reconciliation_required").contains(E(R(r).owner).status)))

  // The code's own restart check validate_reservation_transition_status PP:7519 /
  // validate_reservation_owner_status PP:7528 / reservation_statuses PP:7575-7610. A
  // committed state failing it makes the store refuse to open (database.ex:467 validate).
  def allowedStatuses(e: str): Set[str] = {
    val s = E(e).status
    if (s == "pending" or s == "claimed") Set("reserved")
    else if (s == "issued" or s == "unknown") Set("issued_unknown")
    else if (s == "reconciliation_required") {
      if (E(e).receipts.contains("succeeded") or E(e).receipts.contains("failed")) Set("consumed")
      else if (E(e).receipts.contains("non_started")) Set("released", "retired")
      else Set("issued_unknown")
    }
    else if (s == "succeeded" or s == "failed") Set("consumed")
    else if (s == "non_started" or s == "cancelled") Set("released", "retired")
    else Set()
  }
  def restartValidRes(r: str): bool = R(r).status == "absent" or
    (Set("released", "retired").contains(R(r).status) and R(r).explicit) or
    (if (E(R(r).owner).status == "absent") (R(r).status == "proposed" and not(R(r).bound))
     else (R(r).bound == E(R(r).owner).hasClaim and allowedStatuses(R(r).owner).contains(R(r).status)))
  val RestartValid = RESV.forall(r => restartValidRes(r))
  // The same check over reservations that have been activated (they carry units), so a
  // violation here is independent of the proposed-reservation finding.
  val RestartValidActivated = RESV.forall(r => R(r).status == "proposed" or restartValidRes(r))

  val Conservation = PerNodeConservation and NoNegative and TreeConservation and
    DelegatedMatchesChildren and HeldBacked and NoUnitsCreated and ClosedNeverGains
}
