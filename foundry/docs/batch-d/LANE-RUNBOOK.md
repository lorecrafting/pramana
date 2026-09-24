# Manual lane runbook

For an LLM operator in a fresh session. The manual lane records a ticket's admission, one
claimed effect per work packet, the developer's candidate and an independent review, and
replays all of it after a restart. It launches nothing: you hand each packet to an agent
yourself. Design: [THIN-LANE-DESIGN](THIN-LANE-DESIGN-2026-09-23.md); risks A1–A6 and what
stays disabled: [DOGFOOD-READINESS §4](../DOGFOOD-READINESS-2026-09-23.md#4-the-thin-dogfood-option).

All commands run from `foundry/` in the main checkout. Every `bin/pramana lane …` command
prints one result; add `--json` for a single JSON object. A refusal prints `error: <atom>`
and exits non-zero.

## 1. Prerequisites

- Elixir/Erlang as pinned for Foundry, `python3` and `git` on `PATH`.
- Check no other `pramana_foundry` daemon is running: `pgrep -fl 'sname pramana_foundry'`.
  The lane uses its own node name and runtime root regardless.
- The lane daemon runs `ManualLane.Server` alone: no Coordinator, Improver, HardeningPM or
  agent launches. Never set `COORDINATOR_TICK`, `auto_approve` or a paid profile for it.

## 2. Start and stop

`bin/foundry-lane` sets the lane environment and drives the release. Defaults, each
overridable from the environment (`bin/foundry-lane env` prints them):

| Variable | Default | Meaning |
|---|---|---|
| `FOUNDRY_LANE_BUILD` | `/private/tmp/foundry-lane-build` | release build path, separate from `_build/prod` |
| `RELEASE_NODE` | `foundry_lane` | node name `bin/pramana lane` targets |
| `PRAMANA_RUNTIME_ROOT` | `~/.local/state/foundry-lane` | runtime root; the store is `state/manual-lane/authority.sqlite3` |
| `FOUNDRY_MANUAL_LANE_REPO` | the checkout holding `bin/` | repo `admit` resolves base refs in |
| `FOUNDRY_MANUAL_LANE_POLICY` | `docs/batch-d/lane-policy.example.json` | seed, read only while the store lacks the policy |
| `FOUNDRY_MANUAL_LANE_STORE` | unset | explicit store path, overriding the runtime-root default |

```sh
bin/foundry-lane build      # MIX_ENV=prod mix release into FOUNDRY_LANE_BUILD (after code changes)
bin/foundry-lane start      # starts the daemon, then prints `lane status`
bin/foundry-lane status     # node, pid and `lane status`
bin/foundry-lane stop       # clean stop; the next start comes up ready
```

`bin/pramana lane …` reads the same settings, so it needs no exports. Set any override on
`start` itself; every later command reaches the running node. The example seed grants 10
developer and 10 reviewer starts for the whole store; a store is seeded once.

## 3. One ticket, phase by phase

Ticket ids match `ML-[A-Za-z0-9-]+`. Take the base from git, never from memory.

**Admit.** `--acceptance` repeats; `--scope` is comma-separated.

```sh
bin/pramana lane admit ML-42 --base-ref "$(git rev-parse HEAD)" --title "Short title" \
  --scope foundry/lib/x.ex,foundry/test/x_test.exs --acceptance "criterion 1" --acceptance "criterion 2"
```

**Developer packet.** Writes the packet to `--out` and prints it.

```sh
bin/pramana lane packet ML-42 --role developer \
  --principal agent:claude-opus-5-5/dev-ML-42 --out /private/tmp/ML-42.dev.json
```

Hand it to a developer agent in its own worktree (`isolation: "worktree"`), with the packet
file as the brief. Tell it: start from the packet's `base_revision`, stay in `scope`, meet
`acceptance_criteria`, commit, and report the commit SHA and worktree path. Check the
worktree's base yourself: agents have started on the wrong base.

**Candidate and checkout.** The candidate is a commit whose ancestry contains the base, in a
checkout whose `HEAD` is that commit and whose tree is clean:

```sh
git -C <worktree> status --porcelain     # must be empty
git -C <worktree> rev-parse HEAD         # this is --candidate
```

**Submit.** `--principal` must be the developer packet's principal.

```sh
bin/pramana lane submit ML-42 --principal agent:claude-opus-5-5/dev-ML-42 \
  --candidate <sha> --checkout <worktree>
```

If the developer could not finish, add `--blocked "<reason>"`; the candidate and checkout
are still required. Otherwise the phase becomes `awaiting_review`.

**Reviewer packet.** A different principal, from a different model.

```sh
bin/pramana lane packet ML-42 --role reviewer \
  --principal agent:claude-fable-5-1/review-ML-42 --out /private/tmp/ML-42.review.json
```

Hand it to a fresh Fable agent, never a fork of the developer or of you. Give it the
packet, the candidate SHA and `git diff <base_revision> <candidate>`, and ask for a verdict
(`approved`, `correction` or `rejected`) and notes written to a file. Risk A4: nothing
checks the diff against `scope` except the reviewer, so ask it to.

**Review.**

```sh
bin/pramana lane review ML-42 --principal agent:claude-fable-5-1/review-ML-42 \
  --verdict approved --candidate <sha> --notes /private/tmp/ML-42.review.md
```

`approved` → `ready_to_integrate`; `correction` → `queued` for a new developer packet;
`rejected` → `rejected`.

**Settle** an issued packet that never ran or whose fate is unknown. The principal is the
packet's issuer.

```sh
bin/pramana lane settle ML-42 --role developer --principal agent:claude-opus-5-5/dev-ML-42 \
  --outcome non_started --attest "what you checked" --issuer-gone --channel-quiet
```

`non_started` needs both `--issuer-gone` and `--channel-quiet` (A1: attested, not proved).
`unknown` is permanent (A2): it holds its units, and the ticket is abandoned; admit a new id.

**Status and log.** Both write nothing to the store.

```sh
bin/pramana lane status [ML-42]    # phase, attempts, executions; awaits_operator marks issued claims
bin/pramana lane log [ML-42]       # committed events, refused commands, each effect's claim
```

## 4. Principals

Convention: developer `agent:claude-opus-5-5/dev-<ticket>`, reviewer
`agent:claude-fable-5-1/review-<ticket>`; a human is `human:<name>`. `--principal` never
defaults.

They must differ. The seeded policy makes the reviewer independent of the developer role,
so Core refuses a reviewer packet whose principal issued a developer effect on the attempt
(`principal_not_independent`). Only the issuer of an effect may submit, review or settle
it. Until FR-15aB, principals are recorded, not proved isolated (A3): the independence is
only as real as your choice of a fresh agent on a different model.

## 5. Refusals

| Refusal | Meaning | Do |
|---|---|---|
| `principal_required`, `option_required` | a required flag is missing | add it |
| `principal_not_independent` | the reviewer principal issued a developer effect of this attempt | use a fresh reviewer principal |
| `wrong_source_phase` | the command does not fit the ticket's phase (a reviewer packet before submit, say) | `lane status`, then run the phase's command |
| `candidate_mismatch` | `review --candidate` is not the submitted candidate | pass the SHA from `lane status` |
| `git_evidence` | checkout dirty, `HEAD` is not the candidate, or the base is not an ancestor | commit or clean the worktree |
| `git_ref_unresolved` | `admit --base-ref` does not resolve in the configured repo | fix the ref, or `FOUNDRY_MANUAL_LANE_REPO` |
| `receipt_mismatch` | a rerun attests something other than the stored receipt | the first answer stands; read it with `lane log` |
| `review_already_recorded` | a different review is already committed for this attempt | none; admit a new ticket if it was wrong |
| `revision_conflict` | the store moved between the command's read and its write | rerun the same command; committed steps replay |
| `execution_owned_by_other_principal` | another principal already holds this role's open packet | use that principal, or settle its packet |
| `receipt_provenance_mismatch` | submit, review or settle by a principal that did not issue the effect | use the packet's principal |
| `lane_disabled` | no lane server on the node | `bin/foundry-lane start` |
| `gateway_recovery` | the previous daemon stopped uncleanly; the store is fenced | see below |

**Idempotency.** Every command replays what is already committed. Rerunning `packet`
returns the same packet (no second effect); rerunning `submit` or `review` with the same
arguments returns the stored result. Rerun freely after a timeout or a crash. A rerun
`review` that differs only in `--notes` also returns the stored result and keeps the first
notes digest.

**`gateway_recovery`.** After a crash or kill, every command reports it, with the reason
and the next step. Confirm that no other lane process owns the store
(`pgrep -fl 'sname foundry_lane'` shows one node, the one you just started), then:

```sh
bin/pramana lane recover --evidence "killed pid N at HH:MM; one foundry_lane node running"
bin/pramana lane status
```

Write what you checked; the lane prefixes `operator_attestation: ` itself. The evidence is
archived with the old owner marker. Packets issued before the crash keep their old writer
epoch; `submit` and `settle` still work on them.

## 6. Logs

- `lane log [ID]` reads the store: the authoritative trail, including refused commands.
- `<runtime root>/state/manual-lane/operator.log.jsonl`: one line per lane command (argv,
  result, principal, duration). Observation only; nothing reads it back.
- Daemon console: `$FOUNDRY_LANE_BUILD/rel/pramana_foundry/tmp/log/erlang.log.*`.

## 7. Out of scope

- **Integration** is manual git outside Foundry (A5). The lane ends at `ready_to_integrate`;
  merge or cherry-pick the candidate yourself. Nothing records `integrated`.
- Checks: the policy's check set is empty; record the checks you ran in the review notes.
- Legacy commands (`ticket …`, `handoff …`) do not work against the lane node.
