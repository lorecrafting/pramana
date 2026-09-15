# Project history — chapter 6

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

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
