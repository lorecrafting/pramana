# Archived TRANSLATION.md: translation-design-and-experiments — chapter 2

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../translation-design-and-experiments.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

## The promotion pipeline

This answers "can on-the-fly translations get pooled?" — yes, through an explicit gate,
not silently.

An Oban job scores candidates and promotes the good ones into the *next* bake (the
`bake_id` changes, which is correct: new corpus content, new bake).

**Scoring, cheapest signals first:**

1. **Glossary compliance** — did it use the pinned term renderings? Fully
   deterministic, no model needed. Catches most bad output immediately.
2. **Cross-model consensus** — translate with 2–3 models; measure agreement. High
   agreement is strong evidence; disagreement is the interesting case (below).
3. **Back-translation** — render back to the source language, compare semantically to
   the original. A cheap sanity check, not proof.
4. **Human review** — required for `approved`. Nothing reaches T0-adjacent status
   without a person.

Promotion is what turns a translation into *retrieval* signal, since only baked
translations get embedded. That's the real incentive to run the pipeline: promotion
improves cross-lingual search, which is the system's weakest axis.

---

## Divergence as a feature, not a problem

Where models disagree, the passage is genuinely hard — ambiguous classical grammar, a
contested technical term, or textual corruption. That's worth surfacing, not hiding.

```
translation_divergence
  anchor_urn, lang
  n_renderings
  divergence_score      -- embedding distance + edit distance across renderings
  contested_terms       -- which terms specifically differ
```

Computed as a bake stage. Three payoffs:

- **A corpus-wide difficulty map.** "Show me where translators disagree" is real
  scholarship, and no one has it for this corpus.
- **It prioritizes human review.** Review the ~2% of passages where renderings
  diverge, not all 250M characters. This is what makes human-reviewed translation at
  canon scale actually tractable rather than theoretical.
- **It unifies with 異譯本 work.** Where Kumārajīva and Xuanzang differ is the *same*
  signal, computed the same way. One feature covers both.

---

## Selection policy at the API

Callers never get an implicit choice made for them:

```
translation_policy: {
  lang: "en",
  prefer: ["human", "baked", "ephemeral"],   # tier order; default
  translator: "sujato",                       # or pin one explicitly
  model: "claude-opus-5",                     # force a specific model
  mode: "single" | "compare",                 # compare returns the full pool
  allow_generate: true                        # may we spend tokens on a T2 miss?
}
```

`mode: "compare"` returning every rendering side by side, with divergence highlighted,
is arguably the most interesting reading experience this project can offer — and it
falls out of the schema for free.

For reproducibility, a session can pin a `translation_set` (a lockfile over
`translator_id`s) so a reading experience is stable. Answers cite
`bake_id + translation_set`.

---

## Cost and latency

Naive on-the-fly translation at 250M characters is ruinous. Constraints:

- **On-the-fly translates retrieved spans only** — you retrieved 10 passages, you
  translate 10 passages. Never a whole work synchronously.
- **Whole-work translation is a background Oban job** that notifies on completion.
- **Cache by content hash**, not by URN — identical text in different works
  (formulaic passages are pervasive in this corpus) translates once.
- **Elixir fits well here**: `Task.async_stream` for parallel span translation with
  bounded concurrency, Oban for background whole-work runs, Phoenix PubSub to stream
  partial results into the LiveView reader later.

### Four levers, and the order to reach for them

None of these is specific to a vendor, and none of the numbers is written down here —
rule 41 and the doc rule above it both say measure it, and a quoted price is stale the
week after it is quoted.

1. **Tier the work.** A whole-work translation is one job in name only: pinning glossary
   terms, extracting a byline, classifying a passage's genre and rendering the passage are
   different kinds of thinking with wildly different values. Bounded, repetitive extraction
   belongs on the cheapest model that passes its eval; **judgement — the rendering itself,
   and any adjudication between candidates — is where the expensive tokens earn their
   place.** Every job here already carries the metadata to tier it, because
   `translation_layers` records the model per rendering.
2. **Hold the prefix still.** A glossary-pinned prompt is mostly a *fixed* preamble — the
   term table, the register instructions, the provenance frame — with a small variable
   span at the end. Order it that way and the fixed part is cached across a whole-work run;
   interleave the variable part and it is not. This is a prompt-construction decision, not
   an infrastructure one, and it is invisible until someone measures a run.
3. **Batch what nobody is waiting for.** Whole-work translation is already an Oban job that
   notifies on completion, so latency is not a constraint on it. On-the-fly span
   translation is the opposite and must stay synchronous. The split already exists in the
   design above; the point is that it is also the cost split.
4. **Cache by content hash before any of the above.** Formulaic passages are pervasive in
   this corpus, and the cheapest token is the one not spent. This is first in value and
   listed last because it is the one already decided.

**Measure per work, not per corpus.** A projection from one sūtra to 250M characters is
the kind of extrapolation `docs/PROXIES.md` exists to record the failures of. Translate
one work, count what it actually cost, and publish the figure beside its denominator.

---

## The decoupling contract holds

The translation service is an ordinary **client of the retrieval API**, not a
privileged component. It reads source spans by URN and writes candidates. Any model
can perform it; swapping models changes a `translator_id`, not the corpus.

Which is the same principle as everywhere else here: the bake is the durable asset,
and models — including the ones doing the translating — are commodities.

---

## Prior art we already own

`~/dev/huangnianzu-translation` is a mature hand-built translation of the Huang Nianzu
commentary, and it independently arrived at much of the above. It has a
`Chinese | Pinyin | Canonical English | Notes` glossary with the rule that *every batch
must be checked against it before being marked complete*, plus `scripts_check.py` that
automates exactly the compliance check described here as the cheapest promotion signal.

Read it before implementing this section — it encodes lessons from a long manual
project, and its glossary is directly ingestible as seed data. **Task #34.**

Its reading rules are also the Phase 6 reading-exception table in embryo (道隱 →
*Dōin*, not *Daoyin*; 元曉 → *Wŏnhyo*, Korean not Japanese), including one entry that
states a reading is **unverified** and keeps pinyin rather than inventing one — the
same refuse-to-guess discipline as `provenance_for_volume/1` returning `nil`.

## Roadmap placement

- **Phase 3 — BUILT (#39).** `translations` with tiers, methods and review states;
  `Pramana.Translations` holds the selection policy; rendering URNs
  (`<anchor>#tr:<lang>/<translator>`) resolve through `Pramana.Corpus.resolve/1` so the
  guard checks them on the ordinary path. Seeded with 210,756 English renderings by 8
  translators from bilara-data, 4,601 anchors carrying more than one.

  Two things landed differently from the sketch above. **Licence is per rendering**, not
  per source: bilara-data is CC0 except one CC BY-SA 3.0 publication, and a publication
  cannot always be matched to the works it covers, so `license_class` (what we believe)
  and `redistributable` (what we will act on) are separate columns. And
  `translation_candidates` is deliberately *not* built — it has a different lifecycle,
  outside the bake, and belongs with the generation engine in Phase 7.
- **Phase 6** — divergence scoring, unified with 異譯本 translator fingerprinting.
- **Phase 7** — ephemeral generation, candidate cache, promotion pipeline, full-corpus
  baked translation.
