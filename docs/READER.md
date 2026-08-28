# The Reader

The human surface. `mix phx.server`, then `/`.

```
/                          search — grouped by provenance
/inventory                 what is in this bake, and what is not
/survey?q=<phrase>         every occurrence, counted rather than sampled
/passage?urn=<urn>         one line in its printed context
/works/<work_id>           a work's structure, without its text
```

`docs/MCP.md` is the same corpus for a model. This is the same corpus for a person, and
the two read the *same domain functions* — see "What lives where" below, which is the
only structural rule this document has.

---

## It is a renderer, and that is a constraint rather than a description

Phase 8 was specified as "a renderer over an API that already returns spans, URNs and
offsets", with the note that **if the view starts needing new domain logic, the API is
missing something — fix the API, not the view.**

That held, but only because four things were moved out of a surface and into the domain
while building it:

| moved | from | why |
|---|---|---|
| `Provenance.group/1` | the MCP search tool | two surfaces would have described one provenance bucket differently |
| `Retrieval.search/2`, `Retrieval.mode/1` | the MCP search tool | two surfaces routing `"semantic"` differently is one corpus answering a question two ways |
| `Lexical.known_opts/0` | private | so a dispatcher can drop `:coverage` before a phrase search — `Lexical` raises on unknown options, deliberately |
| `Apparatus.count_for_work/1` | did not exist | a surface counting `meta ? 'apparatus'` for itself is a second definition of what an apparatus is |

Each of those started as three lines in a LiveView. The rule is worth restating because
each time it looked like over-engineering and each time the alternative was two answers to
one question.

## What the pages insist on

Every one of these exists because an invariant has to survive contact with a screen.

**Results are bucketed by composition origin and role, and each bucket is named in plain
language.** Not sorted, not colour-coded — bucketed under a heading that says
"Japanese-composed commentary". A flat ranked list lets a Kamakura-period commentary sit
directly beneath an Indian sūtra with nothing between them; a reader who mis-attributes
one now has to ignore a heading rather than merely miss a field. (Invariant #4.)

**Every hit carries its URN and its sha256.** The URN is displayed, not hidden behind a
copy button, because the URN *is* the citation: `T0262_001@p0001c19` reads as Taishō page,
register and line to anyone checking against print. (Invariants #1 and #2.)

**Both silences are stated above the results, on every search.** What is not ingested
(`Coverage.caveat/0` — Taishō 56–84, and 24 of CBETA's 26 collections) and what is
ingested but not vector-indexed (`embedding_coverage.note`). Plus which retrievers
actually ran, and **why** the semantic one did not when it did not: no serving in this
process is a different fact from nothing embedded, and only the first is fixed by
restarting with `PRAMANA_EMBEDDING=1`.

**A passage is shown in its printed context.** A Taishō line breaks mid-sentence at
whatever column the block-cutter reached, so a single segment is frequently unreadable
alone. The window is a reading convenience; each neighbour is a full span with its own
URN, and the window URN resolves as a unit.

**A section with nothing in it is not rendered.** `Compare.versions/2` returns `nil`
rather than an empty structure for exactly this reason. A "Parallels" heading over an
empty list is the assertion *we looked and there are none*.

**Parallels pointing at texts the bake does not hold are counted, not dropped.** T0099 has
1,958 recorded and 1,661 resolvable; the other 297 are reported as unopenable, because a
parallel we cannot show still tells a reader it exists.

## Two things it took a bug each to get right

**An edition page is a printed page.** The addressing badge was written as
`!= "canonical"` and read "not checkable against a printed page", which is true of
`derived` and false of `edition_page` — a page number printed in the physical book, which
a reader holding it can turn to. That badge was wrong on 4,576 texts, the whole Degé
Kangyur and Tengyur among them. `Pramana.Corpus` already records this same collapse being
made once before, when addressing was inferred from the source id and "understated what
can be verified".

**A witness id is not a sigil.** `meta["apparatus"]` carries each file's own
`wit="#wit1"`, and `wit1` means 38 different things across the canon — 宋 in 832 files, 明
in 375, 甲 in 322. The line in focus shows named witnesses via `Apparatus.at/1`, which
resolves against *that text's* header; its neighbours say a variant exists and name
nothing.

## Running it

```bash
mix phx.server                        # lexical only
PRAMANA_EMBEDDING=1 mix phx.server    # loads BGE-M3: ~80 s and ~2.2 GB, then hybrid works
```

The serving is opt-in because a developer running migrations should not pay 2.2 GB for it.
The consequence is visible rather than silent: without it every search reports
`Searched by: lexical` and says what would turn the other arm on.

## Every passage links out to the edition that published it

The passage page carries a link into CBETA Online, SuttaCentral or 84000 — whichever
published the text — beside the edition's own coordinate for that line: CBETA's linehead
`T09n0262_p0001a05`, SuttaCentral's segment id `sn6.4:1.2`, and none for 84000, which
prints folio references in running text rather than in ids anything can address.

**The link is a convenience and the page says so.** The URN is the citation, and it is
reproducible from `sources.lock.json` in a way a third-party website is not. `verified` is
literally false: CBETA Online and SuttaCentral return HTTP 200 with an identical body for
a real path and for nonsense, so a link checker would be theatre. See `Pramana.Reader`,
which records what was measured for each publisher and on how many identifiers.

## The inventory answers, once, what every other page answers per query

Someone opening a search box cannot tell an empty result from a short shelf. Search,
survey and passage all carry `Coverage.caveat/0` alongside results a reader has *already
asked for*; `/inventory` says it before they ask, and **leads with the gaps rather than
the totals**. 17,061 texts is an impressive number and an uninformative one — *ten of
CBETA's 26 collections* and *Taishō 56–84 entirely absent* is what decides whether this
corpus can answer your question.

Every figure comes from `Pramana.Inventory.snapshot/0`, which has anticipated this page
since Phase 3: *"Phase 8 will want the same numbers for the reader, and a second
implementation is how two surfaces start disagreeing about what the corpus contains."*
The view computes nothing.

## The survey exists because a search page invites a bad claim

Top-k retrieval structurally cannot answer *how often, and where*. It returns the best
twenty hits and says nothing about whether there are twenty-one or twenty thousand, or
whether they cluster in one commentary or spread across the tradition. A reader given
twenty results generalises from them.

For two phases search was the only thing a person could do here, while the MCP surface
has had `survey_corpus` since Phase 3 carrying a note that tells models to run it *before*
claiming anything about frequency. The human surface had no equivalent, which means every
claim a person formed from this corpus was formed from a ranked sample.

`/survey` counts in SQL over the bigram index — 1.2 s over 10.7M segments — and reports
the concentration alongside the total, because that is the number that decides what a
count means: 一切眾生 appears in **36,775 lines across 1,904 works**, 40.8% Indic-composed
and 35.0% Chinese-composed, with the heaviest single work holding 7%. A phrase in one work
is that work's idiom; a phrase across nineteen hundred is the tradition's.

## Not built yet

- Anything that writes. The MCP surface is read-only by invariant #7 and so is this; the
  CLI is the write path.
- A commentary↔root alignment view. Phase 6, and the domain does not have it yet either.
