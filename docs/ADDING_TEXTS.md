# Adding Your Own Texts

## Three different things, three different answers

| what | how often | mechanism |
|---|---|---|
| **A new canonical source** (SAT, bilara, 84000) | rare | one file per work → three `Pramana.Pipeline` behaviours + a registry entry; otherwise a dedicated `mix pramana.<source>.ingest`. Both add a `Pramana.Sources` entry. See `CLAUDE.md` |
| **A one-off text** (a modern commentary, a translation, a teacher's talks) | often | drop a folder with a manifest, run one command |
| **A correction or annotation** to existing text | often | a *layer* over the bake, never an edit to it |

The first is correct as it stands — a new corpus genuinely has its own format and its own
citation grammar, and that is code. The second is what most people mean, and it should
never require touching Elixir. This document is mostly about the second.

---

## The answer to "should this be in MCP?" is **no**

Worth stating plainly, because it is tempting and it would quietly break the project.

**The MCP surface is read-only, deliberately.** If a model could add texts to the corpus:

- The corpus would stop being reproducible from `sources.lock.json` — invariant #3 gone.
- `bake_id` would stop determining contents, so two people with the same id could hold
  different corpora.
- An agent could introduce text that is later cited as canonical.
- **Prompt injection becomes corpus poisoning.** Text from a locally-added source is
  already treated as untrusted input (`docs/CHECKS.md`); letting a model *write* that
  text closes the loop in the worst way.

**Tools read. The CLI writes.** That separation is what keeps the citation guard
meaningful — the guard verifies against a corpus that a human deliberately built.

A *proposal* flow is defensible later: an agent drafts a manifest for review, a human
runs the bake. The draft is a file, not a database write.

---

## The workflow (task #16)

```
sources/local/huang-nianzu-wlsj/
  manifest.yaml
  text/
    01-preface.md
    02-chapter-01.md
    …
```

```bash
mix pramana.local.validate sources/local/huang-nianzu-wlsj   # writes nothing
mix pramana.local.add      sources/local/huang-nianzu-wlsj   # hashes, bakes, re-bakes id
```

Validate first, always, and it must write nothing. Getting provenance wrong is the
failure this project exists to prevent, so the checking step is separable and cheap to
re-run.

### The manifest

```yaml
id: huang-nianzu-wlsj-jie
title: 佛說大乘無量壽莊嚴清淨平等覺經解
title_en: Commentary on the Infinite Life Sūtra
author: 黃念祖

provenance:
  composition_origin: chinese
  text_role: commentary
  date_range: [1980, 1995]
  attribution_confidence: certain

# What it explains. Feeds work_relations (task #36).
comments_on:
  work: xia-lianju-conflation
  relation: comments_on
  confidence: certain
  method: manifest

license:
  class: restricted          # DEFAULT for local sources — see below
  redistributable: false
  note: "Modern work, in copyright. Personal study only."

citation:
  grammar: section-paragraph  # no canonical page/line exists
  addressing: derived

format: markdown
```

### Defaults that are deliberately conservative

- **`license.class` defaults to `restricted`.** Most one-off texts people add are modern
  and in copyright. Defaulting to permissive would be a licence violation waiting to
  happen; defaulting to restricted merely excludes it from any public surface.
- **`addressing: derived`.** A local text has no printed page and line, so its URNs
  cannot be checked against an edition. Retrieval says so, and never lets a derived
  reference pass as canonical.
- **Provenance is required, not inferred.** No division table applies here, and guessing
  is worse than a gap.

---

## Addressing: three levels, not two

This document originally offered `canonical` or `derived`. The first real text needed a
middle term, and using `derived` for it would have understated what a reader can check.

| value | meaning |
|---|---|
| `canonical` | anchored to a published digital critical edition (CBETA/Taishō) |
| `edition_page` | anchored to a page number **printed in the physical book**, recovered by our extraction. A reader with the book can turn to it; the risk is our extraction, not the anchor |
| `derived` | no intrinsic anchor; positions come from file structure and shift when the file changes |

**Use the highest level the source actually supports.** The Huang Nianzu commentary
prints its page numbers, so its URNs are `…@p0100`, not `…@sec12.p3`. That is the same
rule as adopting Taishō page/register/line rather than inventing ids — invariant #2
applies to local texts too.

`edition_page` requires `citation.anchor_source`, because "a reader can turn to this
page" is only checkable if the manifest says what the numbers are.

Addressing is **declared and stored**, not inferred from the source id. Inferring it
collapsed `edition_page` into `derived` and reported the weaker claim for both.

## The honest problem: derived URNs are only as stable as your file

A Taishō citation is stable because the printed page exists and will not change.
`…@sec12.p3` is stable only while `02-chapter-01.md` does not change. Insert a paragraph
and every anchor after it shifts — silently, and old citations now point somewhere else.

Mitigations, in order of value:

1. **The manifest pins a per-file `sha256`**, exactly as `sources.lock.json` does for
   upstream sources. Re-adding changed text is a **new bake**, and the tool must say
   loudly that anchors moved rather than quietly renumbering.
2. **Prefer intrinsic anchors when the text has them.** If the source has numbered
   sections, chapter headings, or an existing citation convention, use it — the same
   principle as adopting Taishō page/line rather than inventing ids.
3. **Treat the text files as immutable once added**, like `raw/`. Corrections become a
   layer, not an edit.

This is a genuine limitation, not something to paper over. It is also why the local path
is separate from the canonical one: canonical sources get checkable citations, local ones
get honest approximations that are labelled as such.

---

## PDFs

The Huang Nianzu source is a 4.3 MB PDF, which is the common case, and it needs an
explicit extraction step rather than a hidden one:

```
PDF → page images / text → proofread markdown → sources/local/<id>/text/
```

Extraction is lossy and its quality is provenance data. When that lands it should record
what did the extraction and how confident it is, the same way `attribution_confidence`
does — an OCR'd text and a hand-proofread one are not the same evidence, and search
results should be able to say which they are.

Your `~/dev/huangnianzu-translation` already has `scripts_split_pages.py` and a
proofreading workflow for exactly this text. **Read it before writing ours** (task #34).

---

## GUI, later

Worth building eventually — metadata entry is fiddly and a form beats hand-written YAML
for anyone who is not the author of this document. Two rules if it happens:

- **The GUI writes the manifest file; the CLI still runs the bake.** Anything else puts
  corpus mutation behind a web request and loses reproducibility.
- It should show the *effects*: which provenance axes are set, what URNs will look like,
  what the licence gating will exclude. Most manifest mistakes are invisible until
  something is mis-cited months later.

---

## Summary

- **Now:** implemented. `mix pramana.local.validate` then `mix pramana.local.add`.
- **Then:** a folder plus a manifest, `validate` then `add`.
- **MCP: read-only, permanently.** Agents query the corpus; humans build it.
- **GUI: eventually, to author manifests** — never to mutate the corpus directly.
- Adding text always produces a **new `bake_id`**, because it is a different corpus.
