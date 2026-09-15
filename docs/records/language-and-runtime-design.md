# Archived ELIXIR.md: language-and-runtime-design

> Captured from `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc` on 2026-09-15. This is retained evidence, not current instructions. Prices, deployment claims, proposed APIs and outcomes below were not revalidated.
> [Current guide](../ELIXIR.md) · [Documentation](../README.md)

# Elixir/Phoenix — Fit, and the Three Exceptions

Verdict: **Elixir is a good choice here, not a compromise.** Roughly 90% of this
system is a better fit for BEAM than for Python. Three narrow components are not, and
they're isolated behind interfaces so they stay small.

## Where Elixir is genuinely the right tool

### The bake pipeline (the strongest case)

The bake is: fetch thousands of files, parse each independently, transform, embed,
load — with retries, backpressure, and per-item fault isolation. This is the canonical
BEAM workload.

- **Oban alone, and Broadway was dropped.** The original argument for Broadway was
  backpressure between stages, with the embedding sidecar as the slow one. It never earned
  its place: Broadway pays off when a slow stage must throttle an upstream *stream*, and the
  bake's input is a static list of 5,005 files. The dependency was removed on 2026-08-28
  after an audit found it declared, never referenced, and described as current by three
  documents — the same shape as the Tibetan `botok` dependency this file already records.
  `docs/ROADMAP.md` had the decision written down correctly the whole time.
- **Oban** gives durable, idempotent, resumable stages. A bake that dies at hour three
  resumes; it doesn't restart.
- **Per-file process isolation** means one malformed TEI file kills one job, not the
  run. In a Python pipeline this is a try/except you have to remember; here it's the
  default.
- **Real parallelism** across cores for XML parsing, with no GIL. This is the single
  biggest wall-clock win over a Python pipeline.

### Text handling

Elixir strings are UTF-8 binaries natively, with proper grapheme handling and
efficient binary pattern matching. For a project whose central risk is silent CJK
corruption, this is a real advantage. Binary pattern matching is also a clean way to
write the URN parser and the Taishō page/register/line grammar.

**Saxy** is a fast pure-Elixir SAX parser — stream TEI P5 without loading documents
into memory, and emit IR structs as you go.

### Postgres

`pgvector-elixir` supports HNSW index creation directly in Ecto migrations
(`create index("segments", ["embedding vector_cosine_ops"], using: :hnsw)`) and
provides `cosine_distance`, `max_inner_product`, `l2_distance`, and friends as Ecto
fragments. Ecto composes provenance filters with vector ordering in one query, which
is the single most important query in this system. No gap here.

### The API and MCP server

Phoenix is an excellent API layer, and **MCP is just JSON-RPC over Streamable HTTP** —
Phoenix serves that natively.

**Decision, resolved in Phase 0: `anubis_mcp`.** `hermes_mcp` was forked and rebranded
after the original maintainer left CloudWalk, and the fork is clearly the live one:
`hermes_mcp`'s last release was 2025-08-14 (a year stale) against `anubis_mcp` 2.0.0 on
2026-08-07, with roughly 7× the daily downloads. Hand-rolling JSON-RPC is no longer
warranted.

The fallback remains available if that ever changes — the MCP spec's core is small, and
the tool layer (`PramanaWeb.MCP.Tools.*`) is library-independent by construction, so
swapping transports would not touch the corpus or the guard.

### The web reader (Phase 8)

**LiveView is a better fit than React here.** A parallel-column reader with synchronized
scroll, variant-reading popovers, and clickable citations is server-state-heavy and
mostly read-only — exactly LiveView's strength. It also avoids maintaining a second
API client. fojin runs React against FastAPI; we get the same UI with one less layer.

---

## The three exceptions

Each is CPU-bound numerical or ML work with no viable BEAM implementation. All three
are narrow, and all three are replaceable.

### 1. CJK word segmentation → Rustler NIF

Chinese has no whitespace, so `jieba-rs` runs in-process via Rustler — no sidecar, and
available at both bake and query time.

**Measured caveat, and it changed the retrieval design.** jieba is trained on modern
Chinese and does not know Buddhist vocabulary:

    般若波羅蜜多心經  ->  ["般若", "波", "羅", "蜜", "多心", "經"]
    耆闍崛山          ->  ["耆", "闍", "崛", "山"]
    摩訶迦旃延        ->  ["摩", "訶", "迦", "旃", "延"]

It shatters transliterated Sanskrit into single characters and invents "多心". So
lexical retrieval does **not** fall back to jieba tokens; it falls back to character
n-grams, which need no dictionary (`Pramana.Retrieval.Lexical`). jieba is kept because
word boundaries genuinely matter elsewhere — 多音字 disambiguation in the Phase 6
reading layer is context-dependent, and the later modern-Chinese medical corpus is
much closer to jieba's training domain.

*Guard:* keep individual calls short or use a dirty CPU scheduler — a long-running NIF
blocks a BEAM scheduler thread.

### 2. Suffix-array text-reuse detection → standalone Rust binary

The quotation graph requires suffix-array/n-gram matching across 250M+ characters.
This is heavy, memory-hungry batch work that would be slow in Elixir and disruptive as
a NIF.

**Run it as a separate Rust binary invoked as a port**, writing results directly to
Postgres. Deliberately *not* a NIF: a multi-gigabyte working set does not belong
inside the BEAM VM. It's a bake stage, invoked once per bake, so process boundaries
cost nothing.

### 3. Model inference → Python sidecar (`priv/embed`)

**Restated 2026-09-02, and the restatement is the point.** This exception was written as
"embeddings", and E1's translation tranche needs a 9B generative model on the same rented
GPU — which under a literal reading is a second exception being opened, and under the
right reading is the same one.

**The boundary is not "only embedding". It is INFERENCE ONLY, NO DOMAIN LOGIC.** Python
turns tokens into tokens and knows nothing else. Everything that *decides* stays in
Elixir: which chunks to translate, which glossary terms pin which renderings, what the
prompt contains, how output is scored, what is stored and what may carry a URN.

**Could generation be done in Elixir instead?** Not realistically today, and this is an
ecosystem fact rather than a preference. Bumblebee loads BGE-M3 because it is an
XLM-RoBERTa the library supports; its coverage of current Chinese-capable generative
models lags badly, and the machinery that makes generation affordable — quantisation,
continuous batching, paged attention — lives in vLLM and SGLang, not in Nx/EXLA. The
MITRA int8 build is quantised with vLLM's own `llm-compressor`, which is the shape of how
far apart the two ecosystems are on this task.

**The enforcement already exists**, which is why widening the wording is safe.
`Architecture.BoundariesTest` fails the build if `priv/embed` imports outside the tensor
stack or learns a domain word — `urn`, `provenance`, `citation`, `witness`, `canon`,
`bake_id`. A translation sidecar that takes text and returns text passes it untouched.

**The gap in that guard, stated so it is watched.** The test would not catch Chinese *term
mappings* hard-coded in Python — a glossary is not in its vocabulary list. If a glossary
ever appears in the sidecar rather than being passed into it, that is the drift, and it is
the one thing here a test does not stop.

### The original exception: embeddings + Tibetan tokenization

The honest one — and now measured rather than assumed. **Phase 0 spike, resolved:**

- Bumblebee's model registry maps `"XLMRobertaModel" => Bumblebee.Text.Roberta`, and
  BGE-M3's `config.json` declares exactly `architectures: ["XLMRobertaModel"]`,
  `model_type: xlm-roberta`, hidden size 1024, 8194 max positions. **So the backbone
  loads in Bumblebee, and dense embeddings can run in-process via `Nx.Serving`.**
- The multi-vector heads are *not* in the HF model. They ship as two loose PyTorch
  pickles alongside it: `sparse_linear.pt` and `colbert_linear.pt`. Bumblebee will
  not load them.

That second point is better news than it sounds. Those files are **two ordinary linear
layers** (1024→1 for sparse, 1024→1024 for ColBERT). Converting them once, offline,
into a format `Nx` can read reduces multi-vector inference to a matmul on top of the
dense output — which would remove Python from the pipeline **entirely**, at serve time
and bake time both.

So the ladder is:

1. **Dense in-process via Bumblebee** — viable today, use it for query embedding.
2. **Multi-vector via the Python sidecar** — the safe default for Phase 1 bakes.
3. **Multi-vector in Nx by porting two linear layers** — the goal; a one-off weight
   conversion, then no sidecar at all. Attempt in Phase 1 once dense is working.

~~Tibetan segmentation depends on `botok`, which is Python-only with no Rust or Elixir
equivalent, so it keeps the sidecar alive regardless until at least Phase 5.~~
**Withdrawn 2026-08-27, and it was never true in code.** The Tibetan lexical layer windows
syllables on the tsheg the edition prints, which supersedes `botok` for the same reason
jieba was refused for Chinese: a dictionary tokenizer shatters transliterated names, and
this corpus has `པྲ་ཛྙཱ་ཝརྨ` sitting in a colophon. `botok` was never added to the sidecar,
nothing imports it, and only the documentation kept it alive — so as of that date the
sidecar was BGE-M3 inference and nothing else, and the argument for keeping it was Phase
1's multi-vector question alone. (It gained translation inference on 2026-09-02; §3 above
is the current boundary. This paragraph is about the `botok` withdrawal and is true of
its date.)

**Decision:** one small Python service behind a tiny interface:

```
POST /embed     {texts: [...], mode: "dense"|"multi"} -> vectors
```

(`POST /tokenize {text, lang: "bo"}` was part of this decision and is withdrawn with the
`botok` dependency above. The interface is one endpoint.)

Elixir owns all orchestration, batching policy, caching, retries, and storage. Python
does tensor math and Tibetan tokenization, and nothing else. **Do not let this service
accumulate domain logic** — if business rules start appearing in it, they're in the
wrong place.

*Escape hatch, if both Bumblebee routes disappoint:* use a hosted embedding API and
drop the sidecar, at the cost of a network dependency inside the bake.

---

## What this changes in the plan

Nothing architectural. Every invariant in `CLAUDE.md` and every stage in
`ARCHITECTURE.md` is language-independent — the URN scheme, the provenance axes, the
citation guard, and the bake are all design, not implementation.

Both Phase 0 spikes are done: the Bumblebee/BGE-M3 assessment and the Rustler build
setup. What they changed was implementation, not design — except for one thing worth
noting, which is that jieba's failure on Buddhist vocabulary moved lexical retrieval's
fallback from word tokens to character n-grams. That was a measurement overturning an
assumption, and it is the kind of thing this doc exists to record. Don't defer
either.
