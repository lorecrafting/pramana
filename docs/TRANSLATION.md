# Translation: Baked Layers, On-the-Fly, and Model Multiplicity

## The reframe

The worry is: *"different LLMs will translate differently — which one wins?"*

**Don't resolve it. Make multiplicity first-class, and mine it for signal.**

This corpus is already natively multi-translation, and always has been. The Chinese
canon contains 2–6 translations of the same Sanskrit work (異譯本 — the Lotus Sūtra
three times). SuttaCentral carries Sujato, Bodhi, Thanissaro, and Horner on the same
suttas. There has never been "the" translation of anything here.

So model disagreement isn't a defect introduced by LLMs. It's the normal condition of
the field, and we already have to build machinery to handle it for the human case.
Machine translations slot into the *same* apparatus — same tables, same comparison
tooling, same UI. The translator-fingerprinting work in Phase 6 and the multi-model
problem are one problem.

There is no "the English translation" in the schema. There is a **pool**, and queries
supply a **selection policy** rather than expecting a value.

---

## Three tiers

| Tier | What | Reproducible | Embedded | Citable as translation |
|---|---|---|---|---|
| **T0 human** | Sujato, Bodhi, 84000, published translators | yes | yes | yes, attributed to a person |
| **T1 baked** | Generated during a bake; pinned model + prompt + glossary | yes | **yes** | yes, attributed to a model+config |
| **T2 ephemeral** | Generated at query time | no | **no** | shown, but marked provisional |

All three live in one logical pool keyed by `anchor_urn + lang + translator_id`, where
`translator_id` is `"sujato"` or `"model:claude-opus-5@prompt-v3+glossary-ddb2"`.
A human and a model are the same kind of thing to the schema, differing in metadata.

Invariant from `LAYERS.md` still holds throughout: **no tier is citable as *source*.**
A translation is always a rendering of a source anchor.

---

## Why ephemeral output does not go straight into the bake

This is the important structural decision.

`bake_id = sha256(sources.lock + pipeline_version + config)` is only meaningful if the
bake's contents are determined by that hash. If query-time translations were written
into the baked pool, two people with the same `bake_id` would have different corpora,
and reproducibility — the whole point of the decoupling — quietly dies.

So there are two tables with two lifecycles:

```
translations             -- the pool. Part of the bake. Immutable per bake_id.
  anchor_urn, lang, tier, translator_id, method
  model_id, prompt_version, glossary_id, bake_id
  text
  review_state           raw | machine_verified | human_reviewed | approved
  glossary_compliance    float   -- deterministic check
  consensus_score        float   -- agreement with other renderings

translation_candidates   -- a cache. NOT part of the bake. Append-only.
  cache_key = hash(source_sha256, lang, model_id, prompt_version, glossary_id)
  anchor_urn, lang, model_id, prompt_version, text
  hit_count, first_seen, last_seen
  promoted_to            FK -> translations.id, nullable
```

Candidates are cached and reused — the same passage requested by a hundred users costs
one translation — but they are excluded from embeddings and clearly marked provisional.

---

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

- **Phase 3** — pool schema (`translations`), tiers, selection policy. Comes free with
  `bilara-data`, which is already multi-translator.
- **Phase 6** — divergence scoring, unified with 異譯本 translator fingerprinting.
- **Phase 7** — ephemeral generation, candidate cache, promotion pipeline, full-corpus
  baked translation.
