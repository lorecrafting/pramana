# Historical one-off gotchas

Recorded lessons, not current task status. [Rule index](../RULES.md).

## One-off gotchas

- **▸ OPEN, NOT SOLVED — an Oban job fails where the identical call succeeds.** Baking
  CBETA GA, 41 of 53 jobs failed deterministically with `{:raw_unreadable, ".../GA/GA11/
  GA11n0010.xml", :enoent}` — a path with the volume padded to **two** digits, which is the
  `Bake.Worker` rebuild branch. Everything that could explain it was checked and excluded:

  - the job's stored args carry the correct three-digit path (`GA/GA011/GA011n0010.xml`);
  - `jsonb_typeof(args->'paths')` is `array`, not `null`, on all 53;
  - `Collections.volume_token("GA", 11)` returns `"GA011"` in the same VM, so **nothing in
    the loaded code can produce `GA11`**;
  - one `Collections` beam is loaded and `:code.which` points at the dev build;
  - the files exist on disk;
  - failure does not correlate with multi-volume works — 36 of 41 failures carry one path;
  - a `--force` recompile and an emptied queue do not change it;
  - and **all 41 succeed when `Worker.perform/1` is called with those same args outside
    Oban.** That is how the collection was finally loaded.

  **▸ SOLVED. A `mix phx.server` left running since the previous day was draining the same
  queue with the code it was started with.** Oban is a *database* queue: any node connected
  to that database competes for its jobs. That server's `Pramana.Cbeta.Collections` had no
  `GA` entry — the collection was acquired the following morning — so its worker padded the
  volume to two digits and asked for a file that has never existed. My VM won 12 of 53 job
  races and the stale one won the rest.

  Every symptom follows: the split moved between runs because it was a race; an `IO.inspect`
  changed it because it changed the timing; the args and the code were correct because they
  were *my* args and *my* code, and neither was what ran.

  **The step that found it, after an hour of inference that did not:** printing at the top of
  `perform`. Fifty-one jobs enqueued, twelve `PERFORM` lines. A worker that is not running
  cannot be debugged by reading it. **Count invocations before reasoning about behaviour.**

  Killing the process fixed it outright — 53 baked, 0 failed.

- **A long-lived `mix phx.server` runs the code it was started with, and holds your job
  queue.** The corollary of the above, worth its own line because the failure does not look
  like a stale server. Check `ps` for old beam processes before debugging anything that
  involves Oban, and `select * from oban_peers` names the node but not its age or its build.

Environment and tooling quirks. Each cost real time; recorded so they cost it only once.

- **`String.to_existing_atom/1` made a tool crash by load order.** The search tool's
  guard admitted `"phrase"`, then the conversion raised because `:phrase` enters the
  atom table only when `Pramana.Retrieval.Lexical` loads — which happens *later* in the
  same function. So `mode: "phrase"` as the **first** search in a fresh VM raised
  ArgumentError while the identical call after any hybrid search succeeded, and every
  test passed because something always ran hybrid first. The atom table is global
  mutable state; map string→atom explicitly instead. (Same family as the
  `function_exported?/3` entry below.)
- **A scripted patch that fails still lets the commit run — EIGHTH occurrence.** The
  Phase 2 gate findings were written by a Python `str.replace`, the anchor did not match,
  the script raised, and `git commit` in the same `&&` chain still succeeded because the
  heredoc was a separate command. The commit message described a doc section that did not
  exist. **Use the Edit tool for docs.** If a script must be used, grep for the new text
  afterwards and treat a missing match as a failed step.

  **Two more on 2026-08-28**, both while writing rules about not doing this. One script
  computed a replacement and never assigned it — `s.replace(old, new)` with no `s =` — and
  printed "ok". Another anchored on `@spec` and inserted a `@doc` between a neighbouring
  `@doc` and its function, which only the compiler caught. Both were found by the grep this
  entry prescribes, which is the entry working; neither was prevented, which is the entry
  not being read. That is why `CLAUDE.md` now indexes these by trigger instead of by topic.
- **The variant-character problem was not where the task assumed.** #32 was written
  expecting the *corpus* to mix orthographic forms. It does not: CBETA writes 說 412,524
  times and 説 zero, 眾生 132,626 times and 众生 zero. The gap is between the **reader's
  keyboard and the corpus** — someone typing simplified or Japanese forms gets *zero*
  results, silently. Same fix, completely different framing, and worth measuring before
  building next time.
- **Unihan's `kSemanticVariant` is not an orthographic-variant field.** It means
  "characters sharing a meaning" and includes genuinely different words, so expanding a
  search across its 2,151 pairs would return passages using another word. Use
  `kSimplifiedVariant` / `kTraditionalVariant` / `kZVariant`. The cost is that 眞/真 is
  filed under the excluded field and is not expanded — documented, not overlooked.
- **A keyword match inside a negation classified 元曉 as Japanese.** Its glossary note
  reads *"Korean (Silla), **not Japanese**"*, and matching the bare word "Japanese"
  found it inside the phrase saying it is not. Two names were misclassified in the real
  import. Negations are now stripped before matching — but the general point is that a
  note saying what something is **not** is evidence about what it is not, and naive
  keyword matching reads it backwards. The source project made the identical mistake
  with the identical name before correcting it.
- **"A decision recorded is not a decision applied."** Borrowed verbatim from
  `scripts_check.py` in `~/dev/huangnianzu-translation`, which found a rule sitting in
  its glossary for *months* asserting a rendering that had already been swept out of
  the prose — invisible because the checker only inspected the translations, never the
  file every batch is told to treat as canonical. The same shape as this project's
  "every declared filter must actually filter", and worth checking for wherever a rule
  is written in one place and enforced in another.
- **`mise trust` is path-keyed.** An early `mise install` silently no-op'd because the
  project config was untrusted, and the global config won. Renaming the project
  directory invalidated the trust again.
- **In an umbrella, `File.cwd!()` is not the umbrella root** — mix runs each child app
  from its own directory. `config :pramana, :project_root` is pinned at compile time
  via `Path.expand("..", __DIR__)` instead.
- **CBETA keeps its apparatus in `<back>`**, not inline, keyed to `<anchor>` positions
  in the body. Assuming inline `<app>` yields empty lemmas.
- **`<lb/>` also appears inside `<back>` lemmas** (which reproduce body text). Treating
  those as line boundaries invented 35 phantom lines with **duplicate anchors** —
  non-unique URNs. `<lb/>` handling is body-only.
- **`<lem>` spans `<lb/>`.** Buffering lemma text and flushing at `</lem>` attributes
  the whole lemma to whichever line closed it.
- **A second URN regex silently disabled the guard.** The quote-pairing pattern's
  character class omitted `:`, so it captured `pramana:cbeta.T` and never matched a
  real URN; every citation fell through to existence-checking and altered quotes
  passed. There is now one `@urn_source`. The test that missed it asserted only `ok?`,
  which is true either way — hence `verified_quotes` in the result.
- **Elixir map typespecs are exact.** An undeclared key in `Corpus.span()` made the
  spec unsatisfiable, and dialyzer narrowed `resolve/1` to its error branch and
  reported every downstream `verdict == :ok` as impossible. Same class of bug in
  `URN.t()`'s `raw` field.
- **Ecto schemas do not define `t/0`**, and Mix/ExUnit are absent from dialyzer's
  default PLT (`plt_add_apps: [:mix, :ex_unit]`).
- **`phx_new` is 1.8.9 while `phoenix` is 1.8.11** — they version separately.
- **Homebrew Postgres uses your OS username**, not `postgres/postgres`.
- **`length(acc)` inside a reduce is quadratic, and only scale reveals it.** The
  segmenter recomputed each ordinal that way. On T0220a (大般若波羅蜜多經, 600 fascicles,
  92,192 segments) that meant ~4.2 billion traversals: 89 s of segmenting against 1.4 s
  of parsing. It presented as a *database* timeout, and no amount of pool tuning would
  have fixed it. Carrying the counter: 89.4 s → 2.3 s. **Measure before tuning.**
- **Oban 2.23 needs migration v14** (v12 errors at boot), and its
  `Oban.Testing.perform_job/2` signature changed — call the worker directly instead.
- **`function_exported?/3` is false for a module that is merely not loaded**, so a test
  using it passes or fails by load order unless you `Code.ensure_loaded!` first.
- **`async: true` plus `Application.put_env(:pramana, :project_root, …)` invalidates the
  corpus tests, on some seeds.** That key is global, and `CBETACorpusTest` /
  `TaishoCorpusTest` read the real `raw/` through it in `setup_all`. An async module that
  repoints it at a temp directory makes those fail with `:enoent` — *"failure on setup_all
  callback, all tests have been invalidated"*, 16 tests, intermittently. `cbeta_test.exs`,
  `lockfile_test.exs` and `work_list_test.exs` are all `async: false` for this reason and
  none of them says so, which is how a new file gets it wrong. **Any test that sets
  `:project_root` must be `async: false`.**
- **A scripted patch that errors leaves docs untouched while the commit still runs.**
  This bit three times. Always verify the file, and never trust an unconditional
  "patched" message.
- **A deep link into CBETA Online, SuttaCentral or SAT cannot be validated by fetching
  it.** All three are single-page apps that resolve content in the browser: a real path
  and complete nonsense both return HTTP 200 with a **byte-identical body** (1,018,537
  bytes for SAT, either way). So `reader.verified` is permanently `false` and stated in
  the payload — a link checker there would be theatre.

  **84000 is the exception, and it is worth knowing which publishers are which.** It is
  server-rendered: `read.84000.co/translation/toh308.html` returns *"Questions Regarding
  Death and Transmigration"* while `toh9999.html` returns a page titled *"Toh 9999"*. So
  its links *could* be checked. `verified: false` stays the floor everywhere anyway,
  because a per-publisher truth claim is one nobody will keep current.

  For the SPAs, formats are measured against each publisher's own **JSON API or rendered
  markup** instead of its HTML status code: 40 of 40 SuttaCentral uids resolve, and every
  CBETA volume token is reproduced from `sources.lock.json` and cross-checked against the
  `id` CBETA puts on the line in the HTML its site serves.
- **Filtering an ANN index post-hoc silently returns too few rows, or none.** Postgres
  plans a filtered vector query as an HNSW index scan *followed by* the join and the
  provenance filter. HNSW yields only `ef_search` candidates (40 by default), so
  narrowing them to a division holding 3.4% of the corpus discards nearly all: a request
  for 10 results in 阿含部 returned **5**, tighter filters returned **none** — with the
  matching text present, embedded and correct. An empty result reads as *"the canon does
  not say this"* when the truth is *"the index never looked there"*, and it strikes
  exactly the provenance filters that are this project's differentiator. Fixed with
  pgvector 0.8's `hnsw.iterative_scan = relaxed_order` on filtered queries only (~3×
  latency, correct answers). **This only appears at scale** — it was invisible across the
  entire 10,138-chunk 阿含部 proof and surfaced within minutes of the corpus reaching
  299,317.
- **Storing the vectors cost more than computing them.** `Transfer.import/2` issues one
  UPDATE per row, each triggering incremental HNSW maintenance: 34 min on an L4 to embed
  299,317 chunks, **88 min** to write them. Task #37.
- **Reproducibility is not fidelity, and `verify` only proved the first.**
  `mix pramana.verify` re-normalizes from `raw/` and byte-compares, so content the
  pipeline drops on *every* run is absent from both sides and the check passes. 10,590
  printed lines, 473 gaiji and 266,547 characters of note text were unreachable in a
  corpus that verified clean. `mix pramana.integrity` counts the bake against the raw
  XML instead; run both at a gate.
- **A `<note>` spanning `<lb/>` was attributed to the line where it CLOSES**, leaving
  intermediate lines with no text and no note — so they looked blank and were dropped.
  Identical in shape to the `<lem>`-spans-`<lb/>` defect fixed earlier. **Any buffered
  element that can cross a line boundary must be split at that boundary**, because the
  line is the citable unit. Check this for every new element that accumulates text.
- **`verify --sample N` is per TEXT, not a corpus total** — `--sample 1000` over 2,471
  texts checks ~1.2M segments, not 1,000.
- **Oban retains finished jobs, so `bake_all`'s counter summed every previous run** and
  reported "works baked: 4941" for a 2,471-work corpus. A wrong number that looks
  plausible. Finished bake jobs are cleared at enqueue now.
- **Coverage `threshold` nests under `summary:`.** `test_coverage: [threshold: n]` is
  silently ignored and Mix keeps applying its own default of 90 — the config appears to
  work because `ignore_modules` at the same level *is* honoured.
- **Excluding a project's only module from coverage crashes `mix test --cover`**
  (`Enum.EmptyError` in `Enum.max/1`). Use `summary: [threshold: 0]` instead.
- **`reference` is a built-in Elixir type and cannot be redefined**, so `@type
  reference :: …` is a compile error, not a warning.
- **`use Anubis.Server.Component` GENERATES `name/0` from its options**, and unlike
  `uri`/`mime_type` it is **not** `defoverridable`. A hand-written `def name` in the
  module body compiles clean and loses to the option default (`nil` when `:uri` is also
  omitted), so the resource lists as a nameless entry. Pass `uri:` and `name:` as
  options. `description/0` is the opposite — optional, never generated, define it.
- **Registering an MCP component does not advertise it.** `capabilities: [:tools]` left
  both resources registered and unreachable: no client calls `resources/list`, so
  nothing errors and nothing is served. Capabilities and `component/1` are two lists
  that must agree.
- **`[env] MIX_ENV = "dev"` in `mise.toml` broke `mix test`.** `mix test` sets
  `MIX_ENV=test` only when it is *not already set*, so pinning it — even to the value
  that is already the default — ran the suite against the dev repo, which has no SQL
  sandbox pool. Removed; do not put `MIX_ENV` there.
- **`mise` shims are not on PATH in non-interactive shells.** `mise current` reported
  the pinned 1.20.3 while `elixir --version` was 1.19.5, so a session's builds and PLT
  drifted off the pinned toolchain without any warning. Prefix with `mise exec --`, and
  check `elixir --version` rather than `mise current`.
- **`mix format` rewrites `field :x, opts` to `field(:x, opts)`.** A scripted patch
  matching the unparenthesised form silently no-ops afterwards. This bit once: the MCP
  input schema kept its old shape while `execute/2` gained new params, so the tool
  accepted the arguments in a direct call and **silently ignored them over MCP**. If a
  patch script prints success unconditionally, it is lying — verify the file.
