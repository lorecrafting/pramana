# Project history — chapter 11

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

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
