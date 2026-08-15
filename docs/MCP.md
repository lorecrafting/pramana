# The MCP Surface

The product boundary. A model never touches Postgres — it sees these five tools and two
resources, and everything they return is URN-addressed so it can be independently
re-checked.

**Read-only, permanently.** Tools read; the CLI writes. `docs/ADDING_TEXTS.md` explains
why, and `CLAUDE.md` invariant #7 makes it binding.

## Tools

| tool | for |
|---|---|
| `search` | **Hybrid by default** — lexical fused with semantic by RRF. The normal entry point. |
| `survey_corpus` | Exhaustive counts, not a ranked sample. The tool that supports claims about *how often* or *where*. |
| `get_passage` | One URN, optionally with `context_before` / `context_after`. |
| `get_outline` | A work's structure without its text. |
| `verify_citation` | Byte-compares a quotation against its URN. |

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
