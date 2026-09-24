# Why every proxy lied — chapter 5

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### Versions on the page, and the collections gap (C) — 2026-08-27

The passage page renders `Compare.versions/2`: the whole translation pool, parallels, and
work-level alternates. SN 6.4 shows Sujato's English beside three parallels that reach
into the Chinese canon from one Pāli line — `T0100_006@p0412b07`, `T0099_044@p0324b03`,
`ja405@1.1` — which is the cross-canon claim this project exists to make, made visible.

Two things the page had to be taught **not** to say. A section with nothing in it is not
rendered at all, because a "Parallels" heading over an empty list asserts *we looked and
there are none*; `Compare.versions/2` returns `nil` rather than an empty structure for
exactly this reason, and the first version of this page rendered the explanatory note
under passages with no versions at all. And parallels pointing at texts not in the bake
are counted rather than dropped — T0099 has 1,958 recorded, 1,661 resolvable, and the 297
unopenable ones are stated, because a parallel we cannot show still tells a reader it
exists.

**`Coverage.cbeta/0`** closes the gap the X ingest opened. CBETA publishes **26
collections**; this bake holds two, and 24 collections / 1,298 works were absent with
nothing saying so — the Taishō 56–84 failure one level up, and invisible for two phases
because while the Taishō was the only collection loaded, "the Chinese canon" and "what we
have" were near enough the same sentence.

Counts are measured, from one git-tree call over the pinned repository at `2b8ab8d5` —
5,005 works, the same call `acquire_all` makes. **Most entries carry no name, deliberately.**
Each CBETA file states its own collection in `<sourceDesc>` (T: 大正新脩大藏經, X:
卍新纂大日本續藏經), and for a collection we have not acquired there is no such statement on
disk. Expanding `YP` or `GA` into a plausible canon name would produce exactly what this
project refuses: a reader unable to tell a sourced fact from a guess. A code and a work
count are facts; the name arrives with the files.

One existing test had to narrow rather than pass: *"issues no caveat, because there is
nothing to warn about"* asserted `caveat() == nil` for a corpus holding all 85 Taishō
volumes. That corpus still holds 1 of 26 collections, which IS something to warn about, so
the assertion now says what it was actually claiming — no *Taishō* warning.

### The work browser and the named apparatus (C) — 2026-08-27

`/works/:work_id` renders `Corpus.outline/1` and leads with provenance. The reasoning is
the one already written into that function: an outline is usually the FIRST thing anyone
sees about a text, so it is where a text gets misjudged, and without origin and role a
Japanese sectarian commentary and a Kumārajīva translation are indistinguishable — same
shape, same 品 headings, same juan count. T0099 renders 50 juan, 1,455 sections, 3,500
lines with variants, and its four candidate 異譯本 with shared-passage counts.

**The apparatus is served through `Apparatus.at/1`, which names witnesses from the text's
own header.** T0099_001@p0001a18 shows 【大】/【宋】/【元】. And the inline version on
neighbouring lines was rendering `meta["apparatus"]` directly, raw `wit="#wit1"` included —
caught in review, because `wit1` means 38 different things across the canon (宋 in 832
files, 明 in 375, 甲 in 322) and that module's own docs say a caller "must never be handed
`#wit1` as though it were a sigil". Neighbours now report that a variant exists; the named
form belongs to the line in focus, where the header has been consulted.

`Apparatus.count_for_work/1` was added to the domain rather than written as a query in the
view — a surface counting `meta ? 'apparatus'` for itself is a second definition of what
an apparatus is, and the fourth thing this reader has pushed back into the domain.

### `mix pramana.vectors` is the step between chunking and embedding — 2026-08-27

Chunking CBETA X produced 290,392 chunks in 98 s, and `mix pramana.embed.export` then
reported **`exported 0 chunk(s)`**.

Not a bug — a missing step, and one the runbook did not name. Chunking creates `chunks`;
the unit that gets embedded is a `chunk_vectors` row, created EMPTY and filled on import.
That ordering is what makes the sha256 round-trip possible at all: the row has to exist
before there is anything to re-check a returned vector against. `Embed.pending_query/1`
therefore looks for vector rows lacking an embedding, and a chunk with no vector row is
invisible to it.

**The failure reads as success.** `exported 0 chunk(s)` is exactly what a fully-embedded
corpus prints. `mix pramana.vectors --source cbeta` built all 290,392 rows in 29 s and the
export found them immediately. `docs/GPU_RUNBOOK.md` now names all three steps.

Also recorded there: **a `modal volume put` can stall silently.** 267 MB stopped at ~125 MB
with no error, no timeout and no output — the CLI prints progress to a TTY, so a
backgrounded run shows nothing and a stall looks exactly like a slow link. The byte counter
in `nettop -P -l 1 -x` is what distinguished them; the retry ran at ~700 KB/s and finished
in six minutes.

### Semantic search cannot say "I have nothing" (#19) — 2026-08-27

CBETA X embedded, the corpus re-gated, and `absence` fell from **100% to 25%**. Three of
the four cases were stale rather than failing; the fourth found something real.

**The three stale ones were testing a filter through the corpus's contents.** abs-001/2/3
were written as `expect_empty: true` under `origin: ["japanese"]`, premised on a sentence
that was true at the time — *this corpus holds no Japanese-composed work*. CBETA X brought
**145 of them**, and 唱題 now correctly returns X0967 教觀撮要論. The cases flipped to
failing on an ingest that made the corpus MORE complete, which is a test measuring the
wrong thing.

They now use `expect_origin: ["japanese"]`: every hit must carry the origin the query
asked for. That keeps exactly the teeth the cases were written for — abs-003's note says
"a filter that silently does nothing returns THOUSANDS of hits here" — and survives any
future ingest, because it tests the filter rather than the inventory.

**The fourth is a real limitation, and it had been invisible.** 本門戒體 is a Tendai
doctrine no text in this bake discusses:

    lexical (phrase, origin: japanese)   0 hits
    hybrid                               5 hits, retrievers: ["semantic"]
      X1164 淨土十要      將涉無生之龍津…
      X0956 山家義苑      …今此戒體，初心便可發之…      (戒體, not 本門戒體)
      X1244 百丈清規證義記  …當依佛語。以戒為師…

The lexical arm refuses correctly. **The semantic arm cannot refuse at all** — it returns
its k nearest neighbours regardless of how far away they are, and there is no distance at
which it declines. Nothing here is an answer; they are the closest Japanese-composed chunks
in the space.

**This case passed for two phases for a reason unrelated to the system working.** The
origin filter yielded an empty candidate pool because no Japanese-composed work existed, so
there was nothing to rank and "empty" came for free. X gave the filter something to admit
and the pretence ended.

`Pramana.Evals`'s own comment on this case type reads "This is the case type that most
projects have no answer for at all." Neither did this one; it looked like it did. For a
project named after the study of valid knowledge, a retrieval layer that cannot express
ignorance is the sharpest gap on the board — see `docs/PLAN.md` for the item.

The baseline records `absence` at 75%, not 100%. That is the honest number, and the ratchet
still catches a further drop.

### What the ignorance probe measured, and the hypothesis it killed — 2026-08-27

48 queries, before any code: 40 with known answers (20 Chinese definitional, 20
English→Pāli/Tibetan) and 8 with none.

    top-1 similarity      min      max
      answerable         0.7188   0.9223     Chinese 0.72–0.80, English 0.76–0.92
      unanswerable       0.6042   0.7423
    gap (top1 - top10)
      answerable         0.0077   0.0957
      unanswerable       0.0055   0.0358     6 of 8 INSIDE the answerable range

**The prediction registered before the run was wrong, and it was wrong in an instructive
direction.** It said a global absolute threshold could not work (BGE-M3's scale is
per-language — 0.9727 mean pairwise cosine in Tibetan against 0.84 in Pāli) and that the
signal would live in the *shape* of the neighbourhood, since "measure discrimination, not
dispersion" is what the Tibetan adapter probe taught.

Half right. The scale IS per-language — English queries sit a whole band above Chinese
ones, which is visible in the table. But the gap does not separate at all: `photosynthesis
in C4 plants` spreads wider than 13 of 20 answerable Chinese queries. **A lesson that was
correct for judging an embedder did not transfer to judging a query**, and the only way to
find that out was to measure it rather than reason from the earlier finding.

**The absolute number does separate, and is still not shippable as a gate.** 0.75 is the
lowest cut admitting none of the unanswerable set, and it refuses 4 of 40 answerable
queries — 10%, ~45 of 446 retrieval cases, to gain 1 absence case. Refused on cost, and
recorded in the rejected table so nobody re-derives it.

So the system REPORTS: `semantic_confidence` carries the top similarity and a band on
every hybrid response, in the MCP payload and above the reader's results, in the same
shape as `retrievers` and `embedding_coverage` — state the fact, let the caller weigh it.
`nil` when the semantic arm did not run, because "no model was loaded" and "the model
found nothing close" are different facts and only the second is about the corpus.

**The second signal was then measured, and it is one-way.** `lexical_support` alone is
useless — zero for every English→Tibetan query, so it detects the query's script rather
than the corpus's ignorance. Combined with the band, over 56 queries through the shipped
path: fires for **6 of 10 unanswerable** and **0 of 46 answerable**, paraphrases included.
Reliable when it appears, silent otherwise. Four unanswerable queries escape — three by
incidental n-gram overlap, and 如何申報所得稅 (*how do I file income tax*) because the
semantic arm puts it in `strong` outright, which is the sharpest possible argument against
ever promoting the band to a gate.

**The first version of that measurement was wrong, and wrong in the flattering direction.**
It called `Lexical.search/2` in phrase mode instead of going through `Retrieval.search/2`,
and reported 8 of 8 rather than 6 of 10 — because the hybrid's lexical arm falls back to
character n-grams and the component does not. 眾生皆能成佛 scores 0 phrase hits and 28
n-gram ones. **Three separate proxies flattered a signal in a single day**: the gap
statistic, the subset sweep's runtime, and this. Rule 47 is about registering predictions;
this is its companion — measure the path that ships, not the piece you can call quickly.

**abs-001 stays red, deliberately.** Reporting is not refusing. Closing it means
suppressing results, and suppression costs ~45 retrieval cases at the only threshold that
separates.

### The stubborn `retrieval/chinese` misses are a gold-set problem — 2026-08-27

The backlog carried "`retrieval/chinese` has 5 stubborn misses out of 232 and has not
moved all year. Cheap to diagnose now that a search is 2.2 s; nobody has looked." Looked.
After X the count is 9, and they split into two unrelated groups.

**Seven are X displacement**, which is expected and legitimate: X is overwhelmingly
commentarial and a commentary quoting a definitional formula is a genuine lexical match
for it. Of the top ten hits, X holds 6, 7, 8, 6, 6, 4 and 2 respectively.

**Two have no X in their top ten at all** — def-062 and def-082, and these are the
original stubborn ones. Both return a **correct answer the gold set did not ask for**:

    def-062  云何為一法   expects T0765_001@p0667a27
      rank 3  T0125_001@p0552c20   「云何為一法？所謂念法，當善修行…」

    def-082  云何為十一   expects T0125_046@p0794a18
      rank 3  T0125_046@p0795a26   「云何為十一？所謂阿練若：乞食，一處坐…」

def-062 finds the Ekottarika Āgama defining 一法 in the canon's own formula, at rank 3,
and is scored a miss because the case pins the 本事經 instead. def-082 finds the same
formula defining 十一 **in the same work and the same fascicle**, about a page from the
pinned line, and is scored a miss for that.

**These are enumerative formulae.** 云何為一法 and 云何為十一 recur throughout the Āgamas by
construction — the texts are lists — so there is no single correct answer to pin, and no
ranking change can make the system prefer one occurrence of a recurring formula over
another equally correct one.

**So `retrieval/chinese` has a ceiling below 100% that is not the system's fault**, and
tuning aimed at those cases is chasing something unwinnable. That is a second, independent
reason the configuration sweep was the wrong thing to spend five hours on.

**Deliberately not fixed here.** The harness already supports several accepted answers —
`expect_urns` is a list — so widening these cases is a one-line change. It is not made,
because widening a gold case makes a number go up, and that is indistinguishable in shape
from explaining away a regression. The absence cases were corrected today for a premise
falsified by an ingest, which is a different thing from a case that is valid but narrow.
This one is a judgement about what the eval should measure and it belongs to a human.
