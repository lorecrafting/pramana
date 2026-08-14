# Elixir/Phoenix — Fit, and the Three Exceptions

Verdict: **Elixir is a good choice here, not a compromise.** Roughly 90% of this
system is a better fit for BEAM than for Python. Three narrow components are not, and
they're isolated behind interfaces so they stay small.

## Where Elixir is genuinely the right tool

### The bake pipeline (the strongest case)

The bake is: fetch thousands of files, parse each independently, transform, embed,
load — with retries, backpressure, and per-item fault isolation. This is the canonical
BEAM workload.

- **Broadway/GenStage** give real backpressure between stages. The embedding sidecar
  is the slow stage; Broadway throttles upstream parsing automatically instead of
  building an unbounded queue.
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
Phoenix serves that natively. This matters because the Elixir MCP library situation is
unsettled: `hermes_mcp` (v0.14.x, client + server) was forked and rebranded to
`anubis-mcp` after the original maintainer left CloudWalk.

**Decision: use a library if one is healthy at build time, but treat the MCP protocol
as something we can implement directly in a Phoenix controller.** The spec is small,
and owning ~300 lines of JSON-RPC dispatch is far preferable to being blocked on an
unmaintained dependency. Check the maintenance status of both before adopting either.

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

Chinese has no whitespace; segmentation is required for decent lexical recall.
`jieba-rs` is mature and fast, and via Rustler it runs in-process with no sidecar.
Needed at both bake time and query time, so in-process matters.

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

### 3. Embeddings + Tibetan tokenization → Python sidecar (`priv/embed`)

The honest one.

BGE-M3 is an XLM-RoBERTa-large backbone with custom sparse and ColBERT output heads.
Bumblebee has text-embedding servings via `Nx.Serving`, but **BGE-M3's multi-vector
heads are not confirmed supported** — dense-only might work, the multi-vector output
almost certainly needs porting. Multi-vector is precisely why we chose BGE-M3.

Similarly, Tibetan segmentation depends on `botok`, which is Python-only with no Rust
or Elixir equivalent.

**Decision:** one small Python service behind a tiny interface:

```
POST /embed     {texts: [...], mode: "dense"|"multi"} -> vectors
POST /tokenize  {text, lang: "bo"}                    -> tokens
```

Elixir owns all orchestration, batching policy, caching, retries, and storage. Python
does tensor math and Tibetan tokenization, and nothing else. **Do not let this service
accumulate domain logic** — if business rules start appearing in it, they're in the
wrong place.

*Phase 0 spike:* try BGE-M3 dense-only through Bumblebee. If it works, the sidecar
becomes bake-time-only and query embedding runs in-process via `Nx.Serving` — a
meaningful simplification of the serving path. Alternative escape hatch: use a hosted
embedding API and drop the sidecar entirely, at the cost of a network dependency in
the bake.

---

## What this changes in the plan

Nothing architectural. Every invariant in `CLAUDE.md` and every stage in
`ARCHITECTURE.md` is language-independent — the URN scheme, the provenance axes, the
citation guard, and the bake are all design, not implementation.

The one schedule note: **Phase 0 must include the Bumblebee/BGE-M3 spike and the
Rustler build setup**, because both affect how Phases 1 and 6 are written. Don't defer
either.
