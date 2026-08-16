# The MCP Surface

The product boundary. A model never touches Postgres — it sees these ten tools and two
resources, and everything they return is URN-addressed so it can be independently
re-checked.

**Read-only, permanently.** Tools read; the CLI writes. `docs/ADDING_TEXTS.md` explains
why, and `CLAUDE.md` invariant #7 makes it binding.

## Tools

| tool | for |
|---|---|
| `search` | **Hybrid by default** — lexical fused with semantic by RRF. The normal entry point. |
| `survey_corpus` | Exhaustive counts, not a ranked sample. The tool that supports claims about *how often* or *where*. |
| `get_passage` | One URN, optionally with `context_before` / `context_after`, and optionally with translations (`translation`, `translator`, `compare_translations`). |
| `get_outline` | A work's structure without its text. |
| `compare_versions` | One passage beside its renderings and its curated parallels. |
| `compare_witnesses` | Where the manuscript witnesses to a line disagree, each named in the edition's own sigla. |
| `define_from_canon` | Where the canon defines a term, by its own definitional formulae. |
| `verify_citation` | Byte-compares a quotation against its URN. |

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
  coverage is not a small canon.
- **`mode`** — `phrase` is strong evidence; `ngram` is a character-window fallback.
- **`addressing`** — `canonical` is checkable against a printed edition; `derived` is
  not, because that source has no printed page and line.
- **`bake_id`** — which corpus snapshot answered.

## Reader deep-links

`search` hits and `get_passage` responses carry a `reader` block pointing into the
published edition, so checking a citation is one click rather than a trip to a library.

```json
"reader": {
  "edition": "CBETA Online",
  "url": "https://cbetaonline.dila.edu.tw/en/T0262_001",
  "granularity": "juan",
  "linehead": "T09n0262_p0001a05",
  "verified": false
}
```

Three deliberate limits, all of them in the payload rather than only in this file:

- **`granularity: "juan"`** — the link opens the fascicle. CBETA Online has no
  line-addressable URL, so `linehead` carries the exact line in CBETA's own citation
  string, which pastes into the reader's Goto box.
- **`verified: false` is literal, not modesty.** CBETA Online and SAT are SPAs that
  resolve content in the browser: both return HTTP 200 with a **byte-identical body**
  for a real path and for nonsense. There is no server-side signal, so a link checker
  would be theatre. Measured, not assumed.
- **No template, no link.** `reader` is absent for any source whose format has not been
  confirmed against real pages — SAT included, until task #14 ingests it and the format
  can be checked against real identifiers. A plausible link to the wrong passage is
  worse than none, because nothing about it looks wrong.

The `linehead` construction is cross-checked against CBETA's own TEI file naming
(`T09n0262.xml` encodes the same volume and number) for **all 2,471 works**.

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
