# Checks and Gates

The discipline that keeps this stable across many sessions. Tasks reference this file
rather than restating it.

## Every task

Before marking a task complete:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
```

All four must pass. A task with failing tests is `in_progress`, not `completed`.

## Every phase gate (the ⛔ CHECKPOINT tasks)

A checkpoint is a real stop. Do not start the next phase until all of it passes.

### 1. Code
```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --cover            # coverage must not regress
mix credo --strict
mix dialyzer                # types; slow, so phase-gate only
mix deps.audit              # known CVEs in deps
mix hex.outdated            # note drift; upgrade deliberately
```

### 2. Architecture review
Re-read `CLAUDE.md`'s invariants and confirm the phase's code honors all seven.
Specifically audit:
- Does anything **in** `apps/pramana_web` read the DB directly — `Repo.`, `import
  Ecto.Query`, a handwritten query? (It must not: the web app is transport, the domain
  app owns the data.) This one has drifted once already, via an MCP resource that built
  its own aggregation.
- Did any domain logic leak into `priv/embed`? (It must not.)
- Can any tool return text without `urn` + offsets + `sha256`? (It must not.)
- Is any generated translation reachable as a top-level URN? (It must not.)
- Is the bake still reproducible from `sources.lock.json` alone?

Write findings into `docs/STATUS.md` under the phase heading. If an invariant was
violated, fix it before the gate passes — invariant drift is what makes long projects
collapse, and it is much cheaper to fix inside the phase that introduced it.

### 3. Data integrity (from Phase 1 on)

**Two checks, and they answer different questions.** Running only the first is how a
real defect survived a passing gate.

```bash
mix pramana.verify --all        # reproducibility: is the pipeline deterministic?
mix pramana.integrity           # fidelity: did the pipeline LOSE anything?
```

`verify` re-normalizes every text from `raw/` and byte-compares against the stored
body. That catches silent corruption — the highest-consequence bug class here.

`integrity` counts the bake against the **raw XML**: every `<lb/>` produced a line,
every line with printed content got a segment, every `<g/>` is reachable. This is the
check `verify` structurally cannot do, because **a pipeline that drops the same content
every run drops it identically on both sides of a re-normalization comparison**, and
the check passes. That is not hypothetical — 10,590 printed lines, 473 rare characters
and 266,547 characters of interlinear note text were unreachable in a corpus that
verified clean. **Reproducibility is not fidelity.**

Note `--sample N` on `verify` is **per text**, not a corpus-wide total. Use `--all` at
a gate; it takes ~2m30s for the full Taishō.

### 4. Evals (from Phase 4 on)
```bash
mix pramana.evals
```
Recall@k and citation accuracy must not regress against the previous gate. Record
the numbers in `docs/STATUS.md`.

### 5. Docs sync
- Does `docs/ROADMAP.md` still describe what we actually built? Amend if not.
- Do `ARCHITECTURE.md` / `LAYERS.md` / `TRANSLATION.md` match the implemented schema?
- Is `CLAUDE.md`'s layout section accurate?
- Update `docs/STATUS.md`: what's done, what's next, decisions taken, surprises found.

Docs drifting from code is the main way a future session gets misled. Treat a doc
correction as part of the work, not overhead.

### 6. Commit and tag
```bash
git add -A
git commit -m "phase N: <summary>"
git tag phase-N
```

## Periodic (every ~3 phases)

- `mix dialyzer` across the whole umbrella with no ignore file growth
- Dependency upgrade pass — deliberate, one PR-sized change
- Re-read `docs/COMPETITIVE.md`: has fojin shipped something that changes our
  positioning? Is our differentiation still real?
- Bake cost review: what does a full bake cost in time and tokens now?

## Security review

Run `/security-review` before any deployment task and at the Phase 7 gate. Specific
concerns for this project:
- Prompt injection via corpus text — canonical texts are trusted, but **locally-added
  sources and any OCR output are not**. Text from a manifest-added source must never
  be treated as instructions.
- The Python sidecar must not be reachable from outside the compose network.
- License gating must actually exclude `restricted` content from any public surface.

## What "stable" means here

The invariants in `CLAUDE.md` are the definition. Tests prove behavior; the checkpoint
architecture review proves the *shape* is still right. Both are required — a codebase
can be fully green and still have quietly stopped being the thing it was designed to
be.

## 6. Retrieval evals

```bash
PRAMANA_EMBEDDING=1 mix pramana.evals --gate
```

Scores the committed gold set in `evals/gold/` and fails if any case type has regressed
against `evals/baseline.json`. A ratchet, like the coverage threshold: a number that rises
is recorded as the new floor; one that falls fails the gate.

Three things to know before reading the output.

**Run it with the embedding serving.** Without `PRAMANA_EMBEDDING=1` the harness scores
the lexical path alone and says so. It is a real number for a smaller system, and it is
not the one the README publishes. The eval harness found this the hard way: `Hybrid`
silently skipped semantic retrieval for any caller that omitted `:serving`, and the first
run scored 0/40 on cross-lingual retrieval that works.

**Stale is not failure.** A case whose expected URN no longer resolves, or whose quoted
text has changed, is reported as `stale` and excluded from the rate. After a re-bake that
is the honest signal — *the gold set is out of date* — and counting it as a miss would
bury it in a number that went down.

**Regenerate the gold set after a re-bake**, with `mix pramana.evals.derive`, and re-read
the cases before committing them. The derivation is seeded, so it is reproducible.
