# The Reader

The human surface. `mix phx.server`, then `/`.

```
/                          search — grouped by provenance
/inventory                 what is in this bake, and what is not
/survey?q=<phrase>         every occurrence, counted rather than sampled
/passage?urn=<urn>         one line in its printed context
/works/<work_id>           a work's structure, without its text
/check                     paste a report; see which of its claims survive
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

**A list that is cut says how much it cut.** The passage page shows the 8 longest
quotations of a line and, when there are more, says *"Showing the 8 longest of 109
quotations of this line"* — 27 root lines in the corpus carry more than eight. Eight of 109
rendered in silence tells a reader there are eight, which is the same failure as a
coverage figure without its denominator, on a page rather than in a number. `get_glosses`
had it on the API side and reports `returned`, `total` and `truncated` for the same reason.

**Every hit carries its URN and its sha256.** The URN is displayed, not hidden behind a
copy button, because the URN *is* the citation: `T0262_001@p0001c19` reads as Taishō page,
register and line to anyone checking against print. (Invariants #1 and #2.)

**Both silences are stated above the results, on every search.** What is not ingested
(`Coverage.caveat/0` — Taishō 56–84, and whichever of CBETA's 26 collections are absent) and what is
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

**A work's page names the hand behind the byline, with the inference on screen.**
`attributed_author` is what the edition printed — `姚秦 鳩摩羅什譯` — and beside it now sits
the person it resolves to: dates as the span of a life, sect, birthplace with its
**historical** region (西域, not 新疆維吾爾自治區), and recorded teachers and students.

Two refusals carry over from `Pramana.Authority` and both are visible rather than
documented:

- **The panel says "probable, never certain" on the page.** The name is in the byline; that
  it denotes this person rather than an unrecorded namesake is an inference, and a surface
  that looked more certain than the data would be worse than no surface.
- **A byline that resolved to nobody renders nothing at all.** Roughly 40% do not resolve,
  and that is a refusal rather than a gap — an empty "Attributed to" heading would assert
  that a person was identified and nothing is known about them.

An open bound prints as an open bound: 施護 is recorded only by his death, so the page reads
`d. 1018`. Printing `1018` alone would assert a birth year nobody recorded, and `1018–1018`
would assert a life of no duration — the same distinction `date_basis` keeps in the
database.

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
the totals**. A five-figure text count is an impressive number and an uninformative one;
*which of CBETA's 26 collections are absent* and *that Taishō 56–84 is missing entirely* is
what decides whether this corpus can answer your question. Every figure on the page is
computed, so this document names none of them — the sentence it replaced quoted a text
count and a collection count, and both went stale within two ingests.

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

## `/check` is the only page here that helps you disbelieve something

Every other screen helps you find a passage. This one takes a document — an answer from
some other assistant, an essay, a draft — and reports which of its claims survive contact
with the corpus. Added 2026-08-31; `Pramana.Report.verify/2` had shipped three days
earlier and was reachable only by MCP call, which is rule 60.

It is the one thing in this space nobody else offers. `verify_citation` and fojin's
`/api/verify/quote` check a single quotation. This checks **a whole document including its
arithmetic**, because the claims that carry a report are not the quotes:

    "T0262 says X"                              -> byte-compared, and always could be
    "X appears 36,775 times across 1,904 works" -> needs the survey re-run
    "no Japanese-composed text uses X"          -> needs the search re-run, still empty

A frequency generalised from twenty ranked hits reads exactly like one counted over twelve
million segments, and that is live in the world right now — people are getting fluent,
confident, invented Dharma from general assistants with nowhere to take it. **Nothing on
this page asks anyone to trust a model of ours**: the checks are byte comparisons and
re-executed counts.

**Three verdicts, and the third is why it is worth building.** `verified` and `failed` are
the obvious two. **`unverifiable`** is a replay recorded against a different `bake_id` —
the corpus has changed and the claim cannot be re-run here. It is not refuted and it does
not pass, it is rendered in its own colour, and collapsing it into `failed` is how a
checker teaches people to ignore it. `mix pramana.integrity` lost its audience that way,
crying wolf over 1,228 X texts.

**The summary states its denominator**, because "3 citations verified" over three
renderings of one Pāli line is not the claim it appears to be. It reports how many were
byte-compared, how many were checked for **existence** only because no quotation was
attached, and how many quoted a translation rather than the source.

And it refuses two things. It does not judge whether a citation *supports* the claim
attached to it — `Pramana.Guard` draws that line and this holds it. And its
*unsourced figures* list is a heuristic prompt to look, never a verdict: a check that
failed on any prose containing a page number would be unusable.

### `/check` also reads other people's citations, and offers repairs

Added 2026-09-02, and the first half closes a hole rather than adding a convenience. The
guard scans for `pramana:` URNs, so **a report citing the Taishō the way an article cites
it — `T. 262, 6a23` — contained no citations at all.** The page reported nothing checked,
which read as nothing wrong. It now recognises the Taishō in print and SAT form and
SuttaCentral segment ids, resolves them, and lists any it could not place rather than
dropping them.

The second half is repair. Beneath the verdicts the page now offers what can be done:

    verified            byte-matches. Untouched.
    quote_relaxed       the words are the corpus's and the punctuation was an editor's —
                        the quotation is replaced with what the corpus prints.
    citation_corrected  the words are real, the address was wrong; the URN is replaced
                        with where the guard's own search found them, and only if unique.
    no_sources          nothing supports it — the citation goes, the sentence stays.
    flagged             repair needs a judgement, so it is named and left alone.

**Every change is a substitution of something the corpus already said.** Nothing is
generated, and a quotation found in three places refuses rather than picking one — a
document whose citations all resolve and some of which are wrong is worse than the one
that came in. The repaired text sits behind a disclosure, never replacing what was pasted.

## Not built yet

- Anything that writes. The MCP surface is read-only by invariant #7 and so is this; the
  CLI is the write path.
- A commentary↔root alignment view. Phase 6, and the domain does not have it yet either.
