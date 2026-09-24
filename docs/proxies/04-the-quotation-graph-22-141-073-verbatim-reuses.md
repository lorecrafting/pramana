# Why every proxy lied — chapter 4

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### The quotation graph (#22) — 141,073 verbatim reuses

A standalone Rust binary scans `texts.body` for runs of identical characters occurring in
two different works. **85.9M characters in about a minute**, 1.5 GB resident, and the
graph now holds **141,073 reuses across 1,301 works** — median 38 characters, longest
**746**.

The top results are exactly what a philologist would predict, which is the point: T2157
(貞元新定釋教目錄, 800 CE) reproducing T2154 (開元釋教錄, 730 CE) at 746 characters, and the
眾經目錄 catalogues sharing long blocks. Later Buddhist catalogues were compiled from
earlier ones, and the scan finds it without being told.

**Neither end is marked as the source.** Identical characters say nothing about who quoted
whom — that is a conclusion about dates and transmission — so the schema has an `a` end
and a `b` end, and every response says so. A tool that labelled one "source" would be
adding a claim the evidence cannot carry.

Two design decisions worth keeping:

- **Seed-and-extend, not a suffix array.** A suffix array would fit (2-3 GB) and give
  maximal matches directly. Seeds were chosen because they make the two decisions that
  actually matter explicit and tunable: the minimum length worth calling a quotation, and
  the frequency above which a string is boilerplate. That second knob is not optional
  here — 如是我聞 opens nearly every sūtra, and a method that cannot dismiss it drowns.
- **Emit only from the left edge of a match.** Every seed inside a shared passage would
  otherwise rediscover it, reporting one 200-character quotation as 189 of them.

**And a rule that was written down and then broken anyway.** `Pramana.Batch` now exists
because the Postgres 65,535-parameter limit was hit twice: a fixed 5,000 rows worked at
13 columns and failed at 18 in `Translations`, the lesson was recorded as rule 14, and
then a fresh 5,000 was written into `Quotations` for a 17-column table and failed
identically. A rule in a document does not survive being reimplemented; a shared function
does. Both call sites now derive the batch from the row width.

The full scan also exposed a resolver that loaded all 4.74M segments into memory to map
offsets — fine on a 155-work division, killed on the canon, *after* the scanner had
already done its job correctly, which made it look as though the scan had failed. It is
batched now.

### Task audit, 2026-08-16

Re-read every open task against what Phases 3-4 actually measured. Five changes.

**#44 created, and it blocks three things.** Tradition balancing: English vectors from
every tradition compete in one vector space with nothing keeping each reachable. Measured,
not suspected — 1,665 gloss vectors displaced Pāli answers. It now blocks **#21**
(Tibetan), **#26** (translation engine) and **#43 stage B**, because each of them adds
English vectors for another tradition and would compound a known defect.

**#21 Tibetan moved behind #44.** This is a reordering of the roadmap. Adding a third
tradition before the balancing mechanism exists means debugging interference across three
corpora instead of two, and the eval harness would report a decline it could not
attribute. #44 is small next to a canon ingest.

**#23 has an unmet prerequisite.** Translator fingerprinting is built on 異譯本 — alternate
Chinese translations of the same Indic original — and *nothing populates them*. The
relation vocabulary has a `parallel_of` slot and the corpus holds 90 `comments_on` and
nothing else. `Pramana.Compare` already documents this. Step 0 is asserting those
relations from catalogue metadata; the task now says so.

**#45 created: ship the apparatus as a tool.** `docs/COMPETITIVE.md` claims variant
readings as a differentiator, and **572,701 segments carry apparatus data** — but no tool
answers "how does this line differ across witnesses". A reader can only receive an
apparatus blob attached to a passage they already fetched. The claim was half-true and the
competitive doc now says so. This is deterministic, needs no acquisition, no tokens and no
vector space, so it is unaffected by #44 and can proceed in parallel — which makes it the
best thing to do while the balancing question is open.

**#41 dissolves into #14.** Three tasks are blocked on the same SAT reply. #41 (the
catalogue) has no separate source and would arrive with the text if access is granted;
#17 is a gate, not work. #14 is the only actionable item, and it is an email.

### The X ingest's six silent defects (B) — 2026-08-26

X landed at 1,230 texts with `verify OK` over 3,701 CBETA texts, and six things were
wrong underneath it. Four were invisible while the Taishō was the only CBETA collection
held, and **not one of those could fail a check that existed at the time.** The last two
are what `mix pramana.integrity` had to say, and the ingest had run `verify` only: the
check was crying wolf over 1,228 texts, and underneath that noise it was right about one.

**1. `embedding_coverage` reported 100.0% over a corpus 38% of which had no vector at
all.** X was baked and never chunked, and `Semantic.coverage/1` counted chunks:

    total: 560,238   embedded: 560,238   percent: 100.0
    unchunked: 1,230 texts, 4,068,303 segments

A text with no chunks is absent from the numerator AND the denominator, so it cancels out
of the ratio perfectly. The field exists so that partial data is never mistaken for a
small canon, and it was hiding a third of the canon. It now reports `reachable_percent`
(text-level), `unchunked_texts`, and a `note` in the shape `Pramana.Coverage` uses, so a
model cannot skim past it. **Counted over texts, not segments, deliberately**: the
segment-level query is 2.8 s against 96 ms and `Hybrid.run/2` calls coverage once per
search.

**2. Six works kept one of their two volumes — and WHICH one was decided by job
scheduling.** X0240, X0367, X0714, X0822, X1568 and X1571 each reuse one work number
across two volume files; `bake_all` ran one job per file and `Loader.load/2` replaces a
work's segments. The corpus had kept volume 8 of X0240 and volume 82 of X1571 — the first
and the second. **Two bakes of one `sources.lock.json` could therefore differ while
reporting one `bake_id`,** which is the only thing a `bake_id` is for.

The open design question — whether the anchors need rewriting — is answered, and the
answer is no. Measured across all six pairs:

    juan continues across the volume break   X08n0240 ends juan 44, X09n0240 opens juan 45
    juan+anchor collisions, all six pairs    0
    page-anchor collisions, X1571 alone      22,616

The URN carries the juan (`X0240_044@p0896b11`), so assembling changes no identifier and
creates no duplicate: 216,041 segments across the six, 216,041 distinct URNs. X1571 is
the one work where the *printed* locator is ambiguous — its two volumes repeat 22,616
page/register/line anchors, because page numbering restarts at each volume — so each
assembled line now carries `meta["volume"]`. **2,233,055 characters recovered.**

**3. Acquiring X deleted the Taishō from the lockfile.** `Lockfile.put_source/1` writes a
source entry whole, and CBETA is acquired one collection at a time:

    sources.lock.json, cbeta:  1,236 files, all X
    corpus, cbeta:             3,701 texts, T and X

**A corpus of 3,701 CBETA texts had a lockfile that could reproduce 1,230 of them.** That
is invariant 3 — *if a bake can't be reproduced from `sources.lock.json`, it's not a
bake* — and nothing anywhere reported it. `raw/` still held all 3,707 files; `verify`
re-derives from the file each text names on disk, so it passed; acquisition printed
success. `bake_id` had been computed over a lockfile describing a third of the corpus.
`Lockfile.merge_source/1` merges by path. A pin that has MOVED is decided by what the new
fetch covers: if it includes every path already locked the source really was re-acquired
and the entry is replaced, and if it does not the merge is refused — one entry listing
files fetched at two commits states something untrue about every one of them. The entry was repaired from the last commit that still held the T records — same
pin, `2b8ab8d5` — and re-hashed against `raw/`: **3,707 files, `{:ok, 3707}`**.

**4. A killed bake left its queue behind.** `bake_all` purged `completed` and `discarded`
jobs only, so the next run enqueued a second copy of everything still `available`: 1,468
jobs for 1,230 works. That is where the nine statement timeouts blamed on contention came
from, and it presents as a slow machine.

**5. The fidelity check had been crying wolf over 1,228 X texts.** It counts `<lb ` in
the raw body and compares against IR lines, and after the two-lineation fix roughly half
of every X file's `<lb/>` belong to the 卍續藏經 reprint and are correctly skipped:

    X0001: lb_lost — raw 46, bake 25       X0008: lb_lost — raw 16814, bake 8423

**The bake was right and the check was wrong**, which is the worse way round — a fidelity
check that cries wolf is a check that gets ignored, and this one had never been run since
X landed. The normalizer had counted the skips the whole time (`skipped_lb`, commented
"so that filtering everything away is a loud failure rather than an empty text") and then
discarded the number when it built the IR. It is now `IR.foreign_lb`, and the check
reconciles instead of comparing: every `<lb/>` in a CBETA body is either a line or a
skip. Over all 3,701 CBETA texts —

    raw <lb>     13,156,723
    IR lines      8,989,044
    foreign lb    4,167,679
    unaccounted           0   (0 texts mismatched)

**6. Underneath the noise, one real line.** With the reconciliation in place integrity had
exactly one complaint left — `X0575: line_unaddressable — raw 1756, bake 1755` — and it
was correct. The segmenter's blank test read `text: "", notes: [], apparatus: []` and
**omitted gaiji**, while `integrity`'s own definition of a printed line included them. A
line whose whole printed content is one rare glyph has empty `text`, because gaiji are
recorded as a mapping rather than substituted into the body, so it matched "nothing was
printed here" exactly.

That is the **third** time a not-blank line has been dropped here — note-only lines
(pipeline v2, 5,213 lines), `<note>` spanning `<lb/>` (v3, 10,590 lines), and now this.
The scale is different and the shape is identical: a definition of "blank" that lists the
kinds of content someone remembered. Corpus-wide it is **one line — X0575 0966b12, 䦚
(CB12059)** — and the Taishō has none, which is why the gate never saw it. Rare characters
are exactly the content a reader cannot reconstruct from anything else.

**The check that catches 2 and 3 now exists, and it is the general one.**
`mix pramana.integrity` gained a fourth check: a census taken from the lockfile **before
any parsing** — files → works → texts loaded. Checks 1–3 all begin at a text row, and
from inside a row a work that lost half of itself looks perfect. It reads
`cbeta: 3,707 file(s) -> 3,701 work(s) -> 3,701 loaded`, and it will fail the same way for
the next source whose works do not map one-to-one onto files, which is most of them.

`pipeline_version` → **4**. Dev pool timeout 120s → 300s: assembled X1571 is one
transaction of 74,570 lines against T1912's 26,000, and that file's own rule says a
timeout there is a capacity problem, never a data problem.

### The reader, first two screens (C) — 2026-08-26

`/` is a LiveView search and `/passage?urn=…` a LiveView passage view, both renderers
over the same domain functions the MCP surface calls. The Phase 8 note that the reader
should be "a renderer over an API that already returns spans, URNs and offsets" held —
but only after **three things were moved out of the MCP layer into the domain**, which is
the scope guard doing its job:

| moved | why it could not stay in a surface |
|---|---|
| `Provenance.group/1` | the reader and the tool would have described one bucket differently |
| `Retrieval.search/2`, `Retrieval.mode/1` | two surfaces routing `"semantic"` differently is one corpus answering a question two ways |
| `Lexical.known_opts/0` | so a dispatcher can drop `:coverage` before a phrase search — `Lexical` RAISES on unknown options, deliberately |

**The atom-table bug was walked into from the second surface.** `String.to_existing_atom("phrase")`
in the new LiveView raised on the first phrase search in a fresh VM and worked on every
one after, exactly as recorded for the MCP tool a phase ago — `:phrase` enters the atom
table only when `Retrieval.Lexical` loads. The literal map now lives in
`Pramana.Retrieval` where both surfaces reach it, with a regression test that runs a
lexical mode as its first search.

**What the page insists on, because each is an invariant that a UI can quietly drop:**
results bucketed by composition origin and role with each bucket named in words (#4);
URN and sha256 on every hit (#1, #2); both silences — what is not ingested and what is
not indexed — stated above the results, along with which retrievers actually ran.

Verified against the real corpus: searching 如是我聞 in phrase mode returns X passages with
byline provenance, a local source correctly flagged `edition_page anchor — not checkable
against a printed page`, and `pramana:cbeta.X:X0575_001@p0966b12` renders in context —
where the line two below it, `䦚通顯道甚深功德寶卷上`, shows what that recovered rare
character was doing: it is the first character of the work's own title.
