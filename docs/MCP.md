# The MCP Surface

The product boundary. A model never touches Postgres — it sees these eleven tools and two
resources, and everything they return is URN-addressed so it can be independently
re-checked.

**Read-only, permanently.** Tools read; the CLI writes. `docs/ADDING_TEXTS.md` explains
why, and `CLAUDE.md` invariant #7 makes it binding.

## Tools

**Every registered tool is in this table, and `PramanaWeb.MCP.DocumentedTest` fails the
build otherwise — in both directions.** The table listed ten for two phases while
`get_commentaries` and `get_parallels` were registered and undocumented, which for a
surface whose entire purpose is to be discovered by a model is the same as not shipping
them. It then went stale twice more before anything checked it. No count is written here:
count the rows, or ask `tools/list`.

| tool | for |
|---|---|
| `search` | **Hybrid by default** — lexical fused with semantic by RRF. The normal entry point, and it reads SOURCE text. |
| `search_translations` | The tool for an English phrase. `search` answers an English question with source-language n-gram noise; this reads the renderings and returns the **anchor** each one renders. |
| `survey_corpus` | Exhaustive counts, not a ranked sample. The tool that supports claims about *how often* or *where*. |
| `get_passage` | One URN, optionally with `context_before` / `context_after`, and optionally with translations (`translation`, `translator`, `compare_translations`). |
| `get_outline` | A work's structure without its text. |
| `get_commentaries` | Which works explain this work, and what this work explains — walked back to root scripture. |
| `get_glosses` | Which commentaries explain **this line**, by deterministic 科文 lemma match. |
| `get_works_by_person` | Everything one translator or author produced, under a **DILA authority id** rather than a byline string — 求那跋陀羅 is one man across three spellings. |
| `get_person` | Who that id **is**: dates as ranges, sect, a resolved place with both its modern district and its **historical** region, recorded teachers and students, and a Wikidata q-id where DILA carries one. |
| `get_parallels` | Curated passage parallels for a work. Note `Coverage.parallels/0`: 6.1% of the recorded graph has both ends in this bake. |
| `compare_versions` | One passage beside its renderings and its curated parallels. |
| `compare_witnesses` | Where the manuscript witnesses to a line disagree, each named in the edition's own sigla. |
| `get_quotations` | Every other text that reproduces this passage word for word. |
| `get_readings` | How a passage is pronounced, where the ordinary answer is wrong. |
| `define_from_canon` | Where the canon defines a term, by its own definitional formulae. |
| `verify_citation` | Byte-compares a quotation against its URN. |

### An English question needs `search_translations`, not `search`

`search` reads the source text, so an English query reaches it as characters: it returns
Pāli or Chinese passages that share n-grams with the English and nothing to do with the
question. 210,756 English renderings can answer, and every one of them leads with the
source line it renders. **Cite `anchor_urn`; the rendering carries
`citable_as_source: false` and a `rendering_urn` that is a fragment over the anchor, never
a top-level URN.**

`match` says how hard it worked. The unit is one rendered line, so requiring every term in
one row is strict — `Baka Brahmā` finds nothing that way while each word alone returns the
same discourse. The fallback reports `match: "any_term"`, and a caller told that knows the
words were not found together. Measured at **70.0%, mean rank 1.68** over 40 cases derived
without consulting the retriever.

### Translations never arrive in `text`

`get_passage` returns the source in `text` and any renderings under a separate
`translations` key, each labelled `citable_as_source: false`. Merging them would defeat
the guard rather than trip it: a model handed Sujato's English where the Pāli belongs
quotes it as the Pāli, attributes it to a URN that really does address the Pāli, and the
guard verifies the source quote against the source. Nothing would catch it, because
nothing was wrong at the point the guard looks.

Without `translation`, no rendering is attached at all. With it, the caller is told how
many renderings were **withheld** (`alternatives`), because a passage with four English
translations shown as one reads as a passage with one.

### Comparison keeps its two kinds apart

`compare_versions` returns `renderings` and `parallels` under separate keys. A rendering
is someone's English *for this passage*; a parallel is a **different text** that
scholarship judges to transmit the same discourse. Merged into one list, a Pāli sutta
reads as a translation of a Chinese Āgama, when neither derives from the other. Each
parallel keeps its relation strength, and the response counts what is
`referenced_but_not_held` — texts the scholarship links that this corpus does not have —
so a partial comparison is never presented as a complete one.

### Quotations are found, not judged

`get_quotations` returns verbatim text reuse — a commentary reproducing its root text, a
sūtra circulating both inside a collection and standalone. It is found by scanning for
**character identity**, so a result is either true or a bug, never a threshold someone
picked.

**Neither end is marked as the origin.** Identical characters say nothing about who
quoted whom; that is a conclusion about dates and transmission which the scan cannot
reach, and a response labelling one end "source" would be adding a claim the evidence
does not carry. Every response says so.

Overlap counts, not only containment: a commentary lifting a clause of a line is still
quoting it, and requiring the whole line would hide the commonest case.

### Readings say where each one came from

`get_readings` romanises a passage, and every token carries a `source`: `exception` where
the Buddhist reading dictionary overrode the ordinary reading, `base` where the ordinary
reading was applied unchanged, `unknown` where none is recorded and none was guessed.

The distinction has to survive to the caller. Transliterated Sanskrit follows conventions
that ignore the characters' ordinary values — 般若 is *bōrě*, 迦葉 is *jiāshè*, and 佛 is
*fó* where Unicode's per-character field says *fú* — so a response that flattened the
three kinds into one string would let a reader take an unchecked default for a Buddhist
convention. On a 46-form test set the per-character method scores 50% and the dictionary
100%; `mix pramana.readings.check` re-runs both, so the comparison stays a measurement.

A reading is a rendering aid. **The text is what is citable**, not its pronunciation, and
every response says so.

### Variants name the witness, and the witness is per text

`compare_witnesses` returns the Taishō's own critical apparatus — 572,701 segments carry
one — with each reading attributed: 消 → 銷 in 【宋】【元】【明】, 至 → 志 in 【宋】.

The attribution is the hard part. A `<rdg wit="#wit1">` refers to a witness declared in
**that file's header**, and the ids are not stable: across the 2,471 CBETA files `wit1`
means 38 different things — 宋 in 832, 明 in 375, 甲 in 322. A global lookup table would
report a Ming variant as a Song one, in the tradition's own sigla, in about a thousand
works, and nothing about the output would look wrong. So each text carries its own map,
imported from its own pinned file, and an id that cannot be resolved is returned as
unidentified rather than guessed.

An omission is also kept distinct from a substitution: "this witness has nothing here" and
"this witness reads something else" are different claims about a manuscript.

`get_passage` reports `variant_count` so a reader knows there is something to look at.

### Definitions are quoted, not composed

`define_from_canon` searches for the tradition's own definitional formulae — 云何為X in
Chinese, Katamañca X in Pāli — immediately followed by the term. It finds the handful of
places the canon stops to say what something *is*, out of the thousands where it merely
uses the word, and returns those passages with citations. A term the canon does not
define returns nothing, along with the formulae that were tried: "we looked, in these
ways, and found nothing" is a different claim from "we did not look".

**Results are bucketed by provenance, exactly as `search` is**, because "the canon defines
X" is a claim about *who* is defining it. The tool's `origin` field always said that "a
definition from a Japanese-composed commentary is a different kind of evidence from one in
a translated sūtra" — and it returned a flat list in which they were indistinguishable
without inspecting every element. That was survivable while the Taishō was the whole
corpus and the formulae matched root scripture almost exclusively. CBETA X added 1,230
mostly-commentarial works, and **a commentary quoting a formula is a genuine lexical match
for it**: 云何為二法 now ranks X0771 釋摩訶衍論疏 above the Ekottarika Āgama passage. Both are
real answers, and only the bucket tells them apart.

Every filter a tool *declares* must actually filter. `division:` was once declared,
accepted, and silently ignored by the lexical retriever while the semantic one honoured
it — so hybrid results were contaminated **and still looked filtered**. There is now a
test asserting each declared filter changes the result set, and unknown options raise
rather than being dropped.

## Resources

| uri | mime | content |
|---|---|---|
| `pramana://guide` | `text/markdown` | How citations, the provenance axes, and the retrievers work. |
| `pramana://inventory` | `application/json` | Live counts for the current bake: works, segments, provenance breakdowns, embedding coverage. |

**Why resources rather than tools:** these are things to *read about* the corpus, not
operations to perform on it. A model that has read the guide uses `origin`, `role` and
`division` — the provenance modelling that distinguishes this project — instead of
defaulting past them. `inventory` exists so a model can tell *"the canon does not say
that"* from *"that part of the canon is not loaded yet"*, which are opposite answers.

Two things must agree for a resource to be reachable: `component/1` registers it, and
`capabilities:` advertises `:resources`. Registering without advertising fails silently
— no client ever calls `resources/list`, so nothing errors and nothing is served.

## Honesty fields

Retrieval degrades rather than failing, so every response says what it actually ran on:

- **`retrievers`** — `["lexical"]` alone means semantic search was unavailable and
  meaning-based matches were never considered.
- **`embedding_coverage`** — how much of the corpus is vector-searchable. Partial
  coverage is not a small canon. **Two numbers**: `percent` is the share of existing
  chunks carrying a vector, `reachable_percent` the share of texts that were chunked at
  all. A text with no chunks cancels out of `percent` entirely, so `percent: 100.0` with
  `unchunked_texts: 1230` means the index is complete over the part of the corpus it
  covers and blind to the rest; `note` says so in words when it applies.
- **`mode`** — `phrase` is strong evidence; `ngram` is a character-window fallback.
- **`role`, as a filter, cannot reach 1,640 texts.** `text_role` comes from the Taishō's 部
  division table and no other collection has one, so `role: ["root"]` returns the Taishō
  and silently excludes X's 1,230 works, J's 285 and N's 38. A thin result under a role
  filter may mean the material was never a candidate. `pramana://inventory` reports the
  gap; the roles are not guessed, because a wrong role on thousands of works is worse than
  a missing one.
- **`composed_after` / `composed_before` on `search` reach 1,515 works, not 17,281.** A work
  is datable only where its byline resolved to a DILA person **and** that person has a
  recorded date, so a date-filtered search reads under a tenth of the shelf. The response
  carries `date_coverage` whenever either option is used, and its `note` is the sentence
  that matters: an undated work is **unaddressed** by the filter, not excluded on evidence.
  The dates themselves are lifespan bounds — `date_basis: authority_lifespan` — so they
  answer *which century* and never *which year*.
- **`authority_id`** — who the byline denotes, where it could be resolved. A byline is what
  the edition printed and the same person appears under several; the id is one identity
  across them, and `get_works_by_person` takes it. It is `null` on roughly 40% of works —
  a refusal, not a gap, because a wrong link merges two people permanently.
- **`witness_name`** — the edition by name, never only its sigil. `witness: "T"` and
  `witness: "N"` differ by one character; the texts behind them differ by fifteen centuries
  and two intervening languages, and both are `indic` in origin and `root` in role.
  **Read the name.**
- **`addressing`** — `canonical` is checkable against a printed edition; `derived` is
  not, because that source has no printed page and line.
- **`bake_id`** — which corpus snapshot answered. **On every tool**, since 2026-08-28; nine
  of the then-fifteen carried it before, and `survey_corpus` was among the six that did not, which is
  the worst of them: a count without the corpus it counted is not evidence of anything.
- **`replay`** — `{tool, arguments}`, the call that produced this response. With `bake_id`
  it is a **reproducible citation of a retrieval**, exactly as a URN is one of a passage:
  run it again against the same bake and you get the same answer. A sourced report can carry
  the replay record beside each claim, so a reader can check not only that the quotation is
  real but that the search which found it was the search the report says it was.
  `arguments` holds what the caller actually sent — a default is omitted, because re-sending
  one would pin a value free to change.

## Reader deep-links

`search` hits and `get_passage` responses carry a `reader` block pointing into the
published edition, so checking a citation is one click rather than a trip to a library.

```json
"reader": {
  "edition": "CBETA Online",
  "url": "https://cbetaonline.dila.edu.tw/en/T0262_001",
  "granularity": "juan",
  "anchor": "T09n0262_p0001a05",
  "anchor_label": "CBETA linehead",
  "verified": false
}
```

Three publishers, each measured against real identifiers drawn from the corpus:

| source | edition | opens | measured |
|---|---|---|---|
| `cbeta` | CBETA Online | the fascicle | every volume token reproduced from `sources.lock.json`, 4,068 files |
| `sc`, `sc-translations` | SuttaCentral | the sutta | 40 of 40 uids resolve; 3 land on the range that contains them |
| `derge`, `derge-tengyur` | 84000 | the work | 29 of 30 Toh numbers return the work's own title |

Four deliberate limits, all of them in the payload rather than only in this file:

- **The link opens a unit, not a line**, and `granularity` says which. `anchor` carries
  that edition's own coordinate for the exact line and `anchor_label` names the grammar,
  because one field holds three: CBETA's linehead (`T09n0262_p0001a05`, which pastes into
  its Goto box), SuttaCentral's segment id (`sn6.4:1.2`), and **nothing** for 84000, whose
  reading room prints folio references in running text rather than in addressable ids.
  `anchor: null` there is a refusal to invent one.
- **`verified: false` is literal, not modesty** — and it is not uniform. CBETA Online and
  SuttaCentral are SPAs that resolve content in the browser: both return HTTP 200 with a
  **byte-identical body** for a real path and for nonsense, so a link checker would be
  theatre. 84000 is server-rendered and *can* be checked — `toh9999` comes back titled
  "Toh 9999". `false` everywhere is the honest floor rather than a per-publisher claim
  nobody will keep current.
- **A short text may open its range.** SuttaCentral groups `dhp298` into `dhp290-305` and
  resolves the member uid to it. The cited verse is on the page; the note says which
  happened rather than promising the verse.
- **No template, no link.** `reader` is absent for any source whose format has not been
  confirmed against real pages — SAT included, until task #14 ingests it and the format
  can be checked against real identifiers. A plausible link to the wrong passage is
  worse than none, because nothing about it looks wrong.

**The linehead was wrong for 725,650 segments until 2026-08-27**, and the way it was wrong
is the reason this section names its evidence. It padded every volume to two digits, which
is the Taishō's width and not CBETA's — `A1057` is in `A091` — and it took the volume from
the *work*, which for a volume-spanning work is the range `"130-133"`. Both produced
strings that look exactly like citations and resolve nowhere. The widths now come from the
`id` attribute CBETA puts on the line in the HTML its own site serves, and a test
reproduces every volume token in the lockfile. Note which source won: CBETA's *catalogue*
reports M1540 in volume `M059` while CBETA's *page* says `M59n1540_p0789b01`.

**The URN is the citation; the URL is a convenience.** The corpus is reproducible from
`sources.lock.json`; a third-party website is not.

## Transports

**stdio**, for Claude Code and other local clients — `.mcp.json` points at
`bin/pramana-mcp`. That wrapper exists for two reasons worth not rediscovering: it puts
the pinned toolchain on `PATH` (mise is not active in a non-interactive shell), and it
compiles with stdout redirected to stderr, because on stdio **stdout is the protocol
channel** and one "Compiling 3 files" line corrupts the stream.

**Streamable HTTP** at `/mcp`, forwarded outside the browser pipeline in
`PramanaWeb.Router`. This is what a remote client or the Phase 8 reader uses.

## Semantic search is opt-in

Loading BGE-M3 costs ~80 s and 2.2 GB, so `Pramana.Embed.Serving` is disabled by
default — tests must never load it. Enable with `PRAMANA_EMBEDDING=1` or
`config :pramana, :embedding_serving, true`. When it is not running, `search` degrades
to lexical **and reports `retrievers: ["lexical"]`** rather than looking complete.
