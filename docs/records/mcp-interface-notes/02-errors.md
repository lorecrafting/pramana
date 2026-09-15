# Archived MCP.md: mcp-interface-notes — chapter 2

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../mcp-interface-notes.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

## Errors

Every failure returns an MCP error whose body is **JSON in the same shape a result uses**, so
a caller needs one parse rather than two:

    {"error": {"reason": "bad_urn", "message": "Malformed URN: … Expected pramana:<source>…"},
     "bake_id": "…",
     "replay": {"tool": "get_passage", "arguments": {"urn": "…"}}}

**Branch on `reason`, read `message`.** The sentence is written for a person and is free to
improve; `reason` is the contract. Distinguishing `bad_urn` (your mistake) from `not_found`
(a fact about this bake) previously required matching on English.

A failure carries `bake_id` and `replay` for the same reason a result does: *"no passage
exists at this URN"* is true of **this** corpus and may be false of the next, so the refusal
is as replayable as an answer.

Reasons in use: `bad_urn`, `not_found`, `work_not_found`, `unknown_authority_id`,
`range_not_supported`, `empty_query`, `search_failed`, `survey_failed`.

## Verifying a whole report, not just a quotation

`verify_citation` answers one question about one URN. `verify_report` answers it for every
citation in a document **and re-executes the retrievals its figures rest on** — which is the
half a citation guard structurally cannot reach:

| claim | guard | `verify_report` |
|---|---|---|
| "T0262 says X" | ✅ | ✅ |
| "X appears 36,775 times across 1,904 works" | ✗ | re-runs the survey |
| "no Japanese-composed text uses X" | ✗ | re-runs the search, confirms still empty |

**Writing a report this can check** costs nothing extra, because the evidence is a field you
already received. Every response carries `replay: {tool, arguments}` beside `bake_id`; put it
next to the claim it supports:

    ```pramana-replay
    {"tool": "survey_corpus",
     "arguments": {"query": "一切眾生"},
     "bake_id": "b143d7f3…",
     "assert": {"total": 36775, "works": 1904}}
    ```

`assert` names response keys and the values you are claiming for them; a dotted path reaches
into nested maps. Omit it and the call is still re-run — proving the retrieval you cited
still executes and still returns something is worth stating on its own.

**Read the verdicts precisely:**

| verdict | meaning |
|---|---|
| `verified` | re-executed, every asserted value re-derived |
| `failed` | a value differs — both numbers are named |
| **`unverifiable`** | recorded against a different `bake_id`. The corpus changed and the claim **cannot be re-run here**: not refuted, and not passed |
| `error` | the tool is unknown, or it raised |

`unsourced_figures` is a **heuristic warning list, never a verdict** — paragraphs carrying a
number with no citation and no replay record. It reads; it does not judge.

Two limits worth knowing before you rely on it. Only read-only tools are runnable, from an
explicit whitelist — a replay record is untrusted input naming tools chosen by whoever wrote
the report, and `verify_report` is deliberately absent from its own list. And there is a cap
on replays per report; records beyond it are reported as skipped and **prevent `ok?`**,
because a report whose evidence was not all examined has not been verified.

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
