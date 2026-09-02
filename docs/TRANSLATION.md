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

## Two PURPOSES, and the bar is different — decided 2026-09-02

The tiers above are about **provenance**: who made a rendering and whether it reproduces.
Cutting across them is a second axis nobody had named, and it decides most of E1's budget:
**is this English going to be matched against, or read?**

| purpose | who consumes it | the bar | served to a person |
|---|---|---|---|
| **index** | the retriever | does an English question reach the right line | **never** |
| **reader** | a person, or a model quoting to a person | is this a faithful rendering | yes, labelled |

**They are not the same product and must not be generated to the same spec.**

### Index English does not have to be readable, and may not want to be prose

`CLAUDE.md`'s thesis is that the LLM is a swappable reader; the consumer of retrieval is a
model, and models read Classical Chinese. So English in the vector index exists to make a
passage **findable**, and nothing more. Three consequences:

  * ~~It may be better as a dense gloss.~~ ▸ **TESTED AND REJECTED, 2026-09-02.** The
    hypothesis was that terms, names and doctrinal vocabulary with no connective tissue
    would pack more retrievable surface per token. Measured against 150 pairs where one
    human translator's rendering queries another's of the same chunk: **prose keeps a
    margin of 0.0989 over the best distractor and dense keeps 0.0549**, and dense beats
    every distractor in 86.7% of pairs against prose's 99.3% — for 53% of the length.
    Recovering that loss needs roughly double the coverage, which costs more than the
    tokens saved. **Generate prose.**

    Two limits on that verdict. It tested *mechanically stripped prose*, not a
    purpose-written gloss — a model asked for "the terms and names in this passage" would
    write something different and probably better. And BGE-M3 is trained on natural
    language, so removing function words moves the text off-distribution; another
    embedder might not care. `docs/PROXIES.md` carries the test, including the first
    version that queried itself and reached the same verdict for free.
  * The acceptance test is `mix pramana.recall --renderings --to cbeta.T`, not a human.
    That removes a review bottleneck from the middle of the budget.
  * Glossary-pinning is still essential, for a *retrieval* reason: 方便, 權 and 善巧 must
    land on one English target or a query for "skilful means" finds one of the three.

### Reader English is a different obligation

The moment a rendering is shown, its fidelity is ours. It is generated on demand for
passages somebody actually opens — small volume, high bar — and it carries the term chain
so a reader can audit the choices: 空 ← *śūnyatā* ← "emptiness".

`glossary_compliance` and `consensus_score` exist on the row for this and are NULL on all
244,763 today, because every rendering held is human and there has been nothing to score.
They become the mechanical half of the bar:

  * **Terminology compliance** against the pinned glossary. Not proof of meaning — but
    **doctrinal error concentrates in word choice.** Whether *anattā* is 無我 or 非我 is
    one of the largest disputes in the tradition and it is a term decision, checkable
    against a table.
  * **Consensus** against a human rendering of the same anchor where one exists — Patton
    over the Āgamas, Sujato through any Pāli parallel. Systematic drift becomes a number.

---

## What this system guarantees, and what it does not

Stated here because it is the honest boundary of the whole design, and it belongs on the
page rather than in a doc nobody reads.

**Guaranteed, and model-independently:** the passage exists at the address given; the
quoted text is byte-identical to the witness, re-resolved and sha256-compared rather than
trusted; the provenance is right, so a Kamakura commentary cannot arrive dressed as an
Indian sūtra; frequency and absence claims are re-executed rather than believed; and no
generated rendering can be presented as source.

**Not guaranteed:** that the English beside those words is a faithful rendering of them.
A model can retrieve a line correctly, cite it correctly, byte-verify it, and then
paraphrase it into something the Chinese does not say — and every mechanical check here
passes. **The guard proves the citation, never the interpretation.**

So the claim this project can make is precise and worth making exactly: *you are reading
the canon's actual words, at an address you can check.* Anything about what they mean is
the reader's, or a translator's, and is labelled as such.

**Stating the limit is the same discipline that makes the rest trustworthy** — the checker
already reports which citations it could not verify rather than quietly passing them, and
this is that habit applied one level up.

---

## The translation layer is meant to be replaced, and the pool already allows it

A consequence of the pool being keyed on `anchor_urn + lang + translator_id`, worth saying
out loud because it shapes what other people can build on this.

**Nothing has to be adopted to be useful.** A better translation layer — somebody else's
model, a scholar's revision, a sangha's published rendering — enters as another
`translator_id` alongside what is here, with its own tier, method, licence and attribution.
It does not replace anything, it does not need permission, and `Translations.select/2` with
`mode: :compare` returns the whole pool rather than a winner.

That is the same refusal `Pramana.TermAnchors` makes about vocabulary and
`compare_witnesses` makes about readings: **where people disagree, return the disagreement
with its attribution.** A translation is an argument about a passage, and a corpus that
silently picks one has destroyed evidence.

Three things follow for anyone building on this:

  * A competing layer can be **composed** rather than merged — mounted in the same client,
    or ingested and served beside ours with both visible.
  * If one is better, `divergence_score` and `consensus_score` are how that gets
    demonstrated rather than asserted.
  * The corpus is the stable thing. **Renderings are expected to churn**, and the URN a
    rendering hangs off does not, which is why a rendering is a fragment over a source
    anchor and never a top-level address.

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
