# Project history — chapter 5

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## Three from the landscape list, and a defect they found — 2026-09-02

**Translator fingerprinting**, which Phase 6 recorded as "ahead of its data", now has it.
`Translators.attested/3` joins two of Karashima's glossaries on the Sanskrit headword:
Kumārajīva and Dharmarakṣa on the same sūtra, **601 shared headwords, 126 agreed, 475
diverged** — `adhimāna-prāpta` as 增上慢 against 貢高, `agra-bodhi` as 道心 against 佛道.
Attested by a philologist rather than inferred from n-gram rates, and reachable through
the new `compare_translators` tool: `Pramana.Translators` had no surface at all, which was
rule 60 sitting in the codebase unnoticed.

**L4**, `Pramana.Citation`. The payoff was not convenience. `Guard` scans prose for
`pramana:` URNs, so a report citing the Taishō the way every article cites it contained no
citations, the checker reported **zero checked**, and `/check` rendered that as a clean
document. Two grammars implemented, both read off data already held; fojin's scheme
deliberately left out because what its locator addresses is documented nowhere checkable.

**L3**, `Pramana.Repair`. Four states from fojin's vocabulary and a fifth, `flagged`, for
the two cases where repair needs a judgement rather than a substitution. Every correction
is a substitution of something the corpus already said; an ambiguous quotation refuses
rather than picking one of three.

**And L3's first run found a defect in the guard.** A URN closing a sentence kept the full
stop and resolved to nothing, so the guard reported `:not_found` for a good citation — a
false accusation, in prose, which is where citations live. `evals/` was blind to it
because its 601 gold quote cases are constructed rather than written as sentences. Fixing
it then produced a second bug in the same commit: trimming in `extract_urns/1` and not in
the quote-pairing map made every paired quotation miss its key and silently downgrade to
an existence check reporting `ok`. Rule 68 carries both.

## The Degé volume walk is deleted, because it was 15–20× slower — 2026-09-01

Audit item #15 said the Tengyur's precomputed volume walk was failing silently and should
be fixed. The bug was real and one line: `volumes_for/2` returned `{volume, path}` for the
Tengyur where `Edition.volume()` is `{pos_integer(), binary() | Enumerable.t()}`, so the
walk parsed a *file path string* as Tibetan, found no lines, and halted in 2 ms without
ever opening a file. Two clauses of one function returning two different shapes.

**Fixing it made verification 15–20× slower.** Measured on one machine, both sources both
ways, all green and byte-identical:

    source          precomputed walk        per-work fallback
    derge           3m16s   6.1 texts/s     13s     87.6 texts/s
    derge-tengyur   20m30s  2.7 texts/s     1m01s   55.3 texts/s

The mechanism is memory rather than parsing. The walk holds every IR in the edition —
891,169 Tengyur lines, 3.7 GB resident against 830 MB — and achieved parallelism halves,
181% CPU against 373%, because garbage collection dominates. The fallback re-parses each
volume about sixteen times, but inside `Task.async_stream` workers whose garbage dies with
the task.

**The ~90-minute figure that justified the walk was true when it was written.** It stopped
being true when audit #10 removed `texts.body` from the load path and made loading
chunked. Nobody re-measured the optimisation those changes had obsoleted — rule 70 — and
it then failed silently for weeks while everything stayed green and fast, which was the
evidence all along that the fallback had become the better path.

So the walk is gone rather than repaired, `Edition.reduce/4` is untouched and still the
ingest's walk, and `mix pramana.verify` lost a fixed cost and about sixty lines.

## Two of the five architecture audits stop being an honour system — 2026-09-01

`Architecture.BoundariesTest`. `docs/CHECKS.md` §2 has always been owed by a person at a
phase gate, and most of it genuinely needs judgement — *has this codebase quietly stopped
being the thing it was designed to be* is not a grep. But **two of its five audits were
already being performed as greps**, and the 2026-08-28 review records them as exactly
that: zero `Repo.` in `pramana_web`, four Python files importing nothing but stdlib and
tensor libraries. Those now run on every push and name the file and line.

**Leeway is the design, not a concession.** Each rule carries an allowlist with a reason,
so a boundary crossed on purpose is one reviewed line and a boundary crossed by accident
is a red test. A rule with no escape hatch gets deleted the first time it is inconvenient.

**The first version reproduced a failure already on this project's own risk list.**
Substring-matching `urn` flagged every `return` in the sidecar — "four different greps
that matched a substring", `docs/ROADMAP.md`. The second version then forbade a docstring
in `modal_train_tibetan.py` explaining that a fine-tuned embedder changes what is *found*
and never what is *cited*, which is exactly the right comment to have written. Word
boundaries, and prose excluded.

**Each rule was proved to discriminate** by introducing a real violation of it and
watching the test go red, then reversing the edit — a structural test that cannot fail is
worth less than no test, because it reads as green forever.

## `/check` — the first screen that helps you disbelieve something — 2026-08-31

`PramanaWeb.CheckLive`. `Pramana.Report.verify/2` had shipped three days earlier and was
reachable only by an MCP call; rule 60 says a capability a person cannot reach has not
shipped. One textarea, one verdict list, nine tests, and it is in the nav.

It checks a **whole document including its arithmetic** — every quotation byte-compared
through `Guard`, every `pramana-replay` block re-executed against the current bake. Three
verdicts, and `unverifiable` is rendered apart from `failed` because a claim recorded
against an older corpus is not refuted by a corpus that has since changed.

**The test for that distinction failed for the wrong reason first.** With no bake row in
the test database, `Bake.current_id()` is nil, every replay is simply executed, and the
screen rendered `verified` — the assertion caught it. Recording a bake in the setup is the
fix, and the lesson is that a test for a distinction must be able to see the distinction.

## Architecture review — 2026-08-28

`docs/CHECKS.md` §2, run by reading rather than by a task, because the gate's own closing
note says no task can do it: *"a codebase can be fully green and have quietly stopped being
the thing it was designed to be."* All five audits pass; one stale comment was found and
fixed.

| audit | result |
|---|---|
| anything in `apps/pramana_web` reading the DB | **0** occurrences of `Repo.`, `import Ecto.Query` or `from(` |
| domain logic in `priv/embed` | **none** — 0 matches for urn/provenance/citation/witness/canon, and the four files import only `argparse`, `json`, `modal`, `os`, `sys`, `time` |
| a tool returning text without `urn` + offsets + `sha256` | **none**; every text-bearing tool carries them |
| a generated translation reachable as a top-level URN | **impossible by construction** — see below |
| bake reproducible from `sources.lock.json` alone | **yes** — `verify OK`, 4,081 CBETA texts, byte-identical, same day |

**Invariant #8 is wired correctly and its comment had gone stale.** `Guard.citable_as_source/1`
carried *"translation layers do not exist until Phase 3, so today `:method` is always absent
and this always returns `:ok`"* — two phases after the corpus grew 241,409 renderings. The
mechanism itself is right: `Corpus.resolve/1` routes a URN carrying `#tr:<lang>/<translator>`
to `Translations.resolve/1`, which returns a span whose provenance has `method`, so a
generated rendering quoted as scripture reaches the check through the **ordinary** resolve
path rather than one a caller must remember. Comment corrected.

**Two false positives in the audit itself, both mine, both the same mistake.** The sidecar
first appeared to leak domain vocabulary because the pattern `urn` matches inside
**`return`**; the dead-code audit the same hour reported every `?` and `!` function as an
orphan because `\b` cannot match after those characters. Third and fourth occurrence in one
session of grepping for a symptom and getting a subset — the first two were credo's five
priority arrows and the same `\b` problem. **Use the exit code; anchor the pattern.**

---
