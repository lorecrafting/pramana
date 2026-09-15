# Project history — chapter 8

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

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
