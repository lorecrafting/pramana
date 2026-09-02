# Project history

**What happened, in order, and what surprised us.** This is a log: entries are written when
the work lands and are not edited afterwards, so a statement here is true *of its date* and
may be false now. If this file and `docs/STATUS.md` disagree about the present, STATUS is
right; if they disagree about the past, this is.

That distinction is why this file exists. These 2,000 lines sat under a heading called
"## Next" inside `STATUS.md`, where a historical sentence — "this bake holds two CBETA
collections" — read as a current claim. It was corrected four separate times before anyone
noticed the heading was the problem.

- **What is true now** → `docs/STATUS.md`
- **What to do next** → `docs/PLAN.md`
- **What we learned, as reusable rules** → `docs/RULES.md`

---

## The Chinese canon gets an English layer, and it is not enough — 2026-08-31

§ E1's first slice. `mix pramana.sc.chinese` and `Pramana.Sc.Lzh`: **3,354 CC0 English
renderings anchored to Taishō lines**, the first English over the Chinese canon in this
corpus. 86.9% of anchors matched the two editions' text exactly; 13.1% are bounded by
neighbours that did and stamped as such; 2 segments were dropped.

**It was already on disk.** Charles Patton's English of 54 Saṃyukta and Madhyama Āgama
sūtras had been in the `sc-translations` lockfile entry since #39 and discarded at every
ingest, because its anchors name SuttaCentral addresses and this corpus holds those Āgamas
as CBETA. It landed in `no_such_anchor`, the same counter the Pāli's legitimate elisions
use, so it read as noise. The sparse checkout had never fetched `root/lzh` either.

**And `topical/chinese` did not move.** Still 0 of 12; `--only topical` scored 51.0%
against a baseline of 51.0% with every tradition row identical, so nothing regressed and
nothing improved. 191 English chunk vectors over the Chinese against 55,135 over the Pāli
answer the same English question, and the Pāli wins. Isolated from that competition,
`mix pramana.recall --renderings --to cbeta.T` scores 63.0% work-level and **37.0% on
line** over 200 seeded pairs.

**A control changed the story on the way.** Scoped to CBETA, "How is mindfulness of
breathing taught?" returns the SĀ ānāpāna sutras at ranks 1–4, which looked like the
result. The nearest CBETA vectors to that query are `parallel_gloss/en/sujato` at d=0.143
and 0.153 — machinery that predates this work — with Patton's own vector third at d=0.224.
Rule 62, caught before it was written down as a finding.

**Two latent defects surfaced.** `Pramana.Chunk.Vectors` excluded every range-anchored
CBETA rendering (2,089 of 3,354) by testing `urn_prefix <> "@"` against an address that
puts the juan in between — now rule 68 and `Pramana.URN.addresses?/2`. And
`mix pramana.recall --renderings` reported hits per language with no denominator, inside
the instrument rules 22, 44 and 54 are measured with.

## Architecture review, the three audits a test cannot do — 2026-09-02

`docs/CHECKS.md` §2 asks for findings to be written here. Two of its five audits became
mechanical on 2026-09-01 (`Architecture.BoundariesTest`); these are the three that were
left, performed by reading.

**Can any tool return text without `urn` + offsets + `sha256`?** No, with one qualification
that is new today. `get_outline` looked like a candidate — its own file never says `urn` —
but the entries are built by `Corpus.outline/1`, which puts one on each. `survey_corpus`
returns counts rather than text.

**`compare_translators`, added today, returns Chinese and Sanskrit headwords with no URN.**
They are not corpus spans — they are lexical entries from a third-party dictionary, and
each response names Karashima and the licence — so invariant #1 is not violated on a
strict reading. But **the anchors now exist**: `glossary_anchors` resolves 25,504 of those
citations to lines this bake holds, and attaching one to each divergence would make every
comparison openable and byte-verifiable rather than merely attributed. Recorded as work,
not as a violation. `docs/PLAN.md`.

**Is any generated translation reachable as a top-level URN?** No. `Pramana.Translations`
addresses a rendering as a fragment over its anchor (`…#tr:en/patton`) and the guard's
`:not_citable_as_source` verdict is exercised by tests. Nothing added today creates a new
path to one: `Pramana.Repair` rewrites a caller's own document and never mints a URN, and
`Pramana.Citation` resolves foreign citations only to lines that already exist.

**Is the bake still reproducible from `sources.lock.json` alone?** Yes, and it is now
harder to break: the gate's lockfile step passed on 2026-09-02, and all eleven tasks that
write the lockfile re-record the bake, enforced by a structural test rather than by
memory.

**The judgement the section exists for** — *has this codebase quietly stopped being the
thing it was designed to be* — is the one nobody can delegate, and it is not answered here.

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

## Announcements as they were written

*Moved out of `STATUS.md`'s "Where we are", which had become a pile of dated claims reading
as current ones — one of them carried its own parenthetical, "(written when the Taishō was
the corpus)". Each is true of when it was written.*

**Phases 0, 1, 3 and 4 complete and gated** (tags `phase-0`, `phase-1`, `phase-4`).
**Phase 2: #15 and #16 done, #14 blocked on acquisition, gate (#17) run but deliberately
NOT tagged** — see the gate findings below. Phase 2 is the only unfinished phase behind
us, and it is waiting on an email, not on code.

**The whole Chinese canon is baked, verified, and embedded.** 2,471 works, **4,740,246
segments**, 90.6M characters, 150 s, zero failures. Both integrity checks
are green over every text: `mix pramana.verify --all` (byte-identical re-normalization
from `raw/`) and `mix pramana.integrity` (nothing printed in the source is missing from
the bake — a different question, see the rules section).

**The 嘉興大藏經 (CBETA J) is baked** (B): 285 works, 17.8M characters, zero failures,
provenance from the byline for 116 of them. Two works span volumes — JB271 (31+32) and
JB277 (32+33) — and were assembled before loading, which is the fix made for X's six
working on a collection it was not written against. The corpus is **17,004 texts and
11,519,879 segments**, and CBETA is now 3 collections of 26.

**The 卍續藏 (CBETA X) is baked, verified, and NOT embedded** (B). 1,230 works, 87.6M
characters, provenance from each work's own byline, pipeline **v4**. Six of those works
run across two printed volumes and are assembled before loading; the four defects that
ingest left behind — including a lockfile that had stopped describing the corpus — are
recorded below. Its 1,230 texts are reachable by the lexical arm and invisible to the
semantic one, which `embedding_coverage` now says out loud instead of reporting 100%.

**Semantic search covers 100% of the Taishō.** 299,317 chunks embedded with BGE-M3 on a
rented L4: 34 min, ~$0.45, 0 rejected vectors. (Written when the Taishō was the corpus;
X is baked and unchunked, and the coverage field now reports that rather than 100%.) Hybrid retrieval fuses lexical and
semantic by Reciprocal Rank Fusion. Querying 眾生皆能成佛 — a paraphrase that appears
nowhere as a literal string — returns 故眾生無不成佛 at 0.817 similarity, which the bigram
index structurally cannot do. Lexical alone runs in 26–63 ms; filtered semantic in
0.5–3 s.

**Provenance is populated across the whole Taishō** from the division (部) table: 1,781
Indic works, 555 Chinese, 135 deliberately unattributed (古逸部 Dunhuang), and **57
apocrypha** flagged. Search results arrive in buckets keyed by composition origin and
text role, each labelled in plain language ("Japanese-composed commentary"), so the
distinction cannot be flattened away by a caller.

**What is NOT here, and says so:** Taishō volumes 56–84 — the Japanese-composed
sectarian corpus. CBETA excludes them and only SAT publishes them, and SAT has no bulk
download (#14). Until that is resolved `Pramana.Coverage` states the gap in every survey
response, because otherwise an absence of Japanese results reads as the tradition being
silent.

**The Pāli canon is in, and with it the first redistributable content** (#38): 8,442
works, 444,673 segments under SuttaCentral's own segment ids. The corpus is now 10,914
texts and 5,185,767 segments across two traditions, and 24,717 curated parallels resolve
at both ends, so SA 1 (Chinese) and SN 22.12 (Pāli) are quotable side by side.

**The Derge Kangyur is in** (#21): 1,195 Tibetan works, 461,302 lines, addressed by the
edition's own reference system — `pramana:derge.D:toh8@14.1b.1` is volume 14, folio 1
verso, line 1. The corpus is now **12,109 texts and 5,647,069 segments across three
traditions**. 75 works run across more than one volume and are assembled before loading,
because the loader replaces a text's segments rather than appending to them. Every text
re-derives from `raw/` byte-identically, and the whole edition reconciles against an
independent byte count to 69 bytes — volume 1's title page, which belongs to no Tōhoku
number. What is NOT here yet: work titles and the English translations. Both come from
84000, whose 396 published Kangyur translations are downloaded and not yet ingested.

**The Degé Tengyur is in** (#21): **3,380 works, 891,169 lines** across 213 volumes of
Indian commentarial literature — Nāgārjuna, Vasubandhu, Dharmakīrti, Candrakīrti — under
the same anchor grammar as the Kangyur: `pramana:derge-tengyur.D:toh4090@140.26b.1` is
where Vasubandhu's Abhidharmakośabhāṣya opens, volume 140, folio 26 recto, line 1. The
corpus is now **15,489 texts and 6,538,238 segments**. Every one of the 3,380 re-derives
from `raw/` byte-identically. The two canons are separate sources because they are
separately published prints with different licences and different editorial hands, and
`Pramana.Coverage.tibetan/0` counts both: the caveat that said the commentators were
absent is gone, and the only remaining coverage gap is Taishō 56–84.

**Semantic search covers three traditions** (#21). **617,038 vectors, 100% of the chunks
that exist — but 92.6% of the corpus's texts**, because CBETA X is baked and unchunked:
300,165 Literary Chinese, **215,354 Tibetan**, 44,719 Pāli, 55,135 English renderings and
1,665 parallel glosses. Tibetan is now the largest non-Chinese layer, and every Tengyur
vector is labelled `bo` rather than falling through to the `lzh` default.
The Tibetan has an English layer for the same reason the Pāli does — 84000's
renderings become `translation/en` vectors on Derge chunks — so an English question can
reach a Tibetan passage and still cite the Tibetan.

**84000's English is attached to the Tibetan** (#21): 30,653 folio-level renderings
across 472 works, and 478 of the 1,195 Kangyur works now carry titles in English,
Sanskrit, Tibetan and Wylie. `pramana:derge.D:toh113@51.100a.1-51.100a.7#tr:en/84000` is
a range anchor, because 84000 cites folios where we cite lines, and it resolves to the
seven Tibetan lines that folio holds.

**Translations are a pool, not a winner** (#39). 210,756 English renderings by 8
translators, keyed onto source anchors; 4,601 anchors carry more than one. Callers supply
a selection policy — prefer a tier, pin a translator, or `compare` for the whole pool —
and are always told how many renderings were withheld. A rendering has no top-level URN:
it is addressed as `<anchor>#tr:en/sujato`, so stripping the fragment always leaves a
citable source, and the guard rejects any non-human rendering quoted as scripture.
The reading layer (pinyin and friends) stores **only exceptions**, seeded from the
glossary: 元曉 → *Wŏnhyo*, 道隱 → *Dōin*, and 12 forms recorded as "not read the ordinary
way" with no reading invented for them.

**Semantic search is multi-vector** (#40). Vectors moved out of `chunks` into
`chunk_vectors`, so a chunk carries several: the passage itself, and the same span in a
translator's English. 342,535 vectors — 300,165 Chinese, 27,589 Pāli, 14,781 English
renderings. An English query can now reach a Pāli passage **through its rendering** while
the result still resolves to, and cites, the Pāli; every hit reports `matched_via`, so a
caller can tell a hit found through English from one found in the original. Chunk size is
per-script — 300 characters of Literary Chinese, 1,200 of romanised Pāli — because one
number silently under-chunks the alphabetic corpus. (The Pāli figure was later measured
against the tokenizer and corrected to 700; see #21 below.)

`compare_versions` and `define_from_canon` ship with it: the same passage beside its
renderings and curated parallels, and the canon's own definitional formulae (云何為X,
Katamañca X) so a definition can be quoted rather than composed.

The end-to-end path works: acquire → normalize → segment → chunk → embed → resolve →
verify, with an MCP server on top exposing nine tools and two resources. A model can
fetch an exact passage by URN, ask for translations alongside it, and the guard
byte-compares its quote.

### Verified, not just built

| Claim | Evidence |
|---|---|
| Nothing lost in normalization | 5374 lines == 5374 body `<lb>`; 941 attached + 4 unanchored == 945 == raw `<app>` |
| Citations are unique | all 5374 line anchors distinct; all URNs parse |
| Spans are byte-verifiable | all 5341 segments' byte offsets slice their exact content out of the body |
| The bake is reproducible | `mix pramana.verify --all`: body re-normalized from `raw/` is **byte-identical** to stored |
| The guard actually catches things | fabricated URN refused; 譯→說 single-character alteration caught, over the wire |

### Gate results (at tag `phase-0`; test count has grown since)

- `mix format --check-formatted` clean
- `mix compile --warnings-as-errors` clean
- **148 tests** passing (128 domain / 13 web / 7 native). Now **175**.
- `mix credo --strict` — 69 checks, 0 issues
- **`mix dialyzer` — 0 errors**
- `mix deps.audit` — no vulnerabilities
- `mix pramana.verify --all` — 1 text, 5341 segments, byte-identical
- Architecture review: all seven invariants hold (see below)

### Architecture review, Phase 0

- **#1** `pramana_web` touches `Repo` in **0 files** — the web layer goes through the
  domain. Every MCP response is `Response.json` or `Response.error`, never prose.
- **#2** URNs are built from each tradition's own citation grammar; no invented IDs.
- **#3** `raw/` is gitignored and nothing from it is committed; `mix pramana.bake`
  verifies `raw/` against the lockfile *before* trusting a byte of it.
- **#4** Provenance is CHECK-constrained columns (`composition_origin_known`,
  `text_role_known`), indexed, never a single source string.
- **#5** Deterministic throughout Phase 0; no LLM in the pipeline yet.
- **#6** No retrieval yet, so no evals yet. Phase 4 owns this.
- **#7** Wired in `Guard.citable_as_source/1` and tested via `check_span/3` with a
  synthetic span, so it is not retrofitted in Phase 3.
- No `priv/embed` sidecar exists yet — correct for Phase 0.

---

---

---

## Next

Phase 1 is complete and gated (**#13**), and the full-corpus embedding run has landed.

**Phase 2:** #15 (structural provenance) and #16 (local-source manifest path) are done —
the Huang Nianzu commentary is in the corpus, page-anchored and licence-gated. #37
(batched embedding import) is done. The gate (#17) has been run; the tag is withheld
until #14 resolves.

**#14 is blocked and needs a human.** SAT publishes no bulk download, so obtaining
Taishō 56–84 starts with an email to `sat at l.u-tokyo.ac.jp` — a draft is in
`docs/sat-request-email.md`, not sent.

**#32**, **#34**, **#36** and **#37** are all done. Nothing in Phase 2 remains except
**#14**, which is waiting on SAT's reply. **Phase 3** (#18, SuttaCentral Pāli) is the
next substantial work and brings the first redistributable content.

**Phase 3 matters more than its number suggests:** SuttaCentral `bilara-data` is CC0 and
would be the **first redistributable content in the corpus**. Until then the public
surface has nothing to serve — see gate finding 2.

**Now measured** (#19). `mix pramana.evals` scores a 200-case gold set whose expected
answers come from curated parallels, published translation anchors, the Taishō division
table and the canon's own definitional formulae — never from a model. Published in the
README: **overall 87.0%**, quote verification and rejection **100%**, provenance **100%**,
retrieval@10 **65.3%** (Chinese 97.1%, Pāli cross-lingual **37.5%**), and topical
**55.0%** — which #42 then split into the finding that matters, below.

The Pāli figure is the weak axis and is published as such. Two things it taught:
**semantic search was silently not running** for any caller that omitted `:serving`
(fixed — the running serving now decides), and **over half the Pāli gold cases quote text
that occurs in several places**, because this literature is formulaic by design.

### What Phase 5 still needs

The Kangyur is in, joined to its English, chunked and embedded. What the phase exit
("three-way retrieval with correct provenance") still wants:

- **The Tengyur has 2,675 of its 3,380 names, read out of the works themselves** — 2,629
  Tibetan titles and 46 Sanskrit-only; see below. The 705 that do not name themselves are
  left unnamed. No English titles
  exist for any of them, because 84000 has not translated the Tengyur.
- **Only a twentieth of the Kangyur is translated.** 84000 has published 385 of ~1,169
  Tōhoku numbers, so most works have no English. They now all have *titles* — see the
  catalogue section below — but a title is not a translation, and topical retrieval into
  Tibetan is 0% because of it.
- **Tibetan lexical search now windows syllables** — see the section below. The old
  grapheme windows were producing `་པ་`, which matches 89.6% of the corpus.
- **The embedder, not the corpus, now bounds Tibetan retrieval.** Measured below: BGE-M3's
  mean pairwise cosine for Tibetan is 0.9727 against 0.84 for Pāli, so ranking within
  Tibetan is weak by construction. Tibetan's own problem is RECALL, not order — half its
  gold never enters a 200-candidate pool — so a reranker cannot reach it and the
  fine-tuned embedder is the lever *for Tibetan*.

  **This bullet demoted the reranker for the whole system on that evidence, and that was
  wrong.** Pāli is 150 of the retrieval cases against Tibetan's 64, and Pāli fails the
  opposite way: its gold is retrieved 84% of the time and merely mis-ranked, so a
  reranker is worth **+44 cases** there against +9 in Tibetan. See *The reranker verdict
  was right about Tibetan and wrong about the system*. Rerank for Pāli, embed for
  Tibetan.
- **Tibetan word segmentation.** ~~`botok` in the Python sidecar is the intended
  syllable/particle segmenter.~~ **Withdrawn.** The lexical layer windows syllables on the
  tsheg the edition prints, which supersedes it for the same reason jieba was refused for
  Chinese — see *Tibetan n-grams were mostly one particle*. `botok` was never added; only
  the documentation kept it alive.
- **Mahāvyutpatti** proper is now loaded as text — Toh 4346, 1,554 lines from volume 204,
  ingested with the Tengyur — but as an untitled Tengyur work, not a parsed lexicon.
  The 84000
  half of that bullet is **done**: 865 three-way Skt–Tib–Chi anchors, below. BDRC metadata
  and IIIF image links are **done** too.

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

### The free gloss experiment (#43, stage A) — and why stage B should not proceed as planned

Before spending tokens, invariant #5 says use the deterministic data. We hold 24,717
curated Chinese↔Pāli parallels and 210,756 human English renderings of the Pāli, which
covers **1,616 of 10,138 阿含部 chunks** with English a person actually wrote. Attached as
a fourth vector kind — `parallel_gloss`, never `translation`, because it renders a
*parallel text* and not the passage — for **zero token cost** and about a cent of GPU.

    topical / chinese         0.0%  ->  33.3%    English query into the Chinese canon
    topical / chinese-native  100%  ->  100%     rank improved 1.25 -> 1.08
    topical / pali           62.5%  ->  50.0%    regressed
    topical overall          55.0%  ->  60.0%

**A third of the Chinese cross-lingual failures were fixed for free.** The English layer
was the missing piece, as #42 predicted.

**The Pāli drop is mostly a gold-set artifact, and the residue is real interference.**
Inspected directly: "What are the four noble truths?" now returns T0099 — the Saṁyukta
Āgama, the Chinese parallel of exactly the right Pāli material — interleaved with the
Pāli. Those Chinese hits are *correct answers to the question*. The case scores them as
misses only because it demands a Pāli term, so the system got better and the metric
punished it.

But the mechanism underneath is real: **English vectors from different traditions compete
in one space.** 1,665 gloss vectors were enough to displace Pāli answers. Stage B would
add ~300,000 of them against 14,781 Pāli translation vectors — a 20:1 imbalance that
would likely bury the Pāli entirely.

So **stage B does not proceed as scoped.** Two things must come first:

1. **A tradition-agnostic topical score.** A user asking "what are the four noble truths"
   is well served by either canon; the gold set currently measures per-tradition
   reachability and calls the other tradition wrong. Both numbers are worth having, but
   they must be labelled as the different questions they are.
2. **A balancing story for retrieval.** Whether that is per-tradition quotas, a diversity
   term in fusion, or simply surfacing both — undecided, and it needs measurement rather
   than a guess.

Cost estimate for stage B, kept for when it is unblocked: 10,138 阿含部 chunks, 2,896,481
Chinese characters, ~3.0M input and ~1.1M output tokens, **~$9 on Haiku, ~$26 on Sonnet**;
the whole canon is 29.6x that (~$260 / ~$770). Embedding is negligible beside generation.
The char-to-token ratio for Literary Chinese is an assumption that should be measured on a
sample before committing.

### The plain HNSW scan was returning worse answers, not wrong ones (#43)

Found while fixing a bug I introduced. Making `vector_kinds` default to a list meant every
query carried a `WHERE kind IN (...)`, but `filtered?/1` did not know about it — so
searches took the plain index scan and post-filtered, the exact truncation rule 6 warns
about. Pāli pinpoint retrieval fell 37.5% -> 30.0%.

The fix was to route **every** query through the iterative scan, which removed the
`@filter_keys` list entirely: there is no longer a set of "options that narrow the
candidates" to keep in step with `apply_filters/2`, so the thing that had to be remembered
is gone.

And it turned out the plain scan had been costing recall all along:

    overall            81.7%  ->  83.3%
    retrieval / pali   37.5%  ->  42.5%
    topical / pali     62.5%  ->  75.0%

The old comment said "unfiltered: the plain index scan is correct and ~3x faster, so leave
it alone". It was right about correctness and wrong about quality — with `ef_search` at
its default the plain scan explores less of the graph and returns *worse* neighbours, not
invalid ones. Nothing failed; the answers were just further down. Cost of the change: 252s
-> 890s for 240 eval cases, about 3.5x.

**The general lesson: a fast path justified by "there is no filter here" is still a
quality decision, and quality decisions need a measurement.** This one sat unmeasured
from Phase 1 until an eval harness existed to catch it.

### Bake cost review (#20)

What a full rebuild costs now, with three traditions and 5.19M segments:

| stage | time |
|---|---|
| CBETA normalize + segment (2,471 works) | 150 s |
| Pāli ingest (8,442 works) | 53 s |
| Translations into the pool (4,996 files) | ~60 s |
| Parallels import (407,176 relations) | 29 s |
| Chunking, whole corpus | 84 s |
| Vector rows (source + translation) | 70 s |
| **Embedding, 342,535 vectors on an L4** | **~40 min, ~$0.50** |
| Vector import (no index present) | 29 s |
| HNSW build, 342,535 vectors @ 6 GB | 395 s |
| `verify --all` | 242 s |
| `integrity` | 159 s |
| **Total wall clock** | **~55 min**, of which 40 is GPU |

Database: **26 GB**.

**Token cost of a bake: zero.** Nothing in the pipeline calls a language model —
normalization, segmentation, chunking, alignment and provenance are all deterministic,
and the only model involved computes embeddings. That is not frugality, it is the
architecture: a bake whose contents depended on a model's output could not be
reproduced from `sources.lock.json`, and `bake_id` would be a fiction.

The first LLM tokens enter at Phase 7, and they enter as a **layer** — generated
translations in the pool, marked, never citable as source.

### The apparatus shipped, and witness ids are not what they look like (#45)

`compare_witnesses` now answers "how does this line differ across the witnesses" over the
**572,701 segments** that carry an apparatus — 消 → 銷 in 【宋】【元】【明】, 至 → 志 in
【宋】. The data had been captured since Phase 0 and reachable only as an opaque blob.

**The attribution was the hard part, and assuming would have been badly wrong.** A
`<rdg wit="#wit1">` names a witness declared in *that file's own header*. Measured across
all 2,471 CBETA files:

    wit1   38 distinct meanings — 宋 in 832 files, 明 in 375, 甲 in 322, 原 in 149
    wit2   33 distinct meanings
    only 4 of 23 ids mean one thing everywhere

A global lookup table — the obvious implementation, and the one a quick sample of four
files would have supported, since `wit1` was 宋 in all four — would have reported Ming
variants as Song ones in roughly a thousand works, in the tradition's own sigla, with
nothing about the output looking wrong.

So each text carries its own map, imported by `mix pramana.witnesses.import` from its own
pinned file. That task deliberately does **not** re-bake: re-normalizing would delete and
rebuild segments, cascading to 344,200 embeddings and 40 minutes of GPU, so it updates
`texts.meta` in place and stays checkable against `raw/`.

Two distinctions kept that a simpler shape would have lost: an unresolvable id returns
`witness: nil` with the raw id preserved rather than a guess, and an **omission** ("this
witness has nothing here") stays distinct from a **substitution** ("reads something
else") — different claims about a manuscript.

### Tradition balancing: the measurement is the deliverable, round-robin is not (#44)

Two halves. The measurement half worked and changes how this project reports itself; the
retrieval half was tried and **rejected on evidence**.

**Measurement.** Topical cases now carry a `topic` slug linking the same question asked of
different canons, so two genuinely different questions can both be answered:

    per-tradition reachability   "can an English query reach the PĀLI witness of this?"
    answered from any tradition  "did the reader get a good answer from anywhere?"

The second is what a reader cares about, and it was not computable before. It is
**81.8% (9 of 11 topics)** at the shipped default — against per-tradition figures of
0% (Chinese) and 68.8% (Pāli). Reporting only the per-tradition numbers understated the
system badly, because answering correctly from the other canon counted as a failure.

**Retrieval.** Round-robin interleaving by tradition was implemented and measured:

    default                   chinese 0.0%   pali 68.8%   answered 81.8%
    + parallel glosses        chinese 33.3%  pali 50.0%   —
    + glosses + balancing     chinese 33.3%  pali 50.0%   answered 63.6%

It moved neither tradition's rate and made the user-facing number **worse**. Pāli mean
rank went 3.18 -> 5.13: interleaving inserts the other tradition between correct answers,
so a hit at rank 3 lands at rank 5 and some fall out of the top ten entirely. Guaranteeing
representation costs ranking, and for a question whose answer genuinely lives in one canon
that is pure loss.

The option survives (`balance: :tradition`, default off) because it is measured and might
suit a caller who explicitly wants breadth. It is not the mechanism.

**What this actually resolves.** The blocking worry was "we cannot add English layers for
another tradition without silently hurting the ones we have". True, and the fix is not a
ranking trick:

- **the layers stay opt-in**, so nothing taxes the default path
- **the caller says what it wants** — a reader after the Chinese witness asks for it, and
  `compare_versions` already shows several traditions side by side rather than making them
  fight for ten slots
- **`answered from any tradition` is the number to optimise**, and it now exists

On that basis #21 (Tibetan) and #26 (translation engine) are unblocked, with a documented
constraint rather than a solved problem: any new English layer must be measured against
answered-from-any-tradition before it becomes a default, and the parallel-gloss layer is
evidence that "it helps one tradition" is not sufficient.

### The eval gate was going to cry wolf (#44)

Two runs of an identical build differed by **one case** in each of `retrieval`
(68.0% / 66.7%) and `topical` (60.0% / 57.5%). Nothing between them touched retrieval.
Approximate nearest-neighbour search with `relaxed_order` simply does not return a fixed
ordering, and at 40-75 cases per type one flip is 1.3-2.5 percentage points.

The gate compared rates and failed on any decrease, so it would have reported a
regression on roughly every other clean run. A benchmark gate that cries wolf gets
ignored, and an ignored gate is worse than none — so the threshold is now in **cases**,
not percentage points: one may flip, two is real.

The cost is that a genuine one-case improvement will not ratchet. That is the right trade:
a gate exists to catch a system getting worse.

**The README claimed "pass rates have been stable"** across runs. That was wrong and is
corrected there. It was written after two runs that happened to agree.

### The Derge normalizer (#21) — a third of the edition, silently

103 volume files in, 1,196 Tōhoku works out: **461,414 citable lines, 77.5M characters
of Tibetan**, in 15 seconds. The citation anchor comes straight from the markup, as it
should — `data-orig-n="1b"` is the folio and `<milestone unit="line" n="3"/>` the line —
so a passage is addressed `1b.3`, which is how Tibetanists cite.

**The first version dropped 146,962 lines and looked fine.** A work is delimited by a
`<milestone unit="text" toh="N"/>` marker, and I treated text before the first marker as
front matter, which is true of volume 1 and false everywhere else: the Vinaya runs to
volume 13 and the Prajñāpāramitā across a dozen more, and **26 of the 103 files contain
no marker at all**. Their entire contents vanished. Nothing errored, the work count was
plausible, and the only visible symptom was a mean line length of 169.7 characters where
a Derge line is nearer 80 — two lines' worth of text under one anchor.

The number that exposed it was one I already had: 460,539 line milestones counted
straight out of the XML, against 313,577 lines emitted. **A count taken from the source
before parsing is worth more than any number the parser reports about itself**, because
the parser's numbers are all downstream of the same wrong assumption.

`normalize_file/2` now takes the work in progress and returns the work still open, and
volumes must be fed in order. 461,414 lines, matching the milestone count.

Three more things the edition itself made necessary:

- **Folio numbers restart at `1a` in every volume**, so the anchor is
  `volume.folio.line` — `2.5b.3`. Without the volume, a work spanning one addresses two
  different lines as `1b.1`, and 26 works span volumes.
- **Volume 103 is the dkar chag**, the catalogue. Eight `toh` markers sit there on titles
  in a running list — Toh 539 is `ཕྱག་དང་།`, "homage, and" — and splitting on them yields
  eight works a few words long that collide with the real text. Median characters between
  markers: **24 in volume 103, 7,804 everywhere else.** It is normalized as one work,
  which it genuinely is.
- **Three anchors in 461,414 lines are printed twice.** Dropping the second loses text;
  merging makes two passages one. They keep the printed anchor with `+2` appended, which
  is visibly not a folio reference — a reader who sees it learns the edition is ambiguous
  there rather than receiving a citation that looks clean and resolves wrongly.

### The Derge ingest (#21) — the edition is the unit, and the header is not the book

**The Kangyur is in: 1,195 works, 461,302 lines, 12,109 texts and 5,647,069 segments
across three traditions.** `mix pramana.derge.ingest` walks the 103 volumes in printed
order in 4m35s; `mix pramana.verify --source derge` re-derives every one of the 1,195
texts from `raw/` byte-identically in 75s. URNs read `pramana:derge.D:toh8@14.1b.1`.

**The numbers in the section above were wrong, and this section's are checked.** The
normalizer's own report said 1,196 works and 461,414 lines. Ingest says 1,195 and
461,302, and the difference is not a regression — it is 102 lines of Esukhia's
distributor note (see below) plus one work that only ever existed as a double count.

Four things this stage settled:

- **A volume is not the unit of loading, and the loader will not tell you.**
  `Loader.load/2` is idempotent by replacing a text's segments, so a work loaded once per
  volume keeps its **last** volume and silently discards the rest — twelve volumes of
  Vinaya, in a text that reports a plausible length and resolves every URN it contains.
  Works are assembled across volumes in `Derge.Edition` and loaded once. 75 of the 1,195
  span more than one volume; Toh 8 spans thirteen.
- **`<teiHeader>` was being read as scripture.** Every volume's `<publicationStmt>`
  carries a 416-byte distributor note, and the normalizer buffered all character data
  regardless of where it sat. In a volume that opens with a work already running — 102 of
  the 103 — that note flushed into the work as its first line, with a URN that resolves.
  Nothing errored: it is text, in a text, with an anchor. The only tell was the anchor
  itself, `2..`, because no folio had been read when it was emitted.
- **What found it was a count that shares none of the parser's assumptions.** Not line
  counts — those agreed. `Derge.Audit` adds up the non-whitespace bytes of character data
  inside `<text>` and knows nothing about folios, markers or works: **290,863,399 in the
  edition against 290,863,330 in the bake, and the 69-byte difference is volume 1's title
  page**, which belongs to no Tōhoku number and is dropped on purpose. That reconciliation
  now runs in `mix pramana.integrity`, per volume, and the rule it enforces is that **only
  the first volume may drop anything** — a later volume dropping its preamble is the exact
  shape of the 146,962-line bug.
- **Four leaves in the edition are inserted rather than numbered** and are labelled
  `33xa`, `93xb`, `354xa`, `355xb`. 65,975 folios take the regular form and exactly 8 do
  not, which is the kind of thing worth counting before writing the pattern that parses it.

Provenance is `indic` / `root` / **`probable`**, not `certain`: the Kangyur's claim to
Indic origin is a claim about where the collection places a text, and it is wrong for a
few (the *mdzangs blun* was assembled from Chinese). Per-work correction is what the 84000
catalogue join is for. The dkar chag is loaded as what it is — `tibetan` / `catalogue` /
`certain`. Titles are absent by design: this etext titles volumes, not works, and 84000
publishes a title for every Toh number in four languages.

### The 84000 join (#21) — 30,653 English folios anchored to Tibetan lines

84000's published Kangyur translations are in, keyed onto the Derge text they translate:
**30,653 renderings across 472 works**, and **478 of the 1,195 Tibetan works now have
titles** in English, Sanskrit, Tibetan and Wylie. An anchor reads
`pramana:derge.D:toh113@51.100a.1-51.100a.7#tr:en/84000`, and it resolves: the English
"His subtle body is adorned by the thirty-two signs" comes back beside
`སུམ་ཅུ་རྩ་གཉིས་མཚན་རྣམས་ཀྱིས། །ཕྲ་བའི་སྐུ་ནི་ལེགས་པར་བརྒྱན།`, line for line.

**The anchor is a range because the two editions cite at different grains.** Ours are
lines, 84000's are folios, so a folio's English renders about seven of our lines and is
stored against the range of exactly those. Anchoring it to the folio's first line would
have been a smaller change and a false claim.

Four things this cost, all of them the same lesson — *the file describes its own location
three times and the three disagree*:

- **`<biblScope>` is prose, `<location>` is arithmetic, and the folio reference in the
  body is the folio.** For Toh 883 the prose says volume 100, the page arithmetic says
  folio 122a, and the reference says 123a. Our Derge etext has it at volume 101, folio
  123a — so the volume comes from `<location>` and the folio from the reference, and
  nothing is computed. Only checking all three against the Tibetan we already had could
  have told us that.
- **A partial match is the dangerous case, not a total mismatch.** 84000 numbers Toh 11's
  folios from the work's own beginning in its second volume — `F.92.b` where the Degé
  prints `1a` — and **428 of those 610 numbers exist in that volume of that work**. They
  anchor. They resolve, they byte-verify, and they attach English to a passage it does
  not translate. So a volume's spans are accepted or refused **together**, on a 95%
  threshold: 490 of the 503 volume-groups land completely, and the rest divide sharply
  into 99.4%/99.6% (84000 citing one folio past the end of ours) and 70%/67%/0%.
- **One translation can render two places in the canon at once.** A dhāraṇī printed twice
  in the Kangyur is translated once, with both editions' folio boundaries marked in one
  interleaved flow — `F.1.b`, `F.123.a`, `F.2.a`, `F.123.b`. Each `<bibl>` gets the whole
  translation cut at its own boundaries, which is why 385 files produced 478 work-level
  attachments.
- **A mirror keeps renamed files.** 11 Tōhoku numbers arrived twice because 84000 renames
  a file when a translation is revised (`the_gandhavyuha_sutra` → `the_stem_array`), and
  7 of those pairs differ in the text. The `<edition>` version decides, compared as
  numbers: `v 1.0.30` is newer than `v 1.0.7` and older than `v 1.1.1`, and string
  ordering gets both comparisons wrong.

Not stored, and counted rather than guessed at: 3 folio references that fit no location,
3 folios absent from our text, 7 refused volume groups, and 4 Tōhoku numbers that are
Tengyur texts this corpus does not hold.

**A folio-anchored rendering is reachable from a line.** `Translations.covering/2` finds
renderings whose anchor *contains* a span, and `select/2` falls back to it when nothing
matches exactly — so asking for `@51.100a.3` returns the folio's English, labelled
`covers: :containing_range` and carrying its own wider `anchor_urn`. Containment is by
**segment ordinal**, recorded on the rendering at ingest, because whether `51.100a.3` lies
inside `51.100a.1-51.100a.7` is a fact about Derge folios while ordinals mean the same
thing in every source. The exact-match path is unchanged: a Pāli rendering anchored to
its own segment id still matches exactly and carries no `covers`.

### Chunk sizes are a tokenizer question (#21) — and the Pāli was answering it wrong

Chunking the Tibetan meant choosing a chunk size for it, and the note in the last session
said to measure rather than guess. Measuring found that **the Pāli size had been wrong
since #40, and invisibly so**.

The embedder runs BGE-M3 at `max_length=320` with `truncation=True`. A chunk over that is
embedded **from its opening only**: the text stays whole in the database, the vector
silently describes a prefix, and every count in the system still agrees. Measured over
real chunks of each script with the actual tokenizer:

| script | chars | tok p50 | tok p95 | over 320 |
|---|---|---|---|---|
| Literary Chinese | 300 | 277 | 291 | 0.0% |
| Pāli | **1,200** | 461 | 535 | **76.2%** |
| Pāli | 700 | 258 | 307 | 0.5% |
| Tibetan | 1,200 | 206 | 266 | 0.3% |
| Tibetan | 1,400 | 242 | 309 | 3.2% |

**Three quarters of the Pāli vectors described about the first two thirds of their
chunk.** Pāli recall@10 is 37.5% against Chinese at 98.7% (#19), and this is a plausible
mechanical contributor — the vectors were built from truncated text while the eval scored
against the whole. Sizes are now the largest whose 95th percentile fits the window: Pāli
700, Tibetan 1,200. Tibetan costs 0.151 tokens per character against Pāli's 0.425, which
is why the same window holds so much more of it.

**Re-chunking the Pāli then hit a defect that had been there all along.** SuttaCentral
numbers a merged section `53-55.1`, so the hyphen is inside the locator as well as being
the character this grammar joins two locators with. `URN.parse/1` split it, and the chunk
builder — which built its range URN from *parsed* locators — emitted `mn12@53-53`: an
address naming a segment that does not exist, identical for every chunk in the section,
and a unique-index violation the moment two landed in one insert. **412 chunks in the
corpus were addressed that way and none of them resolved.** Range URNs are now built from
the raw locator text, and `Pramana.Corpus` resolves a range it cannot split by looking the
URN up as a stored chunk — identity answering what arithmetic cannot.

Two more things the re-chunk forced:

- **`mix pramana.chunk --source`.** `--force` discards the vectors of every text it
  touches, and the corpus holds 299,317 Chinese vectors that cost GPU time. "Re-chunk the
  Pāli" must be sayable without putting those in the blast radius; narrowing a destructive
  operation is not a convenience. (Found the hard way: a `--force` run without it had
  already discarded 527 Pāli vectors before failing.)
- **Translation vectors could not see a range-anchored rendering.** The builder joined
  `translations.anchor_urn` to `segments.urn` by equality, and all 30,653 84000 renderings
  are anchored to folio ranges — so Tibetan would have had no English route into it at
  all. The join now also accepts renderings carrying `ordinal_start`/`ordinal_end`, and
  coverage is counted over the chunk's own segments so two overlapping folios cannot claim
  more of it than it has.

### What the Tibetan measured (#21) — and the two hypotheses it refuted

The Kangyur is embedded and the evals now cover three traditions. **The gold set could
not see Tibetan at all until it was fixed**, and that is the finding worth keeping:

- `mix pramana.evals.derive` joined `translations.anchor_urn` to `segments.urn` by
  equality — the **third** place that join has been wrong — so it found none of the
  30,653 range-anchored 84000 renderings and generated zero Tibetan cases, while
  hardcoding `tradition: "pali"` on everything it did generate. Tibetan would have been
  reported as *not measured* rather than measured and weak, which is the more dangerous
  of the two.
- Cases are now sampled **per tradition** (20 Pāli, 20 Tibetan, 35 Chinese), the tradition
  comes from the data, and a case is admitted only if its anchor resolves.
- Rule 18 arrived from the other side. Where the Pāli's SOURCE repeats verbatim, the
  Tibetan's TRANSLATION does: "Homage to all buddhas and bodhisattvas. Thus did I hear at
  one time." is the published English of **102 separate anchors**, over Tibetan that is not
  byte-identical because each names its own sūtra. Identical renderings now count as one
  equivalence class.
- Nine Tibetan topical cases, with the terms adjudicated by the corpus rather than
  asserted: of twelve proposed, three were rejected as too common to measure
  (ཤེས་རབ་ཀྱི་ཕ་རོལ་ཏུ་ཕྱིན་པ at 19,099 segments, སྟོང་པ་ཉིད at 20,500,
  མྱ་ངན་ལས་འདས་པ at 4,242) and **none as absent**.

**The numbers**, 249 cases, overall 79.5% (the run written as the new baseline; a
second run of the same build put topical/pali at 62.5%, which is the one-case wobble the
README already documents):

| | | |
|---|---|---|
| retrieval / chinese | 97.1% (34/35) | unchanged |
| retrieval / pali | 55.0% (11/20) | new sample |
| **retrieval / tibetan** | **35.0% (7/20)** | first measurement |
| topical / chinese-native | 100% (12/12) | unchanged |
| topical / pali | 56.3% (9/16) | was 75% |
| topical / chinese | 0.0% (0/12) | unchanged — no English layer |
| **topical / tibetan** | **0.0% (0/9)** | first measurement |
| quote verify / reject / provenance / absence | 100% | unchanged |

**Topical Tibetan is 0% for a structural reason, not a retrieval one.** 84000 has
published 385 of ~1,169 Tōhoku numbers, so **95% of the Kangyur has no English vector at
all** and an English topical question can only reach the twentieth of it that does. It is
the same shape as the Chinese 0%, with a different cause: Chinese has no English layer,
Tibetan has one over a twentieth of the text.

**Two hypotheses for the Pāli topical drop, both refuted by measurement.**

1. *The Tibetan English layer displaces Pāli.* This is what #44 predicted and what the
   first English demonstration looked like. Measured over the 16 topical/pali queries:
   **Tibetan occupies 1 of 160 result slots.** It is not displacing anything. (The same
   experiment confirms the English layer is what makes English→Pāli work at all: with
   `vector_kinds: ["source"]` the rate collapses to 1/16.)
2. *The smaller Pāli chunk returns a window too narrow to contain the term.* Scoring
   containment over the chunk **± 3 segments** — the passage a reader would actually see —
   gives **10/16 either way**. The retriever is not landing near the term and being cut
   off; it is not landing there.

What remains is the chunk size itself: 700 characters covers less ground than 1,200, and a
broad topical question is answered by breadth. That is a real trade — **anchor-precise
retrieval up, topical recall down** — and it is not an argument for reverting, because
1,200 was never honestly embedded: 76% of those vectors described two thirds of their
chunk. The honest alternative is to raise the embedder's 320-token limit for the alphabetic
scripts and keep the wider window, paying for it in GPU time. Untested.

**Under #44's rule the Tibetan layer stays a default**: it was measured against
answered-from-any-tradition before shipping, and the drop there (9/11 → 8/11 topics) is
attributable to the Pāli chunk change, not to Tibetan taking slots.

### The Kangyur has its names (#21) — and the metadata is CC0 where the text is not

**1,189 of 1,195 Kangyur works now carry a title**, up from 478, in English, Sanskrit and
Tibetan, with a Wylie transliteration and a BDRC identifier. From 84000's RDF export:
1,254 records covering 1,160 Tōhoku numbers, translated or not.

**The licence is not the one on the repository.** `data-rdf`'s README says CC BY-NC-ND —
the terms for the translations — while every record's own `adm:license` says `LicenseCC0`
with the label "Metadata related to the translations by 84000, provided under the CC0
License". Both are true of different things: the prose of a translation is restricted, the
fact that Toh 113 is called *Saddharmapuṇḍarīka* is not. Recorded as its own source,
`84000-rdf`, because it is its own publication — the same rule bilara-data forced, where
the repository claimed CC0 and the publication file said Public Domain Mark and CC BY-SA.
**This is the first CC0 content in the corpus.**

**Four descriptions of one text, each holding a different title.** A record describes the
abstract Indic work, the Tibetan translation, the Degé printing of it, and 84000's
English — so the Tibetan title is taken from the Degé printing, which is the edition this
corpus holds, and the Sanskrit from the Indic work. Reading any `skos:prefLabel` with the
right language tag would have attributed the printing's title to the Sanskrit original,
and a translator's name — which is also a `prefLabel` — to the sūtra.

A published title is never overwritten: where a translation exists, its own title page is
the better authority and was already stored, so the catalogue fills only what was empty
and records which source each title came from.

**The Wylie is computed, and checking it against 84000's own found two bugs.** The RDF
carries no transliteration, so `Pramana.Readings.Wylie` produces one from the Tibetan and
it is stored under a separate key — a claim by this code must be distinguishable from a
claim by the editors. 476 works have both, which makes an independent check possible:

    before   452 / 476 agree   (94.9%)
    after    454 / 476 agree   (95.4%)

Two real defects, both in constructions that are everywhere in Tibetan:

- **`བའི` came out `b'i`, not `ba'i`.** The rule "an explicit vowel sits on the root" is
  right for བདེ → `bde` and wrong for an *a-chung* suffix carrying the genitive: the བ
  keeps its implicit *a* and the འ takes the ི. That is most of the particles in the
  language — པའི, མའི, པའོ — and it was wrong in every one.
- **`ཤཱཀྱ` came out `shAkya` only after** recognising that a non-root stack carrying a
  SUBJOINED letter is a syllable of its own rather than a suffix; a suffix is always a
  single letter.

The 22 remaining differences are characterised rather than chased: about half are
genuinely different titles (the catalogue and the translation's title page name the text
differently, e.g. `spyan ras gzigs yum` against `spyan ras gzigs dbang phyug gi yum`), one
is 84000 storing Tibetan script in a Wylie field, and the rest are Sanskrit conjunct
notation (`kul+le` against `kulle`) and the `dags`/`dgas` prefix-root ambiguity, which
cannot be resolved without a lexicon. Six works stay untitled: five sub-parts of Toh 845
and one lettered variant, where the etext divides more finely than the catalogue.

Each record also carries the BDRC id of the Degé printing (`MW22084_0113`) — the handle a
IIIF manifest is addressed by, which is the catalogue half of the Phase 5 BDRC item, with
no OCR involved.

### The woodblock page, linked (#21) — and why the arithmetic had to go

A Derge passage now comes back with the photograph of the leaf it was printed on.
**64,828 of the corpus's 65,778 folio anchors — 98.6% — resolve to a BDRC page image**,
served over IIIF, attributed, and never copied or read. `get_passage` carries it as
`page_image`; a folio with no scan gets nothing rather than a neighbour.

**The mapping is BDRC's, and reading it replaced an inference that looked right.** The
obvious construction is arithmetic: two cataloguing cards, then folio *n* recto at leaf-side
2n−1, image name `<group><NNNN>.jpg`. It was built that way first, and the audit that
checked it against all 103 volumes said: 74 fit, **29 claim more leaf-sides than the scan
contains**. Volume 7 settles it — the etext prints folios 1a–287b, BDRC's canvas labels run
1a–287b, and there are **536 canvases where contiguous sides would need 574**. Sides are
missing from the middle of the scan, and nothing computable from a filename could know
which. A single omitted leaf silently shifts every page after it, so the reader is shown a
leaf that is *almost* the right one — the failure this project exists to prevent, arriving
as a photograph.

BDRC publishes the answer: every canvas is labelled with its folio (`1a`, `img. 3`, `1na/`,
`par grangs _3`). So the manifests are fetched and the labels read, which is invariant #2
applied to pictures — adopt the edition's own reference system, never invent one. The
proof it mattered is one line: `51.100a` is image **202**, and the arithmetic said 201.

Also settled here:

- **The volume-to-image-group mapping is derived, not assumed.** The group is in the
  etext's own directory name (`UT4CZ5369-I1KG9127`) and BDRC's record for that group
  confirms it says *"Volume 1 of bka' 'gyur (sde dge)"*. The ids do run consecutively from
  9127, and that is a coincidence of issue order rather than a fact to rely on.
- **The Degé restarts foliation inside a volume.** Volume 31 holds two texts numbered
  1–206 and 1–91, so `31.1b` names two different leaves and is disambiguated only by the
  work in the URN. Two volumes are like this. It does not affect the image lookup now that
  labels are read rather than counted, but it means a bare "D vol 31, f. 1b" is ambiguous
  in this edition.
- **The licence is the scan's, not the metadata's.** What is stored is BDRC's manifest —
  what exists and what it is called. The images stay at BDRC, are linked with attribution,
  and are never redistributed or read.

### The translators' own glossaries (#21) — Skt–Tib–Chi anchors, attested

Phase 5's last bullet asked for Mahāvyutpatti and 84000 glossary entries as Skt–Tib–Chi
anchors. The 84000 half was already in `raw/`: every translation ships with the
translator's glossary, and there are **58,820 entries across the published Kangyur**.

**56,382 stored: 41,253 with Sanskrit, 55,807 with Tibetan, 1,105 with Chinese, 41,480
with a definition — 16,741 distinct Sanskrit terms and 25,524 Tibetan.** Of those, **865
carry all three languages**: `dharma` / `ཆོས།` / `法`, `bodhisattva` / `བྱང་ཆུབ་སེམས་དཔའ།` /
`菩薩摩訶薩`, made by the people who did the translating rather than assembled by matching
strings.

**They work as anchors.** Sampled 60 of the three-way entries against the corpus itself:
the Chinese term occurs in the Taishō for 59 and the Tibetan in the Kangyur for 60 — **59
reachable in both canons at once**. The miss was a proper name the Chinese transliterates
differently, which is the expected shape of the failure.

**Most of the Sanskrit is a reconstruction, and the table says so per term.** 84000 marks
each form: Tibetan `attestedSource` 23,252, Sanskrit `sourceUnspecified` 22,442, Sanskrit
`attestedSource` only 575 in the sampled files (2,783 across the whole ingest). `yūpa`
beside `མཆོད་སྡོང་།` is a scholar's inference about a lost Indic original, not a quotation
from one, and storing the two identically would flatten that into a claim the edition does
not make — the same failure `composition_origin` prevents one layer up. `attested_only:
true` narrows a query to what a witness says, and the attestation is on every row returned
so a caller who never asks still cannot mistake one for the other.

**2,756 Sanskrit terms are rendered by more than one Tibetan**, and nothing here picks a
winner. `parivrājaka` appears as `ཀུན་ཏུ་རྒྱུ་བ།`, `ཀུན་དུ་རྒྱུ།` and — in one text —
transliterated rather than translated, `པ་རི་པ་ར་ཙ་ཀ`. `TermAnchors.renderings/2` returns the
set with how many texts chose each, which is the refusal `Pramana.Translations` makes about
whole passages, one word down. It is also Phase 6's translator-divergence measurement
arriving early and for free.

Stored apart from `glossary_terms` on purpose: that table is a **policy** (376 hand-pinned
renderings for one Chinese commentary, answering *what should this be called*), this one is
**evidence** (*what did this translator call it, in this text*). Merging them would put a
decision and an observation in one row and lose which was which.

**What is still missing:** the Mahāvyutpatti proper. It is Toh 4346 — in the Tengyur, which
this corpus does not hold — so the imperial lexicon itself waits on that acquisition.

### The reading dictionary (#24) — the Buddhist readings were already in Unicode

The task was scoped as "a general pinyin library gets Buddhist vocabulary wrong, so build
a dictionary of the exceptions." That framing turned out to be half right in a way worth
recording.

Unihan's `kMandarin` — the field a per-character library reads — gives **佛 as *fú***.
佛 occurs 533,670 times in the canon and is *fó*; the *fú* reading exists because 佛 is
common in 仿佛 *fǎngfú*, and kMandarin records the commonest reading, not the right one.
So the single most frequent character in Buddhist Chinese is misread half a million times
by any method that reads characters one at a time.

But `kHanyuPinyin` lists 葉 as `yè, shè`. `kXHC1983` lists 若 as `rě`. 般 is `bān, bō`.
**The Buddhist readings are in Unicode already** — spread across four fields nobody
consults. Nothing needed inventing. What needed recording is *which attested reading
applies to which form*, which is exactly what an exception table is, and it turned the
integrity rule into something checkable: **every syllable of every asserted reading must
appear in that character's attested set**, or it does not ship. The hand-curated file is
checked the same way, and an unattested syllable fails the build rather than entering the
corpus as a fact.

Result: 9,543 exceptions over a 44,348-character base, from two independent sources that
agree on 96.8% of compounds. On a 46-form test set covering 1,751,507 corpus occurrences,
per-character scores **50%**, the dictionary **100%**, breaking none of the 23 controls.

**Half the test set is forms the naive method gets right.** A set of only hard cases
would show that the dictionary fires, not that it fires in the right places — and a
dictionary that "corrected" 菩薩 or 涅槃 would be worse than none.

Four filters, each added because the unfiltered output contained that mistake:

1. **Polyphone ambiguity** (1,168 characters skipped). 說 is *shuō*, *shuì* and *yuè*;
   picking one without context is the guessing this table replaces. 佛 survives only
   because its other reading is glossed "used in 仿佛" — a fact about one word, not about
   the character.
2. **Neutral-tone erosion** (2,957 rejected). CC-CEDICT records modern *spoken* Mandarin,
   where 知識 is *zhī shi*. Twentieth-century speech is not evidence about a
   seventh-century text.
3. **Cross-source attestation** (401 rejected). The filter that makes the result
   trustworthy rather than merely sourced: two independent authorities have to agree.
4. **Corpus occurrence** — measured, not enforced. 3,172 of 9,543 forms occur in CBETA,
   covering 1,927,240 occurrences. Scoping the artifact to today's corpus would make it
   wrong the moment a corpus is added.

**And the parameter limit for the fourth time.** `Pramana.Batch` was extracted after the
second and documented after the third, and `Readings.store/1` still blew up — because it
had no batching at all and had simply never been handed enough rows to notice. Offering
`chunk/1` leaves every call site free to forget. `Batch.insert_all/4` takes the same
arguments as `Repo.insert_all/3` and cannot be called without batching; every unbounded
write path now goes through it, including two that were latent (`Parallels.store_anchors`
unbatched, `Parallels.store` with a hardcoded 5,000). **A shared helper only helps if
using it is easier than not.**

One more, on shape of work rather than data: the corpus-occurrence check was first
written as `LIKE '%form%'` per form against the pg_bigm index. It measured **1.3 seconds
each** — because proving a form is *absent* is the expensive case — which is 3.6 hours for
13,000 forms. One streaming pass over the corpus answers the same question in 2m11s.
Index-per-item beats a scan only when the items are few.

### The Tengyur (#21) — the release that says nothing about works

The Tengyur has an official TEI release and it is unusable for this. Counted across all
212 files:

| | line milestones | work milestones |
|---|---|---|
| Kangyur TEI | 460,539 | **1,208** (`unit="text"`) |
| Tengyur TEI | 888,576 | **0** |

Every Tengyur milestone is `unit="line"`, and each file holds exactly **one** `<tei:div>` —
the whole volume as one undifferentiated block. The encoding knows where every line break
falls and nothing at all about where one work ends and the next begins. Its own header says
it was generated from the plain text by a script; the script did not carry the work markers
across.

That is not merely incomplete, it is unciteable. A URN here is
`pramana:<source>.<witness>:<work>@<locator>` and the work is a required component, so a
line-only encoding yields an address with no building: 891,169 lines of real Tibetan,
every citation resolving, none of them able to name what it quotes. The plain text carries
**3,380 `{D…}` markers, 3,380 distinct** — exactly one per work — so that is what
`Pramana.Normalize.DergeTengyur` reads. Checked before writing a line of the normalizer,
not after.

Three things the format forced:

- **The volume number is in the filename**, `079_རྒྱུད་འགྲེལ།_ཚུ.txt`, because the plain text
  has no title page to print it on. `mix pramana.verify` therefore needs a per-format rule
  for where a volume's number lives: the Kangyur's TEI is asked, the Tengyur's path is
  parsed. Taking it from the *order* of the recorded paths would have reproduced a text
  whose anchors agree with themselves and with nothing printed.
- **What the woodblock prints is what enters the text.** The editors' modern spellings
  `{མི་,མེ་}`, suggested corrections `(བཟད་,བཟང་)` and Pedurma note marks `#` are all
  recorded as apparatus beside the printed reading, never in place of it. A normalizer
  that silently accepted the corrections would produce a text no edition contains, and
  every citation into it would still resolve — the exact failure mode this project exists
  to prevent.
- **Volume 213 is 0 bytes.** It is the དཀར་ཆག, the catalogue volume, published empty in
  this release. The walk halted on it, correctly: a volume that yields no works is how a
  broken normalizer looks. The fix distinguishes an empty *file* (counted as `empty`,
  skipped) from a volume with bytes that yields nothing (still halts). Making the walk
  tolerant of both would have hidden the failure it was written to catch.

**The lockfile verified nothing, and said it was fine.** All 213 Tengyur entries recorded
absolute paths on one machine — `/Users/…/raw/tengyur/text/001_….txt` — so
`Lockfile.verify("derge-tengyur")` failed on every one of them while the Kangyur's 103
passed. The ingest code was already right and even carries a comment predicting this:
`Path.relative_to/2` returns the path **unchanged** when the prefix does not match, "which
produces a lockfile that looks right and verifies nothing." The cause was the layout.
`Lockfile.verify/1` resolves each recorded path against `raw/<source_id>/`, and this
source alone sat at `raw/tengyur/` while its id is `derge-tengyur`, so the prefix never
matched and every path passed through untouched. Moving the raw to `raw/derge-tengyur/`
fixes it, but the recorded `source_file` on each text moves with it, so the re-ingest is
required rather than cosmetic — and it is the re-ingest that proves the point: 3,380
works and 891,169 segments again, and the 52,371 already-computed vectors re-imported
with **0 hash mismatches**, which is independent evidence that the chunk content did not
move when the files did.

The general rule, now that it has cost two runs: a check that resolves paths by convention
must have the convention enforced where the path is *written*, because the failure mode is
a green checkmark. Nothing errored. `verify` passed, `integrity` passed, the bake was
byte-identical — and the provenance record pointed at one laptop.

**And it was not the only one.** The fix prompted a check that runs `Lockfile.verify/1`
over *every* source rather than the one just touched — now step 3 of the data-integrity
gate in `docs/CHECKS.md` — and it caught the **Pāli canon failing on all 7,288 files**.
Different cause, identical consequence: `pramana.sc.ingest` recorded paths relative to the
checkout root, `raw/sc/bilara-data`, so every path lost its `bilara-data/` prefix and
resolved to `:enoent`. The provenance record for 8,442 works had verified nothing since
#38 and nothing said so. Six of the eight sources were clean (`84000` 406, `84000-rdf`
1254, `bdrc-derge` 103, `cbeta` 2471, `derge` 103, `derge-tengyur` 213); `sat` is
correctly `:not_locked`, never having been acquired. **Check the sources you did not
touch** — the defect lives in how a path was written, and it is invisible from the side
that reads it back on the same machine.

**And `integrity` immediately earned it — it caught a defect `verify` could not.** The
first Tengyur bake passed `verify` byte-identically and FAILED `integrity`: `toh4100`
(raw 5583, bake 5582) and `toh4150` (raw 1873, bake 1872), each missing exactly one line.
Where one work ends and the next begins mid-line the page reads `[222b.1]#{D4101}#༄༅༅།…`,
so splitting on the marker hands the ENDING work a fragment containing only the `#`.
`extract/1` strips that into an apparatus entry, leaving `text: ""`, and `emit/5` kept the
line because its apparatus was not empty. Three components then disagreed about one
boundary artifact: the normalizer promised a line, the loader refused it (a segment with
no content is not citable), and `integrity` reported the difference. The mark annotates
the printed line, which belongs to the work that STARTS on it and is recorded there, so a
fragment with no printed text is no longer emitted at all. After the fix the ingest reports
`lines: 891169, segments: 891169` — previously 891171 against 891169, exactly the two
phantom lines.

This is the whole argument for running both checks, made concrete: a pipeline that drops
the same content every run drops it identically on both sides of a re-normalization
comparison, and `verify` passes. Reproducibility is not fidelity.

**`integrity` is weaker here than for the Kangyur, and says so.** The Kangyur gets an
independent byte census: a separate counter walks the TEI `<text>` element and totals
character data without knowing anything about folios, which is what catches content the
normalizer drops silently. Plain text has no such envelope — its markup *is* its text — so
no second, independent count of it exists. The Tengyur is covered by per-work
addressability and by byte-identical re-derivation instead. Reproducibility and fidelity
are different questions (`docs/CHECKS.md`), and for this half of the edition the second is
answered less strongly. Documented rather than papered over.

The Tengyur is loaded as `treatise`, not `root` — provenance is per collection, and
calling Vasubandhu the Buddha's word by inheriting the Kangyur's text role would be a
category error the citation would carry forever.

Two per-source settings had to move with it, neither of which fails loudly. Chunk size is
`1_200` for both halves because they are the same script; a source missing from
`@max_chars_by_source` takes the **Chinese 300**, a fifth of the window, and would have
under-chunked 891,169 segments without an error. Language is `"bo"`; a source missing from
`@lang_by_source` takes the **`lzh` default**, and that field is what `matched_via`
reports, so every Tibetan vector would have named the wrong language. Both are now
asserted in tests, because the defect class here is silent correctness, not breakage.

### Pāli takes 193 of 200 slots, and that is why two topical rows are 0% (#19)

`topical/chinese` and `topical/tibetan` both score **0%**, and the obvious reading — the
corpus cannot answer — is wrong for Tibetan. Asked "What are the four noble truths?", the
semantic arm returns:

| depth | sources | first Tibetan |
|---|---|---|
| k=30 | `sc.ms` 30 | — |
| k=200 | `sc.ms` **193**, `cbeta.T` 5, `derge.D` 2 | **rank 142** |

The Tibetan passages exist and are eligible: **250 chunks** contain འཕགས་པའི་བདེན་པ་བཞི *and*
carry an English rendering vector (276 for dependent origination, 229 for the five
aggregates, 446 for bodhicitta). They are retrievable — just buried under a canon whose
English is a more direct statement of the same doctrine. All 55,135 English rendering
vectors compete in one space.

That explains the topical picture as one mechanism rather than three problems:
Pāli 56.3% wins its own cases; Tibetan 0% loses the same competition; Chinese 0% has no
English layer and never competes (#12).

**`balance: :tradition` does not fix it — measured.** With balancing the top 10 was one
Chinese and nine Pāli, still zero Tibetan. `balance` interleaves the traditions *present in
the retrieved pool*, and at `depth = limit * 3 = 30` that pool is 100% Pāli. It is a
ranking remedy for a retrieval problem — **it operates one stage too late.** The module's
own moduledoc calls balancing "the right behaviour for a topical question", which is true
of the intent and not achieved by the implementation. The fix is to retrieve per tradition
and merge, so every canon is represented *before* ranking.

**A correction this produced.** An earlier probe reported "30 of 41 misses absent from top
500". `Semantic` has `@max_limit 200`, so `limit: 500` silently returned 200 — the figure
was absence from top **200**. The conclusion stands; the label was wrong.

### Per-tradition retrieval, decided on the full set (#19) — it stays opt-in

The open question from the previous session: `per_tradition: true` was implemented and
committed opt-in, and the decision — whether topical queries should default to it —
needed the gold set. **1,400 cases, 3h09m, 0 stale**, against `evals/baseline.json`:

| | baseline | per_tradition | |
|---|---|---|---|
| retrieval / chinese | 97.8% (227/232) | 97.8% (227/232) | unchanged |
| **retrieval / pali** | 53.3% (80/150) | **42.7% (64/150)** | **−16 cases** |
| **retrieval / tibetan** | 31.3% (20/64) | **21.9% (14/64)** | **−6 cases** |
| topical / chinese | 0.0% (0/12) | 0.0% (0/12) | unchanged |
| topical / chinese-native | 100% (12/12) | 100% (12/12) | unchanged |
| topical / pali | 56.3% (9/16) | 37.5% (6/16) | −3 cases |
| **topical / tibetan** | **0.0% (0/9)** | **22.2% (2/9)** | **+2 cases** |
| **answered from any canon** | **72.7% (8/11)** | **54.5% (6/11)** | **−2 topics** |

**It buys 2 topical cases for 22 pinpoint ones, and makes the user-facing number worse.**
So it stays opt-in. The moduledoc had asserted it was "wrong for find-the-passage-I-quoted,
where the tradition is not in doubt"; that is now a measurement rather than a claim, and
the trade is about 11:1 against.

**The row that teaches something new is `retrieval/tibetan`, 31.3% → 21.9%.** Per-tradition
retrieval *guarantees* Tibetan a third of every result set, and Tibetan pinpoint retrieval
got **worse**. Giving a canon more slots can only help if its internal ranking can use
them — and #10 measured Tibetan's mean pairwise cosine at 0.9727, so within-Tibetan ranking
is near-random. The slots get filled with near-ties, and correct answers that were scraping
into the top ten on the strength of cross-tradition competition fall out. This is the
embedder bound showing up from a new direction: not as a ceiling on what Tibetan can reach,
but as a *cost* to giving Tibetan more room.

**`retrieval/chinese` is unchanged to the case**, 227/232 both ways. Chinese never faced
competition it could lose, so isolating it changes nothing — the same reason `topical/chinese`
stays 0/12 with guaranteed slots. For Chinese the monopoly was never the binding constraint;
the missing English layer is (#12, #43). The 0%/0% pair in the topical rows had two different
causes all along, and this separates them.

**Do not quote the overall 89.5% → 87.9%.** Both runs score the same 1,400 cases, so it is
comparable — but it is dominated by the 901 guard and provenance cases at 100%, which this
change cannot touch. The per-tradition rows are the measurement; the aggregate only dilutes
them.

**`evals/baseline.json` was NOT updated.** An experiment is not the ratchet, and writing a
non-default configuration into the baseline would silently redefine what every future gate
compares against.

Three defects found while getting to this number, all of which would have corrupted it:

- **`per_tradition` was unreachable from everything that ships.** `Semantic` accepted the
  option and `Hybrid` did not know about it, so `Hybrid.search(q, per_tradition: true)`
  raised from `Lexical.validate_opts!/1`. Every caller — the MCP tools, the eval harness —
  goes through `Hybrid`. The feature was measurable only by a probe calling `Semantic`
  directly, which is exactly how it had been measured.
- **The first run I did returned topical numbers identical to baseline on all four rows,
  and I nearly reported them.** They were baseline's numbers; the flag had not taken
  effect. What caught it was the identicality being too clean for a change a probe had
  already shown moves results. *A configuration flag that changes nothing is a claim about
  the flag, and it should be checked against the mechanism before it is believed.*
- **`mix pramana.evals --only topical` reported "ran 1400 case(s) ... 3.5 cases/s"** for a
  run that scored 49 — it counted the loaded gold set, not the scored one. Every rate this
  project has published from that line was wrong by the ratio of the two.

### Retrieval depth is worth +7 cases and costs 5.4x (#10) — measured, not adopted

The probe above suggested fusion depth was worth real recall. It is, across every
tradition, and the price is the reason it is not simply switched on. All 446 `retrieval`
cases, depth 60 (the shipped default, `limit * 3`) against depth 200:

| | depth 60 | depth 200 | |
|---|---|---|---|
| retrieval / chinese | 97.8% (227/232) | **98.3% (228/232)** | +1 |
| retrieval / pali | 53.3% (80/150) | **54.7% (82/150)** | +2 |
| retrieval / tibetan | 31.3% (20/64) | **37.5% (24/64)** | **+4** |
| **overall** | 73.3% (327/446) | **74.9% (334/446)** | **+7** |
| **wall clock** | **~50 min** | **4h25m** | **5.4x** |

**Nothing regressed**, which is what the pre-registered rule required, and Tibetan's 24/64
has now been produced three independent times — the depth-200 probe, an isolated Tibetan
arm, and this full run. Read the per-row gains carefully though: **only Tibetan's +4 clears
the one-case ANN wobble on its own.** Pāli's +2 and Chinese's +1 are inside it and should
not be quoted as established; the aggregate +7 is what carries.

**The cost is the finding.** 35.6 s per case against ~6.6 s, which is *more expensive than
per-tradition retrieval* (22.7 s/case) despite running one scan instead of three. The
lexical arm is why: at depth 200 it pulls 200 segments out of a 4.7M-segment bigram index
and maps every one to its containing chunk, and the 232 Chinese definitional-formula cases
hit that hardest. As a default it would take the 1,400-case gate from about an hour to
about five, on a check meant to run at every phase gate.

So depth ships as an **option**, not a new default. The middle was then measured, over the
same 64 Tibetan cases:

| depth | retrieval / tibetan | mean rank |
|---|---|---|
| 60 (default) | 31.3% (20/64) | 3.1 |
| **120** | **39.1% (25/64)** | 3.2 |
| 200 | 37.5% (24/64) | 3.0 |

**The whole gain arrives at depth 120.** 25 against 24 is one case, inside the ANN wobble,
so 120 and 200 are indistinguishable on recall and the extra 80 candidates buy nothing.

**The first wall clocks were cache weather, and an ABBA run replaced them.** Depth 120 had
timed at 13m12s against depth 200's 11m21s — backwards, since 120 does strictly less work.
Those arms ran hours apart, and this session already measured cache state moving
`coverage/1` by 5x. So the arms were re-run **back to back in one session, in ABBA order**
(60, 120, 120, 60) to cancel drift:

| arm | depth | recall | scoring time |
|---|---|---|---|
| 1 | 60 | 20/64 | 7m24s |
| 2 | 120 | 25/64 | 11m01s |
| 3 | 120 | **crashed** | — |
| 4 | 60 | 20/64 | 7m32s |

The two depth-60 arms agree to **1.8%**, which is what a usable cost baseline looks like
and what the earlier 5m16s figure was not. **Depth 120 costs 1.47x**, nothing like depth
200's 5.4x, and it carries the whole recall gain.

**And it is still not the default, because one arm in two died:**

    ** (DBConnection.ConnectionError) client timed out because it queued and checked out
       the connection for longer than 120000ms
       lib/pramana/retrieval/lexical.ex:296: Pramana.Retrieval.Lexical.run/4

A single **lexical** query exceeded the 120-second pool timeout and took the whole run with
it. Three things follow, and the last two matter more than the depth question:

- **A default that occasionally kills a multi-hour gate is not a default.** Depth 120
  sits on the edge of the timeout and which side it lands on depends on cache state.
- **The cost of depth is in the BIGRAM index, not in HNSW.** Every intuition here had been
  that depth buys vector-scan time; `lexical.ex:296` says otherwise, and it explains why
  the 232 Chinese definitional-formula cases dominated the 4h25m run. Tuning the vector
  side would have optimised the wrong half.
- **A lexical query can take over two minutes**, which is a live risk on the MCP surface
  and has nothing to do with evals. It is its own defect and its own task.

**This section previously ended "Both halves are now fixed". That was wrong**, and it was
written the same morning the `texts.body` fix landed, on the assumption that the 32x
speedup removed the timeout. It did not. A four-arm ABBA re-run afterwards timed out again
on the same line, and the real cause turned out to be the n-gram fallback — see *The
two-minute lexical query was 135 OR'd LIKEs* below. The claim is corrected rather than
deleted because the mistake is the instructive part: **a speedup measured on one workload
was assumed to fix a timeout observed on another**, and the two workloads were Chinese
phrase queries and English n-gram fallbacks, which share a line number and nothing else.

The same timeout is what killed the depth-200 arm hours earlier; that death was invisible
because a `grep` in the pipeline swallowed the error while the loop still exited 0. The
progress heartbeat added the same day earned itself immediately — the log shows
`10/64 · 1m12s` and `20/64 · 2m24s` before the crash, so the failure point is known rather
than guessed.

**A process note that cost hours.** This run produced no output for 4h25m, so "how far
along is it" was unanswerable and three ETAs were wrong — all extrapolated from a Tibetan
arm that turned out to be the *cheap* tradition. The gold files also load alphabetically,
so the expensive Chinese cases run first, which makes any linear projection from early
elapsed time wrong in the same direction. `mix pramana.evals` now prints a progress
heartbeat for exactly this reason.

### The slow lexical query was `texts.body`, and it was 32x (#10)

`lexical.ex:296` in the crash stacktrace was `Repo.all`, and what it was fetching was the
whole corpus body, repeatedly. The query joined `texts` and preloaded through the join:

    |> join(:inner, [s], t in Text, on: t.id == s.text_id)
    |> preload([_s, t], text: {t, [:work, :witness, :source]})

A join-preload ships **every** column of the joined row, `texts.body` included — the
entire normalized work — **once per matched segment**, and the query over-fetches
`limit * 5` rows before ranking in Elixir. Bodies average **27,218 characters** and the
largest is **13,279,028**, so a 20-result search pulled 100 bodies through shared
buffers to read a title and a licence class off each. **Nothing in the result path reads
`body`**: `Corpus.span_from_segment/1` wants `work`, `witness_id`, `source_id`,
`source.license_class`, `volume` and `meta`, and `Corpus.body/1` fetches the body itself
when offsets need verifying.

The fix is a separate preload query selecting every `texts` column except `body`, which
also loads each DISTINCT text once instead of once per row.

Measured against the full dev corpus (15,489 texts, 6.5M segments), five Chinese
formulae, each warmed then timed 5x, minimum taken — and run **ABBA** because this
session had already been burned by cache weather:

| query | join-preload | separate preload |
|---|---|---|
| 一切有為法 | 278 ms | 13 ms |
| 四聖諦 | 542 ms | 7 ms |
| 無明緣行 | 285 ms | 10 ms |
| 如是我聞 | 147 ms | 10 ms |
| 般若波羅蜜多 | 151 ms | 4 ms |
| **total** | **1403 ms** | **44 ms** |

The repeat arms landed at 1491 ms and 47 ms — 6% and 7% apart, so the 32x is real and not
weather. This is warm-cache; the 120-second timeout was a cold one.

Two things this teaches:

- **`preload` through a join is not free, and its cost is invisible at the call site.**
  The one-line idiomatic form is the expensive one, and it gets more expensive the
  larger the widest column in the joined table is. `select: struct(t, [...])` in a
  separate preload query is the cheap form — and it must be `struct/2`, not a `%Text{}`
  literal, which loses the binding and makes Ecto refuse the query outright.
- **A column list in a `select` is a drift surface.** A new `texts` column not added to
  it reads as `nil` with no error anywhere. The test asserts the emitted SQL names every
  `Text.__schema__(:fields)` entry except `body`, so adding a column and forgetting this
  list fails a test instead of silently blanking a field.

### One case may not kill the run (#10)

The same crash exposed a second defect, and this one is a rule the project already holds
everywhere else: *one malformed file fails one job, never the bake* (`CLAUDE.md`). The
evals harness did not honour it. `score_case/2` had no rescue, so a single
`DBConnection.ConnectionError` propagated out of `Enum.map` and took **4h25m of scoring
with it**, discarding every case already completed. It happened twice, and the first time
a `grep` in the pipeline swallowed the error while the loop still exited 0.

A crashed case is now its own outcome, `{:error, detail}`, and the loop continues.
The scoring rules follow from what an error actually is:

- **Not a miss.** A query that timed out is not the retriever failing to find the
  passage. Counting it as one publishes a recall regression that never happened.
- **Not stale either.** Stale means the gold set aged; an error means *we* broke. They
  are excluded from the denominator for the same reason and printed separately because
  the reader needs to know which one it is.
- **Never silent.** Errors get their own header line, their own section, a `[n ERRORED]`
  suffix on every affected row, and an `"errors"` key in `Score.to_map/1` so a JSON
  artefact carries the fact too. A rate over zero scored cases still prints as "no cases
  scored", not 0.0%.
- **`--gate` refuses to run at all** when any case errored. Errored cases are missing
  hits, so the ratchet would either report a regression that did not happen or — with no
  baseline on disk — *install* the under-measured run as the baseline every future run is
  compared against.

The last point is the one worth generalizing: making a long run fault-tolerant is only
half the job. The other half is making sure the shrunken denominator cannot be read as a
result.

### The two-minute lexical query was 135 OR'd LIKEs (#10)

The `texts.body` fix was 32x and did **not** fix the timeout. A four-arm ABBA re-run after
it died on the same line, so the cause was measured properly instead of assumed.

It is not the phrase stage. `:auto` runs the phrase first and falls back to n-grams when
the phrase returns nothing — which for a cross-lingual English query is *always*, since an
English sentence never appears verbatim in Tibetan source text. `ngrams/2` then windowed by
**grapheme at width 3** for anything not Tibetan, so a 145-character English sentence became
**135 distinct trigrams**, OR'd into one `WHERE`. `EXPLAIN` on the full corpus:

| stage | plan | est. cost |
|---|---|---|
| phrase — 1 pattern, 145 chars | Bitmap Index Scan on `segments_content_bigm_index` | 4,698 |
| ngram — 135 trigram patterns | **Seq Scan on segments**, 6,538,238 rows | 3,043,842 |

Past a tipping point the planner abandons pg_bigm and scans the whole table, testing one
substring per predicate per row. `LIMIT depth * 5` with no `ORDER BY` is what made it
*intermittent* rather than merely slow: the scan stops when it fills the limit, so runtime
depends on where matches fall in heap order. Depth 60 filled 300 in time; depth 120
sometimes failed to fill 600 inside the 120 s pool timeout.

**The cliff is selectivity, not a predicate count** — measured, having first assumed
otherwise. On one query the index survived 24 predicates; on another it was abandoned at
**10**. The difference is short common words, which is why the fix is one rule and not two:

- drop words under 3 characters — the exact analogue of the `@particles` list that already
  drops 之, 於, 者 from Chinese as "grammatical particles, not content". `to`, `at`, `in`,
  `on`, `by` are the same thing, and length says so without a dictionary.
- keep the **longest 20**. Length is a dictionary-free proxy for rarity, and rarity is what
  keeps the planner on the index. Longest-first held the index to 24 predicates on the
  query where first-20-in-order flipped at 10.

Verified over every alphabetic query in the gold set: **252 queries, 252 BitmapOr plans,
zero sequential scans.**

**This is the third instance of one defect.** The module already refuses jieba for Chinese
because "a single common character appears on nearly every line", and refuses grapheme
windows for Tibetan because `་པ་` matched 89.6% of segments. Latin script has the identical
pathology and nothing caught it, because `tibetan?/1` was the only script test and
everything else fell through to trigrams. The windows were simultaneously **useless** — a
Latin trigram is a fragment of no linguistic standing, and can only match the Latin-script
(Pāli) part of the corpus, so on a Tibetan question the whole lexical arm entered the
fusion as noise — and **expensive**, because 135 of them defeat the index.

**A known residue, left deliberately.** `the` is exactly at the length floor and survives.
It is the same shape as `་པ་`: a predicate that votes for nearly every Latin-script line.
Min-3 plus longest-20 is what was *measured* to keep all 252 gold queries on the index;
whether also dropping function words improves recall is an eval question, and `@particles`
is the precedent for fixing it if the eval says so.

### What the fix did to the depth question (#10)

The same four-arm ABBA, before and after. Two runs of four arms each, back to back, one
session per run:

| arm | depth | before | after |
|---|---|---|---|
| 1 | 60 | 20/64, 455 s | 20/64, 453 s |
| 2 | 120 | 25/64, 682 s | 25/64, 675 s |
| 3 | 120 | **24/62, 940 s, 2 ERRORED** | **25/64, 672 s, clean** |
| 4 | 60 | 20/64, 456 s | 20/64, 388 s |

**Arm 3 is the whole result.** It crashed the first session, lost 1 case the second, lost 2
the third, and ran clean the fourth. The two depth-120 arms now agree to **0.4%** where the
same pair previously differed by **38%** — the variance left with the timeout, which is
what a fix to an intermittent early-exit scan should look like.

Depth 120's recall gain is now reproduced a **fifth** time: +5 cases, 20 → 25, well clear
of the documented one-case ANN wobble.

**The cost ratio is 1.5–1.7x, and deliberately not quoted more precisely than that.** This
run's own control loosened: the bracketing depth-60 arms came in at 453 s and 388 s, 15%
apart, against 0.2% in the pre-fix run. Taking the depth-60 mean gives 1.60x; taking arm 1
alone gives 1.48x. The ABBA exists to expose exactly this, and the honest reading is a
range. Nothing above depends on it — both recall figures reproduced exactly, and arm 3
running clean is categorical rather than a timing claim.

**Depth 60 moved by nothing — same 20/64, same 453 s.** That is the right result twice
over: depth 60 never hit the timeout, so its runtime should not change, and the trigram
noise the fix removed was contributing no hits to lose.

### The n-gram fix, validated outside the language that motivated it (#10)

The fix changes the fallback for **every** alphabetic query, so validating it on Tibetan
alone and shipping would have been rule 37 again — a fix measured on one workload and
credited against another. Run at the shipped default depth, so the n-gram change is
isolated from the depth question:

| | baseline | after |
|---|---|---|
| retrieval / pali (150 cases) | 53.3% (80/150) | 54.0% (81/150) |
| topical / pali | 56.3% (9/16) | 56.3% (9/16) |
| topical / chinese | 0.0% (0/12) | 0.0% (0/12) |
| topical / chinese-native | 100% (12/12) | 100% (12/12) |
| topical / tibetan | 0.0% (0/9) | 0.0% (0/9) |
| **answered from any tradition** | **72.7% (8/11)** | **72.7% (8/11)** |

**Nothing moved.** The single Pāli case is inside the documented one-case wobble and is not
claimed as an improvement; what it supports is the absence of a regression on the largest
affected category. The word unit cost the Pāli nothing, so the morphological fuzziness the
trigrams provided was not carrying those cases.

`topical/chinese` staying at 0% was **predicted before the run**, and the prediction is
worth as much as the number: those failures are a missing English layer over the Chinese
canon (#43), not a lexical-fallback problem, and a fallback fix cannot create a layer. Had
that row moved, the standing explanation for the 0% would have been wrong.

Under #44's rule — any change must be measured against answered-from-any-tradition before
becoming a default — the fix qualifies: 72.7%, unchanged.

### Depth is per ARM: the gain is semantic, the cost is lexical (#10)

Depth 120 was measured at **~4x** on the full 446-case retrieval set, not the 1.5–1.7x the
Tibetan-only ABBA implied — rule 37 rediscovered by projecting a ratio from one workload
onto another, twice in one session. That killed depth 120 as a global default. But the
cost and the benefit turned out to live in *different retrievers*, which the single `depth`
knob could not express.

Three arms over the 64 Tibetan cases, **prediction written down before the run**:

| arm | config | predicted | actual | time |
|---|---|---|---|---|
| 1 | both 60 (control) | 20/64 | **20/64** | 298 s |
| 2 | semantic 120, lexical 60 | 25/64 | **25/64** | 465 s |
| 3 | lexical 120, semantic 60 | 20/64 | **20/64** | 303 s |

**Semantic depth carries the entire gain; lexical depth carries none of it.** And lexical
depth is nearly free *here* — 303 s against a 298 s control — because a Tibetan gold query
is English, so the lexical arm has little to return however deep it looks.

The asymmetry has a mechanism on both sides:

- **The cost is lexical, and it is Chinese.** A definitional-formula query matches thousands
  of segments, so `limit * 5` over-fetch at depth 120 pulls 600 segments out of the bigram
  index and maps every one to its containing chunk — per-segment work scaling directly with
  depth, over the 232 Chinese cases that dominate the run.
- **The benefit is semantic, and it is Tibetan.** BGE-M3 packs Tibetan into a narrow cone
  (0.9727 mean pairwise cosine), so its candidates are near-ties and the right chunk sits
  deeper in the ranking. Looking further down is exactly what helps.

So `semantic_depth` and `lexical_depth` override `depth` per arm, both defaulting to it.

**The Tibetan probe's 1.56x did not transfer either.** On the full retrieval set,
semantic-120 with lexical pinned at 60 tracks **~2.3x** — better than global depth 120's
~4x, and nowhere near the cheap win the Tibetan arm implied. Deepening the *semantic* arm
is not free on Chinese: an iterative HNSW scan over 617,038 vectors asked for 120
candidates instead of 60 costs real time, and that lands on all 232 Chinese cases whether
or not they benefit. **Three times in one session a ratio measured on one workload failed
to transfer to another**, the third time after rule 37 had already been written down. The
rule is evidently easier to state than to obey; what actually catches it is running the
other workload.

So the trade is **2.3x across 446 cases to gain +5 cases that exist only in the 64 Tibetan
ones**.

**Decision rule, pre-registered before the full-set numbers were seen** — because three
wrong predictions in one session is exactly the condition under which a criterion invented
afterwards becomes a rationalisation:

- **Ship as default** only if `retrieval/tibetan` ≥ 24/64 **and** `retrieval/chinese` ≥
  226/232 **and** `retrieval/pali` ≥ 80/150. The tolerances are one case each, which is the
  documented ANN wobble; two is a real regression under the project's own gate rule.
- **Refuse** on any category down two or more, regardless of what Tibetan does. Chinese and
  Pāli are 382 of the 446 cases, so a genuine regression there outweighs +5.
- **Cost is not a veto for the retrieval default, but it is for the gate.** 2.3x on a
  1,400-case check meant to run at every phase gate is not acceptable. If this ships, the
  gate and the product run different depths — and that tension must be recorded rather than
  quietly resolved, because a gate that does not measure what ships is measuring the wrong
  thing.

**The rule was met on all three criteria, and it ships.** 446 cases, 0 errors, 1h50m:

| | old default | semantic 120 / lexical 60 | criterion |
|---|---|---|---|
| retrieval / chinese | 227/232 | **227/232** | ≥ 226 ✓ |
| retrieval / pali | 81/150 | **82/150** | ≥ 80 ✓ |
| retrieval / tibetan | 20/64 | **25/64** | ≥ 24 ✓ |
| **overall** | 328/446 (73.5%) | **334/446 (74.9%)** | |

Chinese did not move by a single case, which is the result that mattered most: it is 232 of
the 446, and a regression there would have outweighed the Tibetan gain outright. The Pāli
+1 is inside the wobble and is not claimed.

**334/446 is exactly what depth 200 scored** (74.9%, recorded above) — at **1h50m against
its 4h25m**. Depth 200's entire price was being paid by an arm contributing none of its
gain. That is the finding worth keeping from the whole depth investigation: *the question
"how deep should we look" had no single answer because it was two questions*, and three
sessions of ABBA arms went into tuning one knob that turned out to be two.

Shipped as `@lexical_multiplier 3` / `@semantic_multiplier 6` in `Hybrid`. An explicit
`depth:` still sets both arms, so nothing that passes one number changes meaning.

**Both consequences are now resolved, by a full run rather than an extrapolation.**

**The baseline is regenerated: 1,400 cases, 90.0% (1260/1400), 0 errored, 0 stale.** Run at
the shipped default with no experiment flags, so it measures what ships. The category diff
against the old baseline is the cleanest possible result:

| | old | new | |
|---|---|---|---|
| retrieval | 327/446 | **334/446** | **+7** |
| provenance | 300/300 | 300/300 | — |
| quote_verify | 300/300 | 300/300 | — |
| quote_reject | 301/301 | 301/301 | — |
| absence | 4/4 | 4/4 | — |
| topical | 21/49 | 21/49 | — |
| **overall** | **89.5%** | **90.0%** | |

**Retrieval is the only category that moved**, which is what a retrieval-depth change should
look like and is not guaranteed — #43 measured 1,665 gloss vectors displacing Pāli answers,
so a change rippling into another category is a real failure mode. The per-tradition figures
(chinese 227/232, pali 82/150, tibetan 25/64) reproduce the standalone 446-case run
**exactly**, from a separate execution.

**89.5% → 90.0% is a real +7 cases, unlike the last time this number rose.** When the set
grew 249 → 1,400 the average went 79.5% → 89.4% while nothing improved, because the mix
changed. Here the denominator is identical and only retrieval moved.

**The gate cost, measured rather than projected — and the honest figure is a range.** The
446 retrieval cases took **~2h23m** inside this run against **1h50m** for the same cases
standalone two hours earlier, and ~50 min at the old default. So the multiplier is somewhere
between **2.2x and 2.9x**, and the spread is not depth: the machine measurably slowed across
a six-hour session of continuous eval runs, with the Chinese block drifting from 24.9 s/case
to ~39 s/case. The full set now runs **3h08m** wall clock; the previously recorded "62
minutes" was CPU time and is not comparable.

That left a question that looked like a policy choice: a 3h gate is not something anyone runs
at every checkpoint, and running it shallower than the product means it stops measuring the
product.

**It was not a policy choice. It was a bug**, found within the hour — 38 of every 41 seconds
of a search were `texts.body` being shipped for nothing. See *A search took 41 seconds*
below. **The full gate now runs in 18m13s against 3h08m, a 10.3x speedup**, verified by an
actual `--gate` run: 1,400 cases, 90.0%, every row identical to baseline, `gate OK`.

Recorded here because the instinct to solve a cost problem with a sampling policy was wrong,
and would have permanently degraded the instrument to avoid profiling a query.

### A search took 41 seconds, and 38 of them were `texts.body` again (#10)

The whole day's work on the lexical arm was optimising **0.03%** of the query. Profiled
after the depth work, five Chinese gold queries, warmed:

| | before |
|---|---|
| lexical arm | **14 ms** |
| semantic arm | **41,142 ms** |

A 41-second search is a product defect before it is a gate problem — an MCP caller waits
that long for one `search` call. Splitting it further: the query embedding is **555 ms**
and the database is **~38 s**, while the equivalent ANN query in `psql` runs in **357 ms**.
So it was never HNSW, never `ef_search`, and never the iterative scan.

**It was `texts.body`, in the three places the morning's fix did not touch.** Captured from
Repo telemetry, the semantic path emitted:

- **the ANN select**, which selected the whole `Text` struct — `body` included — for every
  candidate row, and this query over-fetches `limit * @vector_overfetch`;
- **an N+1 of ~120 queries**, one per result, each ~200–300 ms, each a
  `preload([s, t], text: {t, ...})` through a join in `Corpus.between/4` — and each one
  dragging a whole work to build a range span.

120 × ~250 ms is the missing 30 seconds.

**Four call sites, one defect, and the rule did not prevent it.** Rule 34 was written this
morning after fixing exactly this in `Retrieval.Lexical`, and by the afternoon the same
pattern was still live in `Corpus.between/4`, `Corpus.context/2`, `Corpus.fetch_span/1` and
`Semantic.single_search/2`. Writing the rule down did not sweep for other instances, and
nothing made the next author's `preload: [text: {t, ...}]` look wrong.

So it is a **shared function** now — `Text.preload_without_body/0` and
`Text.fields_without_body/0` — for the reason `Pramana.Batch` exists: the 65,535-parameter
limit was hit, written up as rule 14, and then hit again in a fresh call site. A rule in a
document does not survive being reimplemented; a function does.

**And the field list is now derived, not written.** The morning's fix listed every `texts`
column explicitly and its own comment admitted the list was "a drift surface" — a column
added later and not listed would read as `nil` with no error. `__schema__(:fields) --
[:body]` cannot go stale, so the drift surface is gone rather than merely tested.

Measured after, same five queries:

| | before | after | |
|---|---|---|---|
| semantic arm | 41,142 ms | **3,395 ms** | **12.1x** |
| hybrid search | 41,169 ms | **2,242 ms** | **18.4x** |

**And the gold set says it changed nothing but the clock.** All 446 retrieval cases:

| | before | after |
|---|---|---|
| overall | 334/446 (74.9%) | **334/446 (74.9%)** |
| chinese | 227/232, mean rank 1.98 | **227/232, mean rank 1.98** |
| pali | 82/150, mean rank 3.09 | **82/150, mean rank 3.09** |
| tibetan | 25/64, mean rank 3.24 | **25/64, mean rank 3.24** |
| **wall clock** | **2h23m** | **17m22s** |

Mean ranks agreeing to two decimals is stronger evidence than the hit counts: not merely
the same passages found, but in the same order. `evals/baseline.json` therefore stays valid
— nothing it records moved.

**This retires the gate tension recorded above, by 10.3x.** Verified with a real `--gate`
run rather than projected: **1,400 cases in 18m13s against 3h08m**, 90.0%, every row
identical to baseline including mean ranks, `gate OK — no case type regressed`.

| | before | after |
|---|---|---|
| the 901 non-retrieval cases | ~28 min | **8 s** |
| the 446 retrieval cases | 2h23m | ~17 min |
| **full gate** | **3h08m** | **18m13s** |

**The non-retrieval half is the part nobody predicted, including twice by me.** I sized this
first at "~50 minutes" and then at "~21 minutes", both too pessimistic, because both times I
sized only the retrieval half I had been staring at. `provenance`, `citation_guard`,
`quote_verify` and `quote_reject` all resolve URNs through `Corpus.fetch_span/1` — one of
the four body sites — so 901 cases went from ~28 minutes to **8 seconds**. The same
estimation error as every other one today, in the flattering direction for once: **size the
whole thing, not the half you were looking at.**

A gate at 18 minutes is a different instrument from a gate at three hours: it can run on
every change rather than at phase boundaries. The tension was never depth against cost; it
was 38 seconds per search of pure waste, and no policy would have been the right answer.

**The lesson is about where the day went.** Every measurement was sound and every
conclusion followed from its evidence — the ABBA arms, the arm-attribution probe, the
pre-registered criteria. But the whole investigation optimised the lexical arm, which was
**0.03%** of the query, and the 41-second semantic arm sat unprofiled underneath all of it
because a *timeout stack trace pointed at `lexical.ex`*. The stack trace named the arm that
happened to hold the connection when the pool gave up, not the arm consuming the time.
**Profile the whole operation before optimising the part an error message names.**

### Translate the QUERY, not the canon (#43) — 0% to 91.7%, and term choice is worth 50 points

Stage B was scoped as generating English for ~300,000 Chinese chunks (~$260–770, plus
re-embedding, plus a 20:1 English-vector imbalance that #43 measured as likely to bury the
Pāli). The cheaper question was never asked: **`topical/chinese` and
`topical/chinese-native` are the same twelve questions in two languages**, scoring 0% and
100%. The passages are indexed and findable. Only the query is in the wrong language.

Two arms over those twelve, scored by the real harness with `expect_contains` **unchanged**
— only the query rewritten:

| arm | score | mean rank |
|---|---|---|
| English (shipped default) | **0.0%** (0/12) | — |
| **A — the term a translator would pick** | **91.7%** (11/12) | **1.0** |
| **B — a defensible synonym** | **41.7%** (5/12) | 2.8 |
| hand-written Chinese (gold) | 100% (12/12) | 1.25 |

**Translating the query recovers nearly everything, for no corpus change at all** — no
generated text stored, no new vectors, so the imbalance that blocked stage B never arises
and invariant #8 is not even engaged, because nothing generated is persisted. A
well-termed Chinese query returns at **mean rank 1.0**, better than the curator's own.

**And the whole risk is term choice, now quantified at ~50 points.** Arm B substituted
equally legitimate renderings and lost seven cases: 八聖道分 for 八正道, 四念住 for 四念處,
七菩提分 for 七覺支, 六處 for 六入處, 四等心 for 四無量心, 三十七菩提分法 for 三十七道品,
空定 for 空三昧. Each is real Buddhist Chinese; each is a register the *corpus does not
print here*, and lexical matching against a term the edition never uses returns nothing.

Two things make this trustworthy rather than a lucky sample:

- **The single Arm A miss was pre-registered.** Before scoring, the ambiguity note for
  top-021 read "緣起 vs 十二因緣 — the gold term is the latter". 緣起 was the one term where
  the natural translation and the canon's phrase diverge, and it is the one case that
  failed. The failure mode was predicted, not discovered.
- **Arm B's hit on top-021 is the inversion.** There the "alternative" happened to *be*
  the gold term, and it passed. The arms are measuring term choice, not query phrasing.

**This reverses the priority between the two candidate mechanisms.** Glossary term mapping
was assessed as too weak to matter — 84000's `glossary_entries` recovers only 2 of 12 gold
doctrinal terms as a *retrieval* method. But as a *constraint on translation* it is the
difference between 91.7% and 41.7%. `docs/TRANSLATION.md` already specifies the shape:
glossary-pinned translation with a visible term-mapping chain. It is not an enhancement to
query translation; it is the part that works.

**Caveats, because twelve cases is twelve cases.** One case is 8.3 points here, so Arm A
against Arm B is decisive while 91.7% against the gold's 100% is not. `topical/*` cannot
grow without more curated terms (it rejects terms too common to measure), so this axis
stays statistically thin by construction — the finding to bank is the *ordering* of the
arms, not their exact rates.

**What it would cost architecturally**, and the reason this is a decision rather than a
merge: it puts a model in the query path, which today has none. Search would stop being a
pure function of `bake_id` — the same question could return different passages on different
days — and it adds ~0.5–1 s to a search now running at 2.2 s. Neither touches the bake,
reproducibility of the corpus, or what is citable. A translation cache keyed by query hash
(ROADMAP anticipates one for Phase 7) makes the determinism objection largely go away.

### The glossary arm: the mechanism works, the term source does not (#43)

Built on the finding above — translate the query, and use a glossary rather than a model
because a glossary can expand to *every* attested register where a model must gamble on
one. `Pramana.Retrieval.Terms` maps English doctrinal vocabulary to Chinese from 84000's
1,105 English↔Chinese glossary pairs, and `Hybrid` fuses it as a **third arm**, so the
existing arms are untouched and nothing that works for Pāli or Tibetan can regress by
construction.

It works, on exactly the queries it can see. "What are the four noble truths?" expands to
`["四聖諦"]` and goes from **miss to rank 3**. And then the gold set:

| | before | with the arm |
|---|---|---|
| topical / chinese | 0.0% (0/12) | **16.7% (2/12)** |
| topical / pali | 56.3% (9/16) | 50.0% (8/16) |
| **answered from any tradition** | **72.7% (8/11)** | **63.6% (7/11)** |

**Two of twelve — which is the number this document already recorded and I argued myself
out of.** Sizing #12 established that "`glossary_entries` (84000) recovers 2 of 12 gold
doctrinal terms". Reading the glossary dump directly, I saw 四聖諦 and 四念處 alongside many
near-misses and called it "richer than 2 of 12 implied". It was not: the near-misses —
八聖道分 for 八正道, 菩提分法 for 七覺支, 四念住 for 四念處 — are **the wrong register for this
corpus**, which is precisely the 50-point failure mode measured in the arm B experiment an
hour earlier. The evidence to predict 2/12 was already in hand and was not applied.

**So it stays opt-in and off** (`expand_terms: true`). Under #44's standing rule a change
must be measured against answered-from-any-tradition before becoming a default, and this
one moves it the wrong way. The Pāli and topic losses are single cases, inside the
documented wobble, so the honest reading is not "it regresses" but "**+2 of 12 does not
justify a third arm diluting RRF**".

**The bottleneck is the term source, not the design.** 84000's glossary is oriented to the
Tibetan canon, and its Chinese equivalents come from translation traditions CBETA does not
print. A term list built *from this corpus* — every attested rendering, with occurrence
counts, adjudicated the way the topical gold terms already are — would plug into the same
arm unchanged.

**And a limit worth stating plainly, because it bounds the whole approach.** A glossary
fires on vocabulary. Measured directly:

    "What are the four noble truths?"                            -> ["四聖諦"], rank 3
    "What are the 4 things the buddha said when he was
     enlightened"                                                -> [], miss
    "what did the buddha realise under the bodhi tree"           -> [], miss

Both paraphrases return **8 of 8 Pāli results and no Chinese** — and the semantic arm
answers them *correctly* from the Pāli, with `Cattāri ariyasaccāni` at rank 4 on the first.
So a reader asking a paraphrase is not empty-handed today; they simply never receive the
Chinese witness. That is what `answered from any tradition` measures, and it is why the
three mechanisms are complementary rather than competing:

| | paraphrase | reaches Chinese |
|---|---|---|
| semantic arm | yes | **no** (0%, no English layer) |
| glossary arm | **no** (fires on vocabulary) | yes |
| LLM query translation | yes | yes, if term-pinned |

`docs/TRANSLATION.md` already specifies the combination — glossary-pinned translation with
a visible term-mapping chain. The measurements now say why neither half suffices alone: the
model supplies paraphrase understanding, the glossary supplies term fidelity, and the
glossary this corpus needs is one it has not got yet.

### `hnsw.ef_search` tracking the row limit does nothing — tried, measured, reverted

Looked like an obvious defect. `ef_search` was never set, so it sat at pgvector's default
of **40**, while the ANN query's SQL limit is `limit * @vector_overfetch` — after the
semantic arm moved to `limit * 6` that is **480 rows requested from a graph exploring 40**,
a 12x mismatch against pgvector's own guidance that `ef_search` be at least the limit. And
#43 had already recorded this exact class of failure: "the plain scan had been costing
recall all along — nothing failed; the answers were just further down."

A single-probe check seemed to support it: top-120 at `ef_search` 40 against 200 shared
**112 of 120** candidates with an identical top 10, so the difference lay in the tail — and
the depth work had just shown the tail is where Tibetan's +5 cases came from.

**All 446 retrieval cases, and nothing moved at all:**

| | baseline | ef_search = row limit |
|---|---|---|
| overall | 334/446 | **334/446** |
| chinese | 227/232, mean rank 1.98 | **227/232, mean rank 1.98** |
| pali | 82/150, mean rank 3.09 | **82/150, mean rank 3.09** |
| tibetan | 25/64, mean rank 3.24 | **25/64, mean rank 3.24** |
| wall clock | 17m22s | 18m17s (**+5.3%**) |

Mean ranks identical to two decimals: not one scored case changed position.

**Why, and it was reasonable to work out beforehand:** the iterative scan already
compensates. `relaxed_order` with `max_scan_tuples = 200,000` keeps pulling candidates
until the limit is satisfied, which is exactly what a larger `ef_search` would otherwise
buy. The two knobs address the same shortfall, and this codebase already turned the other
one on. The 112/120 overlap was evidence *for* that reading — the scan recovers the tail —
and it was read instead as "the tail matters", which was true and beside the point.

**Reverted.** No gain, 5% cost, and a knob with no measured motivation is a future
maintainer's puzzle. Recorded here so the next person who notices `ef_search` at its
default does not spend the afternoon on it: **it is not a bug, it is subsumed by the
iterative scan.** If `iterative_scan` is ever turned off, this becomes live again.

### The reranker needs no model, and it is worth +46 cases (#10)

Once the Pāli diagnosis said "ranking, not recall", the obvious next step was a
cross-encoder. It was not needed. **The `retrieval` cases quote a published translation,
and we store that translation** — so comparing the query directly against each candidate's
rendering separates them far more sharply than a chunk embedding does, at zero inference
cost. Invariant #5 again: deterministic before probabilistic, and here the deterministic
answer is also the better one.

`Pramana.Retrieval.Rerank` scores bag-of-words **containment** — how much of the query
appears in the candidate's rendering — over `limit * 5` fused candidates, then cuts to
`limit`. Reranking only the top `limit` could never reach the mis-ranked gold, which sits
at a median rank of 37.

| | baseline | **shipped** |
|---|---|---|
| retrieval overall | 334/446 (74.9%) | **380/446 (85.2%)** |
| retrieval / chinese | 227/232, rank 1.98 | **227/232, rank 1.98** |
| retrieval / pali | 82/150, rank 3.09 | **122/150, rank 1.51** |
| retrieval / tibetan | 25/64, rank 3.24 | **31/64, rank 1.32** |
| topical overall | 21/49 (42.9%) | **26/49 (53.1%)** |
| topical / tibetan | 0/9 | **2/9** — first non-zero ever recorded |
| **answered from any tradition** | **72.7%** | **81.8%** |

Nothing regressed, so it ships as the default under #44's rule. `rerank: false` opts out.

**Two predictions were registered before the run; one held and one was wrong in the
useful direction.** Chinese flat was the falsifier — no English renderings exist over the
Chinese canon, so every candidate scores 0 and the order must return untouched. It did,
exactly. Topical was predicted flat-or-worse on the reasoning that a topical query matches
no stored rendering; it rose by 5, because containment measures how much of the *query*
appears in a rendering, and a doctrinal question's content words do appear there. **This is
not only a quote-matcher — it is an English lexical signal over renderings**, which is why
it helps real questions and not merely the anchor-pinpointing the gold set is built from.

**The caveat that has to travel with the +40 Pāli.** Those gold cases are DERIVED from
translation anchors: the query *is* the rendering of the expected passage. A
query-to-rendering matcher therefore solves them close to the way they were constructed,
and the metric flatters the mechanism. #20 already recorded that this case type measures
"pinpoint the anchor whose translation I quoted" while users ask topical questions. The
capability is real — *"I have this English quote, where is it from?"* is ordinary
scholarship, and the citation guard's workflow begins there — but **+40 on `retrieval/pali`
must never be quoted as a general retrieval improvement**. The honest general number is
`answered from any tradition`, 72.7% → 81.8%.

### The first version silently reordered the canons, and only the per-tradition rows caught it

Shipped as an aggregate it looked clean: 370/446, **+36**. Per tradition it was
`chinese 227/232, pali 122/150, tibetan 21/64` — Tibetan **down 4**, twice the documented
ANN wobble.

The cause was a join, and it is the fourth time this exact join has been written wrong
here. Measured:

    derge.D   30,653 range-anchored        0 exact-anchored
    sc.ms          0 range-anchored  210,756 exact-anchored

84000 anchors a rendering to a folio **range**; SuttaCentral anchors one to a **segment
id**. A join written on `anchor_urn = segment.urn` therefore scores **100% of Pāli and 0%
of Tibetan** — and it did not merely fail to help Tibetan. Tibetan queries retrieve Pāli
candidates too, and only those were scorable, so **the reranker promoted the Pāli above the
correct Tibetan answer**. Completing the join took Tibetan from 21 to **31** — past its
25-case baseline, because now it is scored rather than displaced.

**The lesson is about the scorecard, not the join.** A +36 aggregate would have shipped a
mechanism that quietly ranked one canon above another as an artifact of which anchor form
the author happened to have in mind. For a project whose fourth invariant is that a
Japanese commentary must never be presentable as an Indian sūtra, silently reordering the
traditions is the more serious defect, and the aggregate could not see it. **Cross every
headline number with tradition before believing it** — which is exactly what #42 concluded
when `topical/chinese` 0% and `chinese-native` 100% were invisible in both margins.

### The reranker verdict was right about Tibetan and wrong about the system (#10)

The section below concluded "Tibetan's problem is RECALL, not order" and demoted the
reranker on that basis. The measurement was sound and the generalisation was not: it was
taken over 64 Tibetan cases and applied to a retrieval metric that is **150 Pāli cases**.
Pāli had never been probed. It is now, and it fails the opposite way.

| | **Pāli (150)** | Tibetan (64) |
|---|---|---|
| gold at rank ≤ 10 | 82 (54.7%) | 24 (37.5%) |
| **gold at rank 11–200** | **44 (29.3%)** | 9 (14.1%) |
| gold absent from 200 | **24 (16.0%)** | 31 (48.4%) |

**Tibetan cannot be reranked and Pāli can.** Half of Tibetan's gold never enters a
200-candidate pool, so no reordering reaches it. Pāli's gold is retrieved **84% of the
time** and simply sits too low: mis-ranked gold sits at 11, 11, 12, 13, 13, 13, 14, 15,
15, 16, 17, 20, 21, 24 … median **37**, and 30 of the 44 are at rank 62 or better.

**A perfect reranker takes `retrieval/pali` from 82/150 to at most 126/150** — **+44
cases**, against +9 for Tibetan. Overall retrieval would go 334/446 → up to 378/446. That
is the largest single gain available anywhere in the system, and it needs **no training**:
a cross-encoder over the top 50–100 is an off-the-shelf model.

**Why the earlier conclusion inverted the priority.** Tibetan is the weakest language, so
it drew the attention; but it is 64 cases against Pāli's 150, and the thing that helps it
(a better embedder — recall) is the expensive, uncertain option that already failed once as
a LoRA. The thing that helps Pāli (a reranker — ordering) is cheap and untried. The
sentence "a reranker first, then a Tibetan-fine-tuned embedder" was reversed on Tibetan
evidence, and reversing it back is correct for the corpus as a whole: **rerank for Pāli,
embed for Tibetan, and they are different problems needing different tools.**

This is the fourth instance today of a ratio or conclusion measured on one workload and
applied to another (rule 37), and the first where the error was in a *published
conclusion* rather than an estimate.

### What a reranker could actually fix (#10) — 14%, and half the misses are unreachable

The standing plan was "a reranker first, then a Tibetan-fine-tuned embedder". Before
building one, the cheap question: **a reranker reorders the candidate pool and cannot
introduce a passage retrieval never returned — so is the right answer in the pool?**
All 64 `retrieval/tibetan` cases, probed to depth 200:

| | cases | |
|---|---|---|
| gold at rank ≤ 10 | 24 (37.5%) | already a hit |
| gold at rank 11–200 | **9 (14.1%)** | **everything a reranker could fix** |
| gold absent from 200 | **31 (48.4%)** | **recall failure — no reranker helps** |

Mis-ranked gold sits at ranks 12, 14, 14, 17, 28, 30, 48, 177, 194 — median 28, and two
of the nine are barely in the pool at all.

**A perfect reranker takes `retrieval/tibetan` from 37.5% to at most 51.6% at this depth,
and cannot touch the other half.** That is a real gain and a bounded one, and it is not
where the constraint is: **nearly half of Tibetan retrieval never surfaces the right
passage in two hundred candidates.** Recall is the problem, so the fine-tuned embedder —
which changes what gets retrieved — is the higher-value work, and the order in the bullet
above was backwards. #10 already established that a Tibetan LoRA must be judged on the
gold set rather than on proxies; this says which metric it has to move.

**An unexpected second reading, NOT yet a claim.** The eval scores these same 64 cases at
**31.3% (20/64)** using `limit: 20`, which makes Hybrid's over-fetch depth 60. This probe's
own top ten, at depth 200, holds **24**. Same cases, same `covers?/2` rule, +4 cases from
retrieval depth alone. That is above the documented one-case ANN wobble but not far enough
above it to bank, and it is consistent with #43's finding that a wider scan returns better
neighbours rather than merely more of them. It needs a gold-set run at a configurable
depth before anyone believes it — the #10 rule applies to encouraging probes too, and this
is one.

### The gold set was too blunt to decide with (#14) — 249 → 1,400 cases

Two questions in one session came out undecidable, both for the same reason:

- **The 320-vs-512 window.** 6.3% of Pāli chunks were truncated. Against 20 Pāli cases
  that is an expected effect of **~1.26 cases**. The eval could not resolve it, so the
  question was settled on principle rather than measurement.
- **The Tibetan LoRA.** `retrieval/tibetan` moved 7/20 → 8/20 on one index rebuild and
  7/20 → 5/20 on another, **with nothing changed that could touch Tibetan**. HNSW is
  approximate, and Tibetan sits at 0.9727 mean pairwise cosine, so its candidates are
  near-ties that resolve arbitrarily. On 20 cases a ±2 swing is ±10%.

And the LoRA established that for a retrieval change the gold set **is** the decision, not
confirmation of one made on proxies. An instrument that decides has to be able to.

`mix pramana.evals.derive --per-type 300` — the mechanism already existed, capped at 40:

| type/tradition | before | after |
|---|---|---|
| retrieval/pali | 20 | **150** |
| retrieval/tibetan | 20 | **64** |
| retrieval/chinese | 35 | 232 |
| citation_guard | 81 | 601 |
| provenance | 40 | 300 |
| **topical (all four)** | **49** | **49** |
| **total** | **249** | **1,400** |

That 6.3% effect now implies ~9.5 Pāli cases instead of 1.26, and the ±2 Tibetan rebuild
swing falls from 10% of the metric to 3.1%. **Not padded**: the 64 Tibetan cases span
**65 distinct works**, one case per work, so they measure the language rather than a
handful of texts.

**`topical/*` did not grow and cannot.** Its cases come from a curated doctrinal-term list
that rejects terms as *too common to measure* — སྟོང་པ་ཉིད occurs in 20,500 segments, so
"was it found" carries no information. `topical/tibetan` stays at 9 and `topical/chinese`
at 12. Those are the hardest and most valuable questions in the set — a real question
rather than a translator's own words — and they remain statistically undecidable. Growing
them needs more curated terms that are specific enough to test, which is scholarship, not
a parameter.

**The new baseline, and what it shows.** 1,400 cases, **89.4% (1252/1400)**:

| | old (n) | new (n) |
|---|---|---|
| retrieval/pali | 55.0% (20) | **53.3% (150)** |
| retrieval/tibetan | 35.0% (20) | **31.3% (64)** |
| retrieval/chinese | 97.1% (35) | 97.8% (232) |
| provenance/chinese | 100% (40) | 100% (299) |
| topical/* | unchanged | unchanged |

The old figures were **noisy estimates**. Pāli's true rate is nearer 53% than 55%, and
Tibetan's nearer 31% than 35% — both old numbers sat inside their own sampling error,
which is exactly the condition that made #10 and #11 undecidable.

**89.4% is NOT an improvement on 79.5%.** The mix changed: near-perfect categories
(citation_guard, provenance) went from 121 of 249 cases (49%) to 901 of 1,400 (64%), so the
average rose while nothing got better. The two numbers measure different sets and must
never be compared. Any published figure needs the case count beside it.

**The runtime is 62 minutes of CPU, and the wall clock is unknown.** The first run read
8h20m wall, but **the laptop slept during it**, so that figure is an artifact rather than a
measurement and is not a basis for planning. CPU time is the number that survives a
suspend: 62 minutes, against ~5 minutes wall for the old 249 cases.

Two costs sit outside that CPU figure. The semantic cases went 75 → 446, each a query
embedding plus a filtered HNSW search over 617,038 vectors. And every search also runs
`Semantic.coverage/1`, a `SELECT count(*) ... DISTINCT ON` measured at **~1.1 s**, which is
database time and appears in neither the CPU total nor anyone's intuition — it lives inside
a correctness feature, so nobody looks at it. Across 1,400 cases that alone is ~26 minutes.
This line used to end "Worth caching: the figure depends on the corpus and the filters, not
on the query text." **`semantic.ex` argues the opposite at the call site, and it is right:**
the number exists so an empty result cannot be mistaken for a small canon, and a stale
cache reports a corpus fuller than it is — while embedding state changes *without* a
re-bake, so `bake_id` is not even a sound cache key. The ~1.1 s is real and still worth
attacking; the semi-join already took it from 1,224 ms to 921 ms. Caching is the wrong
attack, and two documents disagreeing about it is how a correctness feature gets optimised
away by whoever reads only one of them.

(Two earlier estimates here were wrong and are corrected: 45 minutes, extrapolated from the
case-count ratio, and 8h20m, taken from a wall clock across a sleeping machine.)

### A Tibetan LoRA that every proxy said worked, and the eval said did not (#10)

Trained on the 30,607 folio pairs below: LoRA on attention projections only, 2.36M of
570M parameters (0.41%), InfoNCE over in-batch negatives, 2 epochs on an L4 for ~$0.80.
Pooling, normalisation and `MAX_LENGTH` copied verbatim from `modal_embed.py` — a vector's
meaning comes from how token states are reduced, so training with one and serving with
another produces a worthless adapter and nothing fails.

**The base model could not match a Tibetan folio to its own translation.** On 500 held-out
pairs, at batch 24 where chance is 0.042:

| | top-1 | MRR |
|---|---|---|
| base | **0.044** (= chance) | 0.162 |
| adapted | **0.148** | 0.327 |

**And the discriminative test says the same, harder.** Adjacent chunks of one work are
related text; a chunk from elsewhere is not. The gap between them:

| | base | adapted | |
|---|---|---|---|
| bo | **+0.0098** | **+0.1883** | 19× |
| pli | +0.0693 | +0.1405 | 2.0× |
| lzh | +0.0845 | +0.1903 | 2.3× |

The base rated an adjacent Tibetan chunk at 0.984 and an unrelated one at 0.974 — a **1%
gap**. That is the 0.9727 clustering finding in the terms that matter. Chinese and Pāli did
not merely survive training on Tibetan; they roughly doubled, which is consistent with
in-batch negatives teaching dispersion generally.

**It took three probes to earn those numbers, and the first two were wrong.**

1. **Mean pairwise cosine only** — every language "improved" (bo 0.974→0.556, pli
   0.838→0.651, lzh 0.804→0.656). But that measures **dispersion, not discrimination**: a
   random projection would score beautifully and retrieve nothing. That all three moved
   nearly equally, when only Tibetan was trained, was the tell.
2. **Discrimination, silently broken** — `PeftModel.from_pretrained` injects the adapter
   into the base **in place**, so holding a "before" and an "after" reference compares one
   model with itself. It printed three confident `KEPT` verdicts with `rel`, `unrel` and
   gap identical **to four decimal places**. Only the impossible precision gave it away.
3. **Fixed with `disable_adapter()`** — the table above.

The margin metric reported during training (−0.0247 → −0.0479) moved the *wrong* way while
top-1 tripled. Contrastive training at temperature 0.05 sharpens the model, so when it is
wrong it is now more confidently wrong, and a **mean** margin conflates sharpening with
correctness. Top-1 and MRR are the trustworthy figures; the margin was mis-specified and a
median would have been the right choice.

Adopting the adapter means re-embedding **everything** — a fine-tuned model is a different
model, and mixing two in one index is what `embedding_model` exists to prevent. Renaming
`@model` to `BAAI/bge-m3+pramana-tibetan-lora-v1` flipped all 617,038 vectors to
outstanding automatically, which is the guard working unprompted. The adapter is
`merge_and_unload`-ed into the base weights at fp32 before the fp16 cast, so inference runs
the same code path as the stock model and costs the same: **144 chunks/s against a
historical 147**.

**And then it failed, completely.** On the gold set, against the real corpus:

| | adapted | baseline |
|---|---|---|
| **overall** | **70.7%** (176/249) | 79.5% (198/249) |
| **retrieval/tibetan** | **0.0%** (0/20) | 35.0% (7/20) |
| **retrieval/pali** | **5.0%** (1/20) | 55.0% (11/20) |
| topical/pali | 31.3% (5/16) | 56.3% (9/16) |
| topical/chinese-native | 91.7% (11/12) | 100.0% (12/12) |
| retrieval/chinese | 97.1% (34/35) | 97.1% (34/35) |

**Tibetan went to zero.** The language the adapter was trained for lost every case it had
been winning. Reverted to stock and the corpus re-embedded.

---

## Decisions taken

| Decision | Rationale |
|---|---|
| Name: **Pramāṇa** | "Valid means of knowledge." The name is the thesis; survives the medical-text expansion, which `dharma-*` would not. |
| Open-source, self-hosted | We publish the **pipeline, not the corpus**. Keeps CBETA's non-commercial clause and BDRC's restrictions out of our distribution. |
| All four traditions in v1 | Tibetan is the acknowledged long pole and the designated thing to cut if the schedule slips. |
| One Postgres | The predicate-plus-vector query is the most important query in the system. |
| MCP + HTTP API first, UI last | Makes the Phase 8 reader a renderer rather than a second implementation. |
| Elixir/Phoenix, 3 exceptions | See `docs/ELIXIR.md`. |
| Native Postgres, not Docker | The bake reads hundreds of thousands of small files; container FS on macOS is the slow path. `docs/DEV_ENV.md`. |
| **MCP library: `anubis_mcp`** | `hermes_mcp`'s last release was 2025-08-14 (a year stale); `anubis_mcp` 2.0.0 shipped 2026-08-07 with ~7× the daily downloads. The fork is maintained; hand-rolling JSON-RPC is no longer warranted. |
| **Segments carry char AND byte offsets** | Char offsets are for clients (multi-byte CJK); byte offsets are for the server (`binary_part/3` is O(1) vs `String.slice/3` O(n)). Verifying T0262 went 18.5s → 1.7s, and the guard resolves spans on every answer. |
| **Embeddings: dense in Bumblebee is viable** | BGE-M3 declares `architectures: ["XLMRobertaModel"]` and Bumblebee maps `XLMRobertaModel => Bumblebee.Text.Roberta`. Its sparse/ColBERT heads are two loose `.pt` linear layers, not part of the HF model — so they are portable to Nx, which could remove Python entirely. Ladder in `docs/ELIXIR.md`. |
| **Lexical fallback: character n-grams, not jieba tokens** | jieba is trained on modern Chinese and shatters Buddhist transliterations into single characters (耆闍崛山 → 4 tokens; 般若波羅蜜多心經 → `["般若","波","羅","蜜","多心","經"]`, inventing "多心"). OR-matching those returns noise. n-grams need no dictionary. jieba is kept for the Phase 6 reading layer (多音字 disambiguation is context-dependent) and the later modern-Chinese corpus. |
| **RRF, not score blending** | Lexical scores are occurrence counts; semantic scores are cosine similarities. They share no scale, and normalising them means picking a weighting that is a guess dressed as arithmetic. RRF uses only *rank*, so it is robust precisely because it discards the incomparable part. |
| **A query serving is separate from the indexing serving** | A serving compiled for batch 16 pads a single query to 16 rows and does 16× the work — measured at 10.6 s per query, versus 0.3–0.5 s at batch 1. Throughput config and latency config are not the same config. |
| **Unknown search options RAISE** | `division:` was silently dropped by the lexical retriever while the semantic one honoured it, so hybrid results were contaminated with works from outside the requested division *and still looked filtered*. Silently ignoring an unknown option is how that happened. |
| **Embed CHUNKS, never segments** | A segment is one printed line averaging **18.2 characters**, broken typographically: in T0262 the name 阿若憍陳如 splits across lines as `…阿若憍`/`陳如…`, so embedding it embeds half a name. Chunks are ~300-char windows — semantically coherent, and 15.8× fewer rows, which is the difference between embedding the corpus in an afternoon and in a week. |
| **`text_role` means FUNCTION, not arrival** | A Chinese translation of an Indian sūtra was `translation`, which describes how it arrived — and `composition_origin` already answers that. `root` (scripture), `treatise` (論), `catalogue`, `history` describe what a text *is*. This makes `origin = 'indic' AND role = 'root'` say what it means. |
| **Provenance is assigned during the BAKE, not by a later pass** | The loader replaces work attributes on conflict, so a bake computing weaker provenance than a backfill would silently erase it on the next re-bake. One source of truth (the division table), applied in the pipeline, makes a re-bake converge. There is a test. |
| **`pg_bigm` over `pg_trgm`/tsvector** | `pg_trgm` indexes trigrams, so the two-character queries that dominate Chinese cannot use the index at all. tsvector needs a tokenizer Postgres lacks. Bigrams accelerate `LIKE '%…%'` and are vocabulary-independent — they find 阿㝹樓馱 that no lexicon knows. Builds from source against Homebrew PG 18.4 in under a minute. |
| `.credo.exs` from `gen.config`, patched | A hand-written config silently **replaced** the default check set (3 checks instead of 69). Never hand-roll it. |
