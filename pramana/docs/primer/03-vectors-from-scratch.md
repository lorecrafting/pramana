# Primer: What This System Is, How It Works, and What Everything Is Called — chapter 3

> Learning chapter. Corpus figures are recorded examples, not a live inventory; current contracts are in the architecture guide.
> [Contents](../PRIMER.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

### Vectors, from scratch

An **embedding** is a list of numbers representing a piece of text's meaning. In this
system each chunk becomes **1,024 numbers** — a point in 1,024-dimensional space.

The useful property: **texts that mean similar things land near each other**, even with no
words in common. "The cessation of suffering" and 苦滅 land close together despite sharing
no characters and not even a writing system.

To compare two texts you compare their vectors arithmetically. This project uses **inner
product**, one of several standard distance measures; the vectors are normalised, which
makes inner product equivalent to cosine similarity but cheaper.

### The model

**BGE-M3** is the embedding model — a neural network that takes text and returns those
1,024 numbers. It is multilingual, which is why it can place Chinese and English near each
other at all.

Two honest limits, stated in the code:

- BGE-M3 is **not specifically trained on Literary Chinese**. Whether it is the right
  model here is an open question, and turning that opinion into a measurement is exactly
  what the Phase 4 evaluation harness (#19) is for.
- **Vectors from different models cannot be mixed.** Every value is a valid float; nothing
  fails loudly; ranking silently corrupts. The model id is stored with every vector and
  mismatches are refused.

### Why a GPU, and the export/import round trip

Embedding 299,317 chunks on a laptop takes roughly 65 hours. On a rented **L4 GPU** via
**Modal** (a service that runs code on cloud GPUs on demand) it takes **34 minutes and
about $0.45**.

Rather than ship the corpus and a database to the GPU, the system exports **text** and
imports **vectors**:

```
export  chunks → JSONL file of {id, content, sha256}
        ↓ (upload)
remote  run BGE-M3 → JSONL of {id, vector}
        ↓ (download)
import  re-check sha256 → write vectors
```

The sha256 re-check is the point. If the corpus were re-baked between export and import,
the text a vector was computed from no longer exists, and that vector is **wrong for the
chunk it claims to describe** — while looking completely normal, because it is still 1,024
valid floats. Check, refuse, and report which rows disagreed.

### Multi-vector embeddings (in progress, #40)

A chunk can carry more than one vector:

| kind | what it is | status |
|---|---|---|
| `source` | the passage as printed | built |
| `translation` | the same span in English, one per translator | being built |
| `question` | hypothetical questions the passage answers | deferred to Phase 7 |

The reason is the system's weakest axis: **an English question reaching Literary Chinese**
depends entirely on the multilingual model's cross-language space, which is unproven here.
Embedding the English translation alongside gives the English query an English target,
while the result still resolves to the original-language anchor. `question` vectors would
need an LLM generation pass over 300k+ chunks; spending that before there is an evaluation
harness to measure whether it helps would be spending blind.

---

## 10. Stage 6 — Retrieve

There are two ways to find a passage, and they fail in opposite directions.

### 10.1 Lexical search — matching characters

Find passages containing the characters you typed. Fast, exact, and explainable.

Literary Chinese has no spaces between words, so the usual "split on whitespace" indexing
does not apply. The system uses **pg_bigm**, a PostgreSQL extension that indexes every
**bigram** (adjacent character pair). 佛性 is indexed as itself; a search for it finds
every passage containing those two characters adjacently.

**Where it fails:** 佛性 ("buddha-nature") will not match 如來藏 ("tathāgata-garbha") even
though they name the same doctrine. And a query in the wrong orthography returns nothing
at all — which is why there is **variant-character normalization**: 眾/衆/众 are the same
character in different historical forms, and a query using one form must find passages
using another. The system holds 6,447 variant classes derived from the Unicode Han
database. Before that existed, searching 众生 returned 0 results where 眾生 returned
thousands, silently.

### 10.2 Semantic search — matching meaning

Embed the query, then find the chunks whose vectors are nearest.

Comparing against all 299,317 vectors exactly would be slow, so pgvector builds an
**HNSW** index (*Hierarchical Navigable Small World*) — a graph structure that finds
approximate nearest neighbours very fast. This is called **ANN**, approximate nearest
neighbour: you trade a small chance of missing a result for a very large speed gain.

**The trap this project hit:** if you ask an ANN index for 20 results and *then* filter
them (say, to one division of the canon), you may be left with 3, because the index found
20 globally-nearest neighbours and 17 were filtered away. It looks like the corpus has 3
matches. It doesn't. The fix is pgvector 0.8's **iterative scan**
(`hnsw.iterative_scan = relaxed_order`), which keeps walking the graph until it has enough
results that survive the filter. Any query combining a vector ordering with a selective
`WHERE` needs this, and it will keep being true as the corpus grows.

### 10.3 Hybrid — using both

Lexical is precise but literal; semantic is flexible but fuzzy. **Hybrid search** runs
both and merges the rankings using **RRF** (*Reciprocal Rank Fusion*).

RRF is deliberately simple: for each result, score `1 / (k + rank)` in each list, with
`k = 60`, then add the scores. A passage ranked #1 by lexical and #30 by semantic beats one
ranked #10 by both. Crucially it uses only **ranks**, never the raw scores — so it does not
matter that a bigram similarity and an inner product are not on comparable scales.

Hybrid is the default entry point. A real example: querying 眾生皆能成佛 ("all beings can
become buddhas") — a paraphrase appearing nowhere as a literal string — returns
故眾生無不成佛 at 0.817 similarity. The bigram index structurally cannot find that.

---

## 11. Stage 7 — Resolve and verify

### Resolve

**Resolution** is turning a URN back into the passage it addresses. Give
`pramana:sc.ms:mn1@1.1`, get back `Evaṁ me sutaṁ—` with its hash, offsets and provenance.

### The citation guard

The **guard** is the component that makes the whole project's promise real. It:

1. extracts every URN from a block of generated text
2. re-resolves each one against the corpus
3. **byte-compares** any quoted text against what is actually there

It runs **after** generation and **outside** the model. Nothing about it depends on which
model produced the text, so it works identically for any model, now or later.

The comparison is exact after trimming whitespace — deliberately not fuzzy. "Close
enough" is exactly how a misquotation survives review.

Its verdicts:

| verdict | meaning |
|---|---|
| `:ok` | the URN resolves and the quote is really there |
| `:bad_urn` | malformed address |
| `:not_found` | well-formed, but addresses nothing — do not cite it |
| `:quote_mismatch` | the passage exists; the words are not what was claimed |
| `:not_citable_as_source` | it is a machine translation being presented as scripture |

It also reports `existence_only` — citations with no recognisable quotation were checked
only for *existence*, which is a materially weaker guarantee, so it is never folded into
"verified".

**What it deliberately does not do:** judge whether a citation *supports* the claim it is
attached to. That is interpretation. The guard answers only the mechanical question, and
its value lies in that answer not being fuzzy.

### One level up: verifying a whole report

The guard checks the citations and quote formats it recognizes; it does not make all
fabricated or unsupported prose impossible to pass off. It does not by itself verify the
claims that actually carry a piece of scholarship:

| claim | guard | what checks it |
|---|---|---|
| "T0262 says X" | ✅ byte-compare | the guard |
| "X appears 36,775 times across 1,904 works" | ✗ | re-run the survey and compare |
| "no Japanese-composed text uses X" | ✗ | re-run the search and confirm it is still empty |

The second and third are where a report goes wrong in the way that matters, because **a
frequency claim generalised from twenty ranked hits reads exactly like one counted over
twelve million segments.**

What makes checking them possible is that every tool response carries
`replay: {tool, arguments}` beside its `bake_id` — so a retrieval is *citable* in the same
way a passage is. A report includes that record next to the claim it supports, and
`verify_report` re-executes it:

    ```pramana-replay
    {"tool": "survey_corpus", "arguments": {"query": "一切眾生"},
     "bake_id": "b143d7f3…", "assert": {"total": 36775, "works": 1904}}
    ```

The verdict worth understanding is **`unverifiable`**. If the record names a different
`bake_id`, the corpus has changed and the claim *cannot be re-run here* — so it is neither
confirmed nor refuted. Calling that a false report would be wrong, and it would also be
corrosive: a checker that cries wolf is one people stop reading, which is what happened to
`integrity` while it reported 1,228 X texts as broken.

**This is deliberately not an agent.** The model stays swappable and the MCP surface stays
read-only; what the project ships is the thing that makes *any* agent's report checkable.
And the verification is arithmetic, not a vote — re-running a survey is stronger evidence
than a panel of models agreeing with each other about it.

---

## 12. Addressing: the URN scheme

A **URN** (Uniform Resource Name) is a permanent identifier. This project's grammar:

```
pramana:<source>.<witness>:<work>[@<locator>[-<locator_end>]][#tr:<lang>/<translator>]
```

Examples:

```
pramana:cbeta.T:T0262_009@p0037a13                 Lotus Sūtra, juan 9, page 37a line 13
pramana:cbeta.T:T0262_009@p0037a13-p0037b02        a range, verified as one unit
pramana:sc.ms:mn1@1.1                              Majjhima Nikāya 1, segment 1.1
pramana:sc.ms:mn1@1.1#tr:en/sujato                 Sujato's English *of* that segment
pramana:local-huang-nianzu-jie:jie@sec12.p3        a locally-added commentary
```

| component | meaning |
|---|---|
| `source` | who published the data — `cbeta`, `sc`, `sat`, `local-…` |
| `witness` | which physical edition — `T` (Taishō), `ms` (Mahāsaṅgīti) |
| `work` | the text's own identifier |
| `locator` | the address within the work, in the tradition's own grammar |
| `#tr:…` | a *rendering* fragment — see below |

A **witness** is a manuscript or printed edition testifying to a text. The same work
survives in several, and they differ. Naming the witness in the address means a citation
says not just "the Lotus Sūtra" but "the Lotus Sūtra as printed in the Taishō".

### Why translations are a fragment

A translation is addressed as `<anchor>#tr:en/sujato` — a fragment *hanging off* a source
address, never a top-level URN of its own.

This is structural enforcement of the rule that **a translation is never citable as a
source**. Strip the fragment and you are holding a real source citation. There is no way
to hold a rendering alone, so there is no way to accidentally present one as the text.
