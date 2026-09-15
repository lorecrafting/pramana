# Adding Your Own Texts

**Working directory:** `pramana/` for the commands and source-relative paths below.
Shared policy and the active plan remain at repository `docs/`. Existing corpus,
models and virtualenvs are not moved: see [layout migration](../../docs/LAYOUT_MIGRATION.md).

## Three different things, three different answers

| what | how often | mechanism |
|---|---|---|
| **A new canonical source** (SAT, bilara, 84000) | rare | one file per work → three `Pramana.Pipeline` behaviours + a registry entry; otherwise a dedicated `mix pramana.<source>.ingest`. Both add a `Pramana.Sources` entry. See [the source invariants](INVARIANTS.md) |
| | | **First, group the file list by work id and look at the groups larger than one.** "One file per work" is a claim about the source, not a default: three of four sources here break it, and CBETA breaks it in one collection out of two. A work loaded once per file keeps whichever file finished last, resolves, and verifies clean — see `Pramana.Bake.WorkList` and `IR.concat/1`. |
| **A one-off text** (a modern commentary, a translation, a teacher's talks) | often | drop a folder with a manifest, run one command |
| **A correction or annotation** to existing text | often | a *layer* over the bake, never an edit to it |
| **A translation of something already here** (a better English Lotus, a sangha's published rendering, another model's output) | **the one this table used to answer wrongly** | renderings into the pool against **existing anchors** — no new text, no new work id, nothing replaced. `docs/TRANSLATION.md` |

**The fourth row is a distinction the row above it hides.** A modern commentary is a new
text and gets a work id. **A translation of the Lotus Sūtra is not a new text** — it is a
set of renderings over T0262's existing anchors, and treating it as a one-off text would
mint a second work id for a sūtra this corpus already holds, breaking every parallel,
quotation and commentary link that points at the original.

The pool is keyed on `anchor_urn + lang + translator_id`, so **a new rendering enters
alongside rather than replacing**, needs no permission from whoever is already there, and
`Pramana.Translations.select/2` with `mode: :compare` returns the whole pool instead of
picking a winner. That is deliberate: where translators disagree, the disagreement is the
evidence, and a corpus that silently picks one has destroyed it. Same refusal
`Pramana.TermAnchors` makes about vocabulary and `compare_witnesses` about variant
readings. See `docs/TRANSLATION.md` § "The translation layer is meant to be replaced".

The first is correct as it stands — a new corpus genuinely has its own format and its own
citation grammar, and that is code. The second is what most people mean, and it should
never require touching Elixir. This document is mostly about the second.

---

## The answer to "should this be in MCP?" is **no**

Worth stating plainly, because it is tempting and it would quietly break the project.

**The MCP surface is read-only, deliberately.** If a model could add texts to the corpus:

- The corpus would stop being reproducible from `sources.lock.json` — invariant #3 gone.
- Uncontrolled writes would break the link between declared source inputs and loaded text.
  `bake_id` already does not freeze all derived retrieval state; see [architecture](ARCHITECTURE.md#identity-and-replay).
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

# Which CANON this text belongs to. Optional, and NOT the same thing as
# composition_origin above — a Pāli sutta and a Derge sūtra are both `indic` in origin
# and belong to different canons. Declaring it means the text competes INSIDE that canon
# when a caller asks for per-tradition retrieval; omitting it makes the text its own
# tradition, which is the conservative default and never folds it into a canon nobody
# said it belonged to. One of: chinese, pali, tibetan.
tradition: chinese

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

The original operator used an external `huangnianzu-translation` checkout and a
`scripts_split_pages.py` proofreading workflow. Those files are **not supplied by this
repository**. Inspect available extraction evidence instead of assuming that local path exists.

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
- Changed source inputs can change `bake_id`; repeating the same validated inputs need not.
  Identity does not by itself prove that all writes completed or all prior citations remain resolvable.
