# FR-06 R4a focused independent review

2026-09-12. Reviewer: a fresh delegated Codex review agent, separate from the
correction author. Scope: revision 3's launch-non-start correction and its necessary
R1/R5 and global-control interactions. This is not a repeat architecture audit.

## Verdict

**PASS — R4a is resolved at design level.** The manifested correction supplies the
missing developer/reviewer domain recovery transitions without charging a confirmed
process start that never occurred. No unresolved design blocker was found in this
focused scope. The v2 review's design dispositions for R1/R2/R3/R5 remain applicable;
this correction exposes no concrete contradiction requiring them to reopen.

The focused FR-06 design-review condition is satisfied. This does not complete FR-03
or authorize starting FR-07 in this session. FR-07 still requires its existing FR-03
prerequisite and the implementation gates remain binding. Existing status documents
were deliberately not edited; this new review records the independent disposition.

## Reasoning and challenged boundaries

References below are to the exact working-tree bytes recorded in the input inventory.

| Challenge | Independent disposition |
|---|---|
| Developer ownership | Contract R4a, line 394, retains one nonterminal attempt with immutable lineage, returns the ticket to queued and closes only the failed execution. The ordinary dispatch row at line 431 explicitly reuses that retained attempt. Checkout/conflict leases release only with the specified non-exposure/non-mutation proof and require reacquisition/revalidation. An infrastructure limit blocks that attempt; allocation exhaustion terminates it. No synthetic crash or successful result is needed. |
| Reviewer ownership | R4a, line 395, together with the ordinary reviewer-dispatch row, returns the reviewing attempt/ticket to awaiting_review with the same frozen candidate, check receipts and reviewer role. Only the failed reviewer execution closes. Neither developer retry nor approval follows from non-start. Infrastructure blocking preserves the candidate; policy-selected budget exhaustion does not reopen a terminal attempt on reset. |
| Finite retry bound | Lines 383–390 and 410–415 require a finite protected-policy allowance and a durable ordinal per role/work owner. Each proved non-start increments once; redispatch needs remaining allowance. Returning a refunded start unit therefore cannot create an unlimited non-start loop. Resume, restart, profile changes and fresh execution IDs cannot reset the ordinal. At the limit, ordinary resume alone cannot authorize another launch; an explicit policy change/new infrastructure generation is required. |
| Refunds and conservation | Non-start settlement closes the execution, settles its original reservation and changes domain/ordinal state in one transaction. R5 releases held units only once and preserves separately charged requests/validation. A confirmed start remains consumed; an unknown start remains held. The infrastructure ordinal is separate from the fungible start ledger, so incrementing it neither mints nor consumes start credit. For a closed generation, held→retired preserves R5's equation and provides no new-generation availability. Duplicate settlement changes neither balance nor ordinal; conflicting evidence remains subject to R5 quarantine. |
| Waiting versus unknown start | Pre-intent denial creates no execution, reservation or infrastructure charge. After issue, absence of proof produces unknown, retaining holds, slot and conflicting leases. A missing pane, expired deadline, new epoch or local issuer termination alone cannot establish non-delivery. R1's quiescence and attributable-outcome requirements still govern release and successor eligibility. |
| PM and other roles | PM keeps the same planning owner, yields no proposal/admission and creates no grant. The explicit check/import/build/integration/activation row preserves each phase's verified inputs and invokes its existing infrastructure retry/block handling, with the same finite allowance and predecessor requirement. It cannot manufacture check, ref or release success. Phase-specific R1 effects and R5 operation/start dimensions remain binding. |
| Pause, drain and cancel | Receipt/refund processing survives controls. Pause prevents productive issue; drain blocks developer/PM replacements while allowing the already-admitted work permitted by the global drain rule. Cancel never retries. R4a's cancellation summary must be read with R4's explicit finalization guard: all owned sessions, non-session claims and cleanup reconcile before final cancellation. A settled launch claim alone does not prove a running descendant has stopped. |
| Generation and authority changes | Retry eligibility is rechecked against current control, policy, resources and permitted ledger generation, despite retaining immutable attempt lineage. Old receipts settle old reservations, never newer execution authority. Explicit infrastructure-generation changes retain predecessor history; a budget reset or new execution ID does not implicitly reset infrastructure allowance. |
| Restart before redispatch | Atomic non-start/domain/ordinal/reservation settlement yields either the prior unresolved state or the complete settled state, never an acknowledged partial bundle. Boot still reconciles under R1 before scheduling. Once settlement is committed, replay reconstructs one queued/review/blocked owner and no live failed execution; only a fresh successor referencing the terminal predecessor may be claimed. Replayed receipts neither redeliver the old effect nor increment/refund again. |

These are protocol case analyses, not executed state-machine or ledger tests. In
particular, the general R1 quiescence requirement and R5 closed-generation settlement
rule constrain R4a's shorter references to proof and refunds; they are not exceptions
introduced by the correction.

## Acceptance routing and remaining evidence

The FR-08 addition covers exact role transitions, controls/generations and restart
reconstruction. FR-10 covers proof, atomic settlement, duplicate/late observations,
unknown holds and predecessor effects. FR-11 retains the original failed-reviewer-launch
acceptance and adds candidate/attempt ownership, finite limits and budget outcomes.
FR-12 covers pre-intent waiting, current redispatch eligibility, controls and leases.
Their original Acceptance paragraphs and v2 refinements remain present and binding.
In particular, successful-developer cleanup, independent review and capacity-one
progress are not replaced by the new non-start cases.

An independent read-only routing check found 23 ticket nodes, no unknown dependency or
cycle, and FR-22 transitively reaching all other tickets, including FR-15a. F01–F24
each occur exactly once in the obligation matrix, and every ticket has its Acceptance
paragraph. Semantic inspection confirms the relevant F07–F11 and F14–F16 obligations
are strengthened by the correction, while the matrix continues to route all remaining
audit obligations. The original product/authority contract and the supersession table
still require the original acceptance evidence. This is not a fresh byte-for-byte
reconstruction of the historical author's preservation checks or a re-audit of all
24 implementation findings.

Deferred implementation evidence remains material: FR-07/08 must prove actual protected
multi-row atomicity, constraints, conserved ledgers and deterministic replay; FR-10/11/12
must exercise the non-start, limit, control, generation and restart interleavings with
owned fake backends. FR-09 must establish what installed OMP can actually prove; absent
proof, its result is unknown. FR-15a still owns host/process/channel enforcement, and
FR-22 owns end-to-end acceptance. No implementation finding is closed here.

Two nonblocking suggestions for schema/document precision:

- Render the reviewer row as `reviewing → awaiting_review` instead of “Keep ...
  awaiting_review.” The adjacent dispatch row, v3 response and acceptance traces
  already establish the intended transition, so this is wording rather than a missing
  normative outcome.
- In FR-08's concrete schema, enumerate the immutable `work_owner` key for each role
  and bind the infrastructure generation explicitly. Include tests that a new execution
  ID, check-run ID or resumption cannot become a fresh owner to evade the same work's
  limit. This implements the existing per-owner/no-reset requirement rather than adding
  a new policy decision.

## Exact inputs and verification

HEAD: `a3fa302342238ae3d5a133b35bd86f4fa4f13710`.
The supplied manifest SHA-256 matched before substantive review:
`27e8315697ad84db96dfbcf985f2055014b3065c91561c5c6cba7067d307dd38`.
Every one of its 15 entries matched. The reviewed inventory is:

```text
AGENTS.md 56b2b70ae8f1c415cb057c3785eea42dfa0b949b1a9b2ae88155fb5471982c87
docs/STATUS.md a37c2b3411e223b060ecf733fbf9c55feb5064eead7ea7fdb81c2494973f2815
docs/PLAN.md 07baddf88344d4211fc76c0273dab73e2db564cbfe19ae04385648da4ce7f957
docs/ROADMAP.md abe413c758cc58b1f6cb573d2b2a5a3877f979bb33f7e9fbebf9064046b9bac5
docs/RULES.md 45057c7ff3f412372290f4df58e4ab350a52500dde46f070ccdcd49e2286e1f5
foundry/docs/WORKFLOW-CONTRACT.md e1381b5250b1c811ebcea2479cf63f6d9eec0d12e1035f8ef266da3c2472a6e9
foundry/docs/REPAIR-PLAN.md db1c1112852b12baadd6e3cbec77779a6e431b3e023aabfdac210a74ffafae9f
foundry/docs/FR-06-DESIGN-REVIEW.md d953b960c0fd1b746290764adff46dddbafd85d8cb852c24fa78142cff247134
foundry/docs/FR-06-DESIGN-REVIEW-V2.md 0e1bf28a46990fde561e90e52138e126894e896b365a590f4be7dffeaec7793a
foundry/docs/AUDIT-2026-09-12.md 3cd1818a5d57f1b58092166dd3396d2ae17455157bf8844f2bcfa02cf441121a
foundry/docs/fr-06/review-response-v2.md 426da04cf0e04f44192a4357e867fba1ac5f6668a44a8f37a9f4b1e1638fc179
foundry/docs/fr-06/review-response-v3.md 5f099b8766ece50364afcca9406309b5fa14414e4c0711ddbdc616c904046b56
foundry/docs/fr-06/verification.md 256b305fda5777059bb88fd5b0f565f51c0ad2874571eb679d79fc19c8e0d900
foundry/docs/fr-06/storage_spike.py 65da1683f1256d9ce623a75693b0f185454b2387c3d519a09a85e6dfda97d5eb
foundry/docs/fr-06/storage-results.json d6ae141fa56d7ceb649b63033de23ee4a3973672d76c76208cf81266a98a01ce
```

Commands: `git status --short`, `git rev-parse HEAD`, `shasum -a 256`, Ruby
JSON/Digest comparison of every manifest entry, bounded `sed`/`nl`/`rg` reads and
Ruby dependency/acceptance-table checks. Manifest and routing checks exited 0.
An initially truncated full-contract read was supplemented with focused R1/R4a/R4/R5
reads. Inputs read included both complete historical reviews, both responses,
verification, required ticket sections and the audit's operating contract and
F07–F11/F14–F16. Orientation reads were bounded to relevant project context/rules;
storage files were hash-verified only. Their experiment was not rerun.

Baseline already contained modified PLAN/README/CLI/Coordinator files and untracked
audit/design/evidence/review artifacts. This review creates only this new file. It does
not edit existing inputs, refresh the manifest, stage or commit. No production source
audit, daemon access, credentials, provisioning, model execution, runtime probe, suite,
storage experiment, integration or activation occurred.
