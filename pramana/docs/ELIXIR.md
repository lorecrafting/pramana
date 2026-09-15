# Language and runtime boundaries

**Working directory:** `pramana/` for the commands and source-relative paths below.
Shared policy and the active plan remain at repository `docs/`. Existing corpus,
models and virtualenvs are not moved: see [layout migration](../../docs/LAYOUT_MIGRATION.md).

[The repository map](../../docs/REPO_MAP.md) owns the overall layout. The umbrella uses Elixir
for corpus/domain logic and Phoenix for the reader/MCP transport. Foundry is a
separate OTP project with its own lifecycle and dependencies.

## Elixir owns the corpus

Acquisition policy, normalization, citation addressing, provenance, database writes,
retrieval and verification belong in the core domain. Keep web rendering separate
from these rules. Domain code uses Ecto/PostgreSQL; the core also uses Phoenix PubSub
without depending on the Phoenix web application itself.

The [Mix manifests](../mix.exs), [core manifest](../apps/pramana/mix.exs),
[web manifest](../apps/pramana_web/mix.exs) and [toolchain pin](../../mise.toml)
are the authoritative dependency/version records. Old spike results are not current
library-support guarantees.

## The deliberate non-Elixir components

| Component | Current implementation | Boundary |
|---|---|---|
| CJK segmentation | Rustler NIF in `apps/pramana_native/` using jieba-rs | Runs in the BEAM; lexical strategies still need evaluation on Buddhist vocabulary |
| Verbatim text reuse | Standalone Rust executable in `native/quotations/` | Seed-and-extend, not a suffix-array implementation; JSONL input/output; no direct Postgres writes |
| Inference/training helpers | Python scripts in `priv/embed/` | Tensor/model work and artifact handling, including embeddings and translation; no competing corpus database/domain layer |

Dense query serving uses the implemented Elixir embedding path. The old
`POST /embed` sketch describes a proposed interface, not a configured HTTP service.
The withdrawn `botok`/Python tokenization proposal is not a current dependency.
A model's supported heads or a recognized reading scheme do not establish that every
representation or dictionary is implemented and populated here.

Foundry orchestration must remain independent of these corpus companions. A future
shared component requires an explicit boundary decision, not accidental inclusion of
Foundry in the umbrella or inference helpers in its model-free checks.

[Historical language/tooling assessment](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md)
retains the spikes, rejected alternatives and earlier interface sketches.
[Architecture](ARCHITECTURE.md) · [Embedding](EMBEDDING.md) · [Testing](../../docs/TESTING.md)

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="elixirphoenix--fit-and-the-three-exceptions"></a>[Elixir/Phoenix — Fit, and the Three Exceptions](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#elixirphoenix--fit-and-the-three-exceptions) |
| <a id="where-elixir-is-genuinely-the-right-tool"></a>[Where Elixir is genuinely the right tool](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#where-elixir-is-genuinely-the-right-tool) |
| <a id="the-bake-pipeline-the-strongest-case"></a>[The bake pipeline (the strongest case)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#the-bake-pipeline-the-strongest-case) |
| <a id="text-handling"></a>[Text handling](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#text-handling) |
| <a id="postgres"></a>[Postgres](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#postgres) |
| <a id="the-api-and-mcp-server"></a>[The API and MCP server](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#the-api-and-mcp-server) |
| <a id="the-web-reader-phase-8"></a>[The web reader (Phase 8)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#the-web-reader-phase-8) |
| <a id="the-three-exceptions"></a>[The three exceptions](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#the-three-exceptions) |
| <a id="1-cjk-word-segmentation--rustler-nif"></a>[1. CJK word segmentation → Rustler NIF](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#1-cjk-word-segmentation--rustler-nif) |
| <a id="2-suffix-array-text-reuse-detection--standalone-rust-binary"></a>[2. Suffix-array text-reuse detection → standalone Rust binary](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#2-suffix-array-text-reuse-detection--standalone-rust-binary) |
| <a id="3-model-inference--python-sidecar-privembed"></a>[3. Model inference → Python sidecar (`priv/embed`)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#3-model-inference--python-sidecar-privembed) |
| <a id="the-original-exception-embeddings--tibetan-tokenization"></a>[The original exception: embeddings + Tibetan tokenization](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#the-original-exception-embeddings--tibetan-tokenization) |
| <a id="what-this-changes-in-the-plan"></a>[What this changes in the plan](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md#what-this-changes-in-the-plan) |
