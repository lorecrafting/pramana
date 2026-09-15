# Project history — chapter 7

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### Phase 1 gate findings (#13)

The gate did its job — it found more than it confirmed.

| check | result |
|---|---|
| format / compile --warnings-as-errors / credo --strict | clean |
| dialyzer | 0 errors |
| `mix deps.audit` | no known vulnerabilities |
| `mix hex.outdated` | 2 pinned back: `phoenix_live_view` 1.1.33→1.2.9, `phoenix_live_dashboard` 0.8.7→0.9.0. Both LiveView, unused until Phase 8; upgrade deliberately there |
| `mix pramana.verify --all` | 2,471 texts, 4,740,246 segments, byte-identical from `raw/`, 2m37s |
| `mix pramana.integrity` | every `<lb/>`, every printed line, every gaiji accounted for |
| `mix test --cover` | **failed at first** — see below |

**Fidelity (the big one).** `verify` proved reproducibility and could not prove
completeness: 10,590 printed lines had no URN, including 473 rare characters and
266,547 characters of interlinear note text. Two defects, both fixed, pipeline v1 → v3.
`mix pramana.integrity` now guards it. This is recorded at length under *Surprises*
because the general lesson — a deterministic pipeline drops the same thing every run,
so self-comparison cannot detect loss — applies to every source added from here on.

**Architecture review**, against `CLAUDE.md`'s seven invariants:

- **One violation, introduced in this phase and fixed:** the `pramana://inventory` MCP
  resource built its own Ecto queries, so `pramana_web` was reading the database
  directly. Moved to `Pramana.Inventory`. `docs/CHECKS.md`'s wording for this audit was
  also inverted and has been corrected.
- Tools returning quotable text all carry `urn` + offsets + `sha256`. `get_outline` and
  `survey_corpus` return structure and counts only, so the rule does not bind them —
  but `get_outline` was not naming its `bake_id` and now does.
- No generated translation is reachable as a top-level URN (no translation layer exists
  yet — Phase 3).
- No network access anywhere in the bake path outside `Pramana.Acquire`.
- MCP surface is read-only; no ingest or mutation tool exists.

**Coverage.** Failed against Mix's default 90%. The uncovered modules were CLI shells
over already-covered domain functions (`pramana.embed.import` 0% / `Embed.Transfer`
100%), OTP callbacks, and Phoenix scaffolding unused until Phase 8. Configured
deliberate exclusions, then wrote the tests the exclusions did *not* excuse —
`Pramana.Inventory`, `survey_corpus` and `get_outline` had almost none. Now a ratchet:
**pramana 79%, pramana_web 82%**, never to be lowered to make a run pass.

**Not done at this gate:** evals (#19, Phase 4 — there is no gold set yet, so recall@k
and citation accuracy remain unmeasured) and the full-corpus embedding run.

### Phase 2 gate findings (#17) — **NOT TAGGED**

**The tag is deliberately withheld.** #14 (SAT ingest) is blocked on acquisition, so
Phase 2 has an open task by definition, and stamping a gate green over a known gap is
how gates stop meaning anything. **Condition to tag `phase-2`:** #14 resolves, or it is
formally moved to a later phase.

Everything else was run, and it found three real things.

| check | result |
|---|---|
| format / compile --warnings-as-errors | clean |
| credo --strict | **5 issues**, all from the #16 verify/integrity changes — fixed |
| dialyzer | 0 errors |
| deps.audit | no known vulnerabilities |
| hex.outdated | 2 pinned back (both LiveView, unused until Phase 8) |
| test --cover | 357 + 56 + 7, ratchet held |
| verify --all / integrity | green over 2,472 texts |

**1. The licence filter did not exist.** #16's exit criterion required the local text to
be "excluded under a CC0-only licence filter". `license_class` was recorded on every
source and displayed in every result, which made it *look* enforced — but **no retriever
could filter on it**, so "we publish the pipeline, not the corpus" was a promise kept by
hand. Now `redistributable_only:` and `license_class:` filter in Lexical, Semantic and
Survey, with tests. #16 had been marked complete against a criterion no code met.

**2. The public corpus was EMPTY at this gate — and is not any more.** With the filter in
place, `redistributable_only: true` returned **0 hits across all 4.7M segments**: CBETA is
`nc`/not-redistributable and the Huang Nianzu commentary is `restricted`, which was
everything the corpus then held. The Phase 8 public demo had nothing it could serve.

**Superseded, and by a wide margin.** Phases 3 and 5 landed three public-domain sources,
and the filter now returns real results — measured 2026-08-24:

| | |
|---|---|
| redistributable texts | **13,017** (`sc` 8,442 · `derge-tengyur` 3,380 · `derge` 1,195) |
| redistributable segments | **1,797,144** — 27.5% of the corpus |
| embedded vectors over them | **315,208** |

A search under `redistributable_only: true` returns Pāli passages normally. So the Phase 8
public demo has a fully-baked, fully-embedded, two-tradition corpus available to it, and
the constraint recorded here — "nothing it could serve" — is no longer the blocker. What
remains restricted is the Chinese canon (CBETA `nc`) and the one local commentary.

**3. `credo` was not clean at the #16 commit**, which claimed it was — the
verify/integrity changes landed after the credo run. Run the checks *last*, not
mid-change.

**Architecture review** — all seven invariants hold. `pramana_web` touches `Repo` in 0
files; no MCP tool mutates; **0 corpus files tracked by git** (`raw/` and
`sources/local/*/text/` both ignored); no generated translation exists yet; the bake
reads only from pinned sources.

---


### Phase 3+4 gate findings (#20) — tagged `phase-4`

Everything passed, and the review found one real invariant drift.

| check | result |
|---|---|
| format / compile --warnings-as-errors / credo --strict | clean |
| dialyzer, whole umbrella | **0 errors, and no ignore file exists** — none has ever been needed |
| `mix deps.audit` | no known vulnerabilities |
| `mix hex.outdated` | 2 behind, both LiveView, both blocked by constraints and deliberately deferred to Phase 8 |
| `mix test --cover` | **662 tests**; 84.1% / 92.7% / 25% |
| `mix pramana.verify --all` | 10,914 texts, 5,185,767 segments, byte-identical, **242s** |
| `mix pramana.integrity` | every `<lb/>`, printed line and gaiji accounted for, **159s** |
| `mix pramana.evals` | 200 cases, 0 stale, **87.0%** overall |

**Invariant drift found and fixed: a pooled translation carried no hash.** The same
rendering returned `content_sha256` when resolved by URN and no hash at all when listed
in a `compare_versions` pool — so whether a caller could verify the text depended on
which call it happened to make. Invariant #1 says no unattributed text leaves the API;
`sha256` is now on both paths, with a test asserting they agree.

The other four audits were clean:

- **`pramana_web` touches the database in 0 files.** The boundary that drifted once, via
  an MCP resource building its own aggregation, has held since.
- **No domain logic in `priv/embed`.** The sidecar knows ids, text and hashes; it has
  never seen a URN.
- **No rendering is reachable as a top-level URN.** `pramana:sc.ms:mn1@1.1` resolves to
  the Pāli; only `…#tr:en/sujato` resolves to the English, and 0 text rows are
  addressable as renderings.
- **The bake is still reproducible from `sources.lock.json` alone** — which is what
  `verify --all` proves over all three traditions.

### The T56–84 catalogue is blocked too (#41)

The plan was to ingest the *catalogue* for Taishō 56–84 — work numbers, titles, authors —
since bibliographic facts are not the text and carry none of the licensing risk that
blocks #14. **There is no source for it.** Checked at this gate:

- SAT publishes no bulk metadata, API or downloadable index — only a browse interface.
- **CBETA's own catalogue stops at volume 55** as well, for the same reason its texts do.
- No openly-licensed machine-readable Taishō catalogue covering 56–84 was findable.

Two things were deliberately **not** done. Scraping SAT's browse interface, because we
have an access request pending with them and going around it is both discourteous and
pointless if they say yes. And hand-transcribing ~547 entries from a printed catalogue,
because a mistyped title is a fabricated bibliographic fact, which is the category of
error this project exists to refuse.

**What was delivered instead**, from data already held: `Pramana.Coverage` now reports
the gap in **work numbers** rather than only volumes, using the Taishō's own division
table —

    T2185–T2700  續經疏部 (Japanese sub-commentaries)  516 work numbers  japanese/commentary
    T2701–T2731  悉曇部 (Siddhaṃ script)                31 work numbers  japanese/treatise

"Volumes 56–84 are missing" requires a reader to already know which volumes those are.
"T2185–T2731, 547 Japanese-composed works, not held" is a statement they can act on, and
it needed no acquisition and no guessing.

### What the topical questions found (#42) — cross-lingual into Chinese is 0%

The #20 gate asked whether 37.5% was acceptable and answered: not yet a number worth
optimising, because the harness measured *pinpoint the anchor whose translation I quoted*
while users ask topical questions. #42 added 40 hand-written topical questions with
term-verified ground truth, and the answer turned out to be more specific than expected.

    topical / chinese-native   100.0%  (12/12)  mean rank 1.25
    topical / pali              62.5%  (10/16)  English query, has translation vectors
    topical / chinese            0.0%  (0/12)   English query, NO translation vectors

**Same twelve questions, same corpus; only the query language differs.** Chinese
retrieval is not broken — cross-lingual retrieval *into* Chinese is. Ask in Chinese and
the corpus answers perfectly at rank 1.25; ask the identical question in English and it
answers not at all.

This is a missing-layer problem rather than a tuning problem, and the contrast proves it:
Phase 3 gave Pāli chunks an English rendering to match against, which is exactly why the
English→Pāli row works. The Chinese canon has no English translation in this corpus, so
an English query has to cross inside BGE-M3's own multilingual space —
`Pramana.Retrieval.Semantic` has carried the admission that this was unproven on Literary
Chinese since Phase 1. It is now measured, and it does not work.

So the highest-value retrieval work is **an English gloss layer for Chinese chunks**
(#43), ahead of any parameter tuning. The two earlier hypotheses — chunk granularity and
the 320-token truncation — are demoted to secondary; they may not be the binding
constraint at all.

**Two errors in the previously published table, corrected here.** The README's
"↳ Chinese 98.7% (75 cases)" under *Retrieval* was a by-tradition row that silently
included the 40 provenance cases, so its sub-rows did not sum to their parent; the real
figure is 97.1% over 35 Chinese retrieval cases. And the 100%/0% split above was
invisible in both margins of the report — it only appeared once case type was crossed
with tradition, which the scorecard now always does.
