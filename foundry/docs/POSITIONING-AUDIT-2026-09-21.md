# Independent positioning-documentation audit — PRs #43–#46

Audited revision: `d3e37183e4ff6b39b9a8c5f61e1e91a90bc6d175`.
Tree: `8939639bad5b19a8730aea484ccdcc77577844a1`.
Range: `6a33aca3..origin/main` — 14 files, ~3,694 insertions.
Prepared 2026-09-21, Pacific/Honolulu, by a fresh independent Fable session. This is a
read-only audit. It changes no backlog, contract, runtime, policy, credential, Git ref,
deployment or activation permission. Only this report is written; the edits it proposes are
not applied here.

The four merged pull requests:

| PR | Merge commit | Branch |
|---|---|---|
| #43 | `93c640c5` | `docs/replaceable-planning-projections-2026-09-20` |
| #44 | `079ac53c` | `docs/foundry-ecosystem-positioning` |
| #45 | `f1368d10` | `docs/ax-substrate-execution-backend` |
| #46 | `d3e37183` | `docs/foundry-orchestrator-authority-boundary` |

## Why this document exists

An audit of these same four PRs was run in an earlier session and returned, by the handoff
note's account, a nine-row table and eight minimum edits. **Those findings were never written
to the repository and are lost.** The ask was carried across sessions as "nothing has been
landed" while the thing to land existed only in a session's context, so it could not be acted
on.

This audit is a **re-derivation, not a reproduction**. It finds fourteen rows and eleven
edits. No attempt was made to match the earlier counts, and the difference should not be read
as either audit being wrong — the earlier findings cannot be compared because they do not
exist. That is the point of committing this one.

## What an unowned obligation means here

These are positioning and strategy documents. They make claims about what the system does,
will do, guarantees or refuses. An **unowned obligation** is a claim committing the project to
behaviour with no identified owner in the plan, no FR node, no ticket and no implementation —
a promise the repository has no mechanism to keep or to notice breaking.

The FR namespace is closed at FR-23 by operator direction, so an obligation with no home is a
real finding rather than a bookkeeping gap. Roadmap IDs are not tickets, which is why several
rows below route to `ROADMAP.md` rather than to a new FR node.

Four categories, because they need different fixes:

- **Contradicts** — conflicts with a documented invariant or an existing guarantee. Highest
  severity.
- **Unowned** — no owner, should have one.
- **Unownable as written** — too vague to assign; needs rewording before it can be owned.
- **Already owned** — looks unowned but an FR node or existing document covers it. Recorded
  so it is not re-raised by the next audit.

## 1. Obligations

Ordered by severity.

| # | Claim | Category | Severity and reason | Owner it should have / why none |
|---|---|---|---|---|
| 1 | `foundry/docs/OBSERVABILITY.md:330` — "The durable correlation chain should support: `project/workflow revision → objective → ticket/work item → attempt → assignment → execution → …`" | **Contradicts** | **High.** The same document states the canonical chain at `:184` as `objective_id → ticket_id → attempt_id → execution_id → …`. `OBSERVABILITY.md` is FR-18B's route document (`REPAIR-PLAN.md:1249-1254`) and FR-18A owns the identity vocabulary (`:1206-1208`). `project`, `workflow revision` and `assignment` are not identities in the contract's table (`WORKFLOW-CONTRACT.md:228-240`). An FR-18B implementer now has two chains to satisfy, one naming undefined identities. The same chain and envelope appear in `ORCHESTRATOR-BOUNDARY.md:534-577`, but that document is correctly labelled post-repair. | FR-18A if the operator wants the outer nodes in the repair; otherwise post-repair O2, and the line must say so. |
| 2 | `foundry/docs/OBSERVABILITY.md:332-337` — "Every orchestrator observation should also preserve … controller kind/version, adapter version, controller job/session ID … wake reason and whether the wake exposed actionable new state." | **Unowned** | **High.** New observation-schema fields written into FR-18B's route document; FR-18B's acceptance (`REPAIR-PLAN.md:1217-1254`) contains none of them. `ORCHESTRATOR-BOUNDARY.md:935-939` (O2) assigns the same fields to a post-repair step, so a second document now depends on them landing somewhere. | Post-repair O2 (itself unowned, row 6), or FR-18B by explicit operator addition. Not FR-18B today. |
| 3 | `foundry/docs/STRATEGY.md:89-91` — "The preferred distribution is **Foundry Core + an optional bundled Standard Controller**"; `ORCHESTRATOR-BOUNDARY.md:701-722`, `:780-782` "factor software-specific scheduling, role selection and correction logic out of protected authority into the Standard Controller." | **Unowned** | **High.** A product-shape commitment plus a refactor of the protected kernel. FR-23 excludes behavioural change and "does not relitigate settled design" (`REPAIR-PLAN.md:1512-1516`); FR-22 reconciles documents, it does not refactor. FR namespace closed. `ROADMAP.md` owns post-repair initiatives (`:6-18`) and was untouched by all four PRs. Three documents now state it as the target. | A `ROADMAP.md` I-F entry — roadmap IDs are not tickets, so the closed FR namespace does not block one — or reword to hypothesis. |
| 4 | Three experiment ladders: `ORCHESTRATOR-BOUNDARY.md:918-958` O0–O4; `AX-SUBSTRATE.md:450-499` A0–A4; `CLOUDFLARE-OS.md:809-850` C0–C3. Plus `STRATEGY.md:99` and `ORCHESTRATOR-BOUNDARY.md:784-787`. | **Unowned** | **Medium.** Each ladder says it creates no repair dependency, which is honest, but none is registered in `ROADMAP.md`. The documents now carry four "first" claims — Cloudflare first controller, AX first distributed backend (`AX-SUBSTRATE.md:65-66`), Restate before durable machinery (`ECOSYSTEM-BOUNDARY.md:312-314`) and the pre-existing I-F1 (`FOUNDRY.md:327`) — under `FOUNDRY.md:443`'s "one bounded Foundry improvement alongside". ROADMAP I-F3 (`:182-208`) already defines the portability sequence as software-on-another-repo then Loka; this is neither. | `ROADMAP.md`: one entry or umbrella naming O/A/C, depending on G0 and I-F3's software baseline. |
| 5 | `docs/strategy/FOUNDRY.md:143-144` — "Event subscriptions should let deterministic controller code wait without repeatedly waking a model to poll child status."; `ORCHESTRATOR-BOUNDARY.md:376-394`; conformance item 13 (`:871`). | **Unowned** | **Medium.** No subscription mechanism exists — `grep -rE 'subscribe\(|PubSub|Registry\.dispatch' foundry/lib` returns 0 hits. The contract's local boundary (`WORKFLOW-CONTRACT.md:210-219`) defines a command socket and read-only status only; no FR owns push. The strategy chapter states it as design, not as a post-repair candidate. | Post-repair O1/O2 (row 4). |
| 6 | `foundry/docs/OBSERVABILITY.md:197-202` — "Measure **reorientation tax** …"; `PLANNING-STRATEGIES.md:355-356`. `VALIDATION.md:55-62` depends on the same dimensions. | **Unowned** | **Medium.** Imperative in FR-18B's route document. FR-18B's measurement refinement (`REPAIR-PLAN.md:1236-1248`) covers usage, context, retries/compaction and human effort — not handoff-to-first-effect latency, repeated reads or stale-context failures. | ROADMAP I-F1 (`:164-170`, "context-reset/restart cases … matched-task effort comparison") is the natural home. Post-repair. |
| 7 | `foundry/docs/CLOUDFLARE-OS.md:564-565` — "Do **not** add this to the protected ontology during the current repair … But preserve a future seam capable of carrying something like: `ObservationReceipt {…}`"; echoed at `docs/strategy/FOUNDRY.md:103-109`. | **Unownable as written** | **Medium-low.** "Preserve a future seam" is an obligation on current schema and identity work (FR-07 schema, FR-18A vocabulary) that nobody can verify was met or broken. | Either name the concrete fields and assign to FR-18A, or delete the clause and keep the C0 decision item (`CLOUDFLARE-OS.md:819-820`), which is the honest form. |
| 8 | `foundry/docs/OBSERVABILITY.md:21-23` — "[Orchestrator boundary] makes one distinction mandatory …"; `:45-46`. | **Already owned** (wrong citation) | **Low.** The separation is already true and owned: command transaction protocol (`WORKFLOW-CONTRACT.md:251-299`, FR-06/FR-08) versus telemetry surfaces (FR-18). The problem is only that a post-repair document is cited as the source of a mandate on an active route document. | FR-06/FR-08 + FR-18. Cite the contract, not ORCH. |
| 9 | `foundry/docs/ORCHESTRATOR-BOUNDARY.md:104` — "A deployment should distinguish at least three governance modes: NATIVE / GOVERNED / ESCALATING"; `:136-157`. | **Unownable as written** | **Low.** "A deployment" has no subject in this repository; the modes are Cloudflare-product design. FR-15's admission path (`REPAIR-PLAN.md:1126-1146`) has no source-provenance input and nothing here asks for one. | None needed once reworded as a Cloudflare-side property under O3. |
| 10 | `foundry/docs/STRATEGY.md:50-51` introduces `ExecutionBackend`/`ResourceAdapter`; `STRATEGY.md:471` still names the same seam "`Foundry.ExecutionSandbox` conformance suite"; `ECOSYSTEM-BOUNDARY.md:112-119` lists seven contract names without it. Neither name exists in `foundry/lib`. | **Contradicts** (naming) | **Low.** A reader cannot tell whether these are one seam or two. | One clause at `STRATEGY.md:471`. |
| 11 | `foundry/docs/STRATEGY.md:76` — "The CLI **is** an operator client of those semantics, not the required controller integration mechanism." | **Contradicts** (tense) | **Low.** Today the CLI is the only client — FR-02 inert RPC transport, "temporary containment, replaced by FR-15a's scoped protocol" (`WORKFLOW-CONTRACT.md:218-219`). `ORCHESTRATOR-BOUNDARY.md:28-29` correctly says "should be". | FR-15a owns the socket protocol the claim presupposes. |
| 12 | `foundry/docs/ORCHESTRATOR-BOUNDARY.md:271-276` — "The primary integration surface should be a small versioned machine API …" | **Already owned** | **None.** `WORKFLOW-CONTRACT.md:212-219` requires exactly this and assigns it to FR-15a. Recorded so it is not re-raised. | FR-15a. |
| 13 | `foundry/docs/ECOSYSTEM-BOUNDARY.md:312-314`; `STRATEGY.md:57-58`. | **Already owned** | **None.** `ROADMAP.md:14-18` "compose before build" and `FOUNDRY.md:161-176` own the rule; `RESEARCH.md` dependency-policy rows E39–E42 register the candidates. | ROADMAP / RESEARCH. |
| 14 | `foundry/docs/ECOSYSTEM-BOUNDARY.md:223-224` cites Cloudflare OS at `baa4f7cc…`; `CLOUDFLARE-OS.md:14-21` and `RESEARCH.md` E41 pin `b09c64cb…`. | Stale cross-reference, not an obligation | **Low.** | One-line fix. |

**Clean findings, with their denominators.** `PLANNING-STRATEGIES.md` (384 of 384 lines read):
no unowned obligations. Its §11 maps steps 1–3 to FR-15/FR-18/FR-22 and labels 4–5
post-repair; the rest is "should"/"may" and says so at `:33-36`. `PROJECT-WORKFLOW-PROFILES.md`
§1.1 (all 45 added lines read; the other ~620 lines not read): hedged by the header, nothing
unowned. `AX-SUBSTRATE.md` (529 of 529): nothing beyond row 4, and its "What this does not
authorize" list is the model the other documents should copy.

## 2. Minimum edits

Not applied. Eleven edits; E4 is the only addition longer than a sentence, and it is the one
that gives rows 3–5 a home the closed FR namespace cannot.

| Edit | File and change | Answers |
|---|---|---|
| E1 | `foundry/docs/OBSERVABILITY.md:330` — add after the chain: "Only the `objective → … → accepted outcome` subset in *Canonical correlation model* is FR-18A/18B scope; `project`, `workflow revision` and `assignment` are post-repair vocabulary from the orchestrator boundary, not workflow-contract identities." | 1 |
| E2 | `foundry/docs/OBSERVABILITY.md:332-337` — prefix the paragraph with "**Post-repair (O2):**". At `:21` replace "makes one distinction mandatory" with "restates a distinction the workflow contract already makes mandatory (command transaction protocol versus telemetry surfaces)". | 2, 8 |
| E3 | `foundry/docs/OBSERVABILITY.md:197` — "Measure **reorientation tax**" → "I-F1 may measure **reorientation tax**". `docs/strategy/ROADMAP.md:167-168` I-F1 evidence line: append ", reorientation-tax measures per OBSERVABILITY". | 6 |
| E4 | `docs/strategy/ROADMAP.md` — add after I-F4: **I-F5 — Core/Standard Controller split and substitution experiments.** Outcome: the O0–O4, A0–A4 and C0–C3 ladders run one at a time under FOUNDRY's "one bounded improvement" rule. Dependencies: G0, I-F3 software baseline. Excludes: refactoring protected authority before FR-22; more than one ladder active. | 3, 4, 5 |
| E5 | `foundry/docs/STRATEGY.md:89` — "The preferred distribution is" → "The candidate post-repair distribution (ROADMAP I-F5) is". `:99` — "should be the first materially different external-controller experiment" → "is the preferred first external-controller experiment, sequenced under I-F3/I-F5". | 3, 4 |
| E6 | `docs/strategy/FOUNDRY.md:143` — "Event subscriptions should let" → "A post-repair subscription surface (I-F5, O1/O2) would let". | 5 |
| E7 | `foundry/docs/CLOUDFLARE-OS.md:564-565` — delete "But preserve a future seam capable of carrying something like:" and replace with "A later C0 decision may introduce something like:". No change to `FOUNDRY.md:103-109`, already "future". | 7 |
| E8 | `foundry/docs/ORCHESTRATOR-BOUNDARY.md:104` — "A deployment should distinguish" → "A Cloudflare-side deployment would distinguish". | 9 |
| E9 | `foundry/docs/STRATEGY.md:471` — "`Foundry.ExecutionSandbox` conformance suite" → "`ExecutionBackend` conformance suite (earlier named `Foundry.ExecutionSandbox`)". | 10 |
| E10 | `foundry/docs/STRATEGY.md:76` — "The CLI is an operator client" → "The CLI should become an operator client (FR-15a owns the socket protocol this presupposes)". | 11 |
| E11 | `foundry/docs/ECOSYSTEM-BOUNDARY.md:223-224` — replace `baa4f7cc4ab628c5d157c68054b315695de02fa1` with `b09c64cb66c13eb106f5f825e8c5f71636f09eb8`. | 14 |

Rows 12 and 13 need no edit.

## 3. Coverage, and what was not read

Read in full: `ORCHESTRATOR-BOUNDARY.md` (986), `CLOUDFLARE-OS.md` (903),
`ECOSYSTEM-BOUNDARY.md` (610), `AX-SUBSTRATE.md` (529), `PLANNING-STRATEGIES.md` (384); every
added line of the nine edited files via `git diff 6a33aca3..origin/main`.

Read for context: `OBSERVABILITY.md` 1–15, 170–200, 300–345; `STRATEGY.md` 470–500;
`docs/strategy/FOUNDRY.md` 1–60, 320–385, 421–470; `ROADMAP.md` 1–70, 150–215.

Ownership sources: `REPAIR-PLAN.md` 1–120 and FR-15, FR-18A/B (1204–1260), FR-20, FR-21,
FR-22, FR-23; `WORKFLOW-CONTRACT.md` 158–300. Greps over `foundry/lib` for the seven contract
names, `ExecutionSandbox`, subscription/pubsub and sockets.

**Not read**, so no claim of absence covers them: `OBSERVABILITY.md` ~400 remaining lines;
`STRATEGY.md` ~600 remaining; `FOUNDRY.md` 60–320 outside the hunks;
`PROJECT-WORKFLOW-PROFILES.md` outside the hunks; `RESEARCH.md` and `VALIDATION.md` outside
the hunks; `WORKFLOW-CONTRACT.md` 1–157 and 300–700; `REPAIR-PLAN.md` 120–1126 and the
completion log; `foundry/lib` beyond the greps; `docs/PLAN.md`.

## 4. Suspected, not confirmed

Recorded rather than dropped, so the next pass starts here instead of rediscovering them.

- `ORCHESTRATOR-BOUNDARY.md:433-452` lets a controller spawn helpers "inside one admitted
  execution" sharing one budget ceiling; R5 requires a reservation per actual model request
  (`WORKFLOW-CONTRACT.md:180-181`). Possible conflict if helpers make model calls. R5
  (`:529-613`) was not read.
- `ORCHESTRATOR-BOUNDARY.md:416-431` `ExecutionGrant` fields likely duplicate FR-06 token
  semantics (`WORKFLOW-CONTRACT.md:213-215`); probably already owned, not field-checked
  against R1/R4.
- The three conformance lists — ORCH 15 items, AX 17, CF 17, **49 test obligations** — have no
  test owner. Folded into row 4 rather than listed individually.
- The F01–F24 obligation table was not cross-checked against the new documents.
- `PROJECT-WORKFLOW-PROFILES.md` §1.1 claims one admitted workflow can be exercised by
  multiple controllers "without changing the acceptance criteria"; VALIDATION's portability
  falsification cases were not read to see whether controller substitution is among them.
