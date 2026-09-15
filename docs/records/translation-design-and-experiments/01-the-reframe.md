# Archived TRANSLATION.md: translation-design-and-experiments — chapter 1

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../translation-design-and-experiments.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

# Archived TRANSLATION.md: translation-design-and-experiments

> Captured from `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc` on 2026-09-15. This is retained evidence, not current instructions. Prices, deployment claims, proposed APIs and outcomes below were not revalidated.
> [Current guide](../../TRANSLATION.md) · [Documentation](../../README.md)

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

## Getting text to a model and back — `export` / `import`, built 2026-09-02

Two tasks and a sidecar, in the shape `mix pramana.embed.export` / `import` already
established, because the problem is the same one: the model runs on a rented GPU and the
text has to make a round trip it can be held accountable for.

```
mix pramana.translate.export --covered-by patton --limit 300 --out /tmp/bakeoff.jsonl
modal run priv/embed/modal_translate.py --arm mitra
mix pramana.translate.import --in /tmp/renderings-mitra.jsonl --translator-id model:mitra
```

**`--covered-by` selects chunks a named human already renders**, which is what a bake-off
needs: every generated passage then has a human rendering to be blinded against, and the
arms are scored on the same passages the human is scored on.

**The sha256 travels with the text**, so `import` can prove a rendering still describes
the passage it names — a chunk re-chunked between export and import is rejected and
counted, never attached to whatever now occupies that id. And what comes back is stored
`tier: "t1"`, `method: "llm"`, range-anchored to the chunk's ordinal span. It is not
citable as source and cannot be made so by this path; that is invariant #8, and
`Pramana.Guard` is where it is enforced rather than here.

`Pramana.Translate.Transfer` holds both directions. The Python side is handed text and
returns text — see `docs/ELIXIR.md` § 3 for why that is inference rather than a second
exception.

---
