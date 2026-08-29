# Rules that generalize

**Read this before writing a new source pipeline.** Every rule here was learned from a
real defect in this repository, and most of them apply directly to the next normalizer.

This file was the last third of `docs/STATUS.md` — the section `CLAUDE.md` sends every new
session to, buried at line 3,272 of a 3,896-line file that was mostly a chronological log.
It is a **reference**, consulted by number: code and commits cite "rule 41" and mean an
entry here.

`docs/HISTORY.md` has the incident each rule came from. `docs/PROXIES.md` is the one
case study long enough to need its own file.

---

## Rules that generalize

**Read this section before writing a new source pipeline.** Everything here was learned
from a specific bug, but each one states a rule that will apply again — most of them to
Phase 2's SAT normalizer, which is the next thing anyone writes.

1. **Any buffered element that can span a line boundary must be split at that
   boundary.** The line is the citable unit, not the element. This bug has now been
   fixed *twice* in the same file — `<lem>` spanning `<lb/>`, then `<note>` spanning
   `<lb/>` — and the second cost 10,590 uncitable printed lines. When adding an element
   that accumulates text, the question is not "does it usually fit on one line" but
   "what happens when it does not".
2. **Reproducibility is not fidelity.** A check that re-runs the pipeline and compares
   proves determinism only: content dropped on every run is absent from both sides and
   the check passes. Fidelity has to be measured against the *source*. Hence
   `mix pramana.integrity` alongside `mix pramana.verify`.
3. **A line is only droppable if nothing was printed on it.** Text, an interlinear note,
   a variant reading and a rare character are all printed content, and each needs an
   address.
4. **Never silently ignore an unknown option** — raise. A filter that is accepted and
   dropped produces results that look filtered and are not.
5. **Every declared filter must have a test proving it changes the result set.** Both
   filter bugs so far passed their existing tests.
6. **Filtering an ANN index post-hoc truncates silently.** Any query combining a vector
   ordering with a selective `WHERE` needs pgvector's iterative scan, or it returns too
   few rows with no error. Expect this to recur every time the corpus grows.
7. **Defects that only appear at scale will not appear in the proof run.** The quadratic
   ordinal, the ANN truncation, and the note-splitting loss were all invisible on one
   text or one division. Re-run the integrity and filter checks after every corpus
   growth, not just after code changes.
8. **A scripted patch that reports success may have done nothing.** This has now bitten
   five times. Always grep for the new text afterwards; never trust an unconditional
   "patched" message. Prefer a real edit over a Python string replace.
9. **`on_conflict: :nothing` on a reference row makes it write-once.** Correcting
   bilara-data's licence from CC0 to Public Domain Mark in `Pramana.Sources` and
   re-ingesting all 8,442 works left the `sources` row still saying `cc0`, because the
   row already existed. `redistributable_only` filters by joining that row, so the
   registry was right and the thing making decisions was wrong. Any table that mirrors a
   declaration in code must replace on conflict, and a test must assert the row equals
   the registry after a load.
10. **A source's own LICENSE file is not the licence.** bilara-data's LICENSE.md says
    CC0 throughout; its `_publication.json` records Public Domain Mark for the Pāli root
    text and CC BY-SA 3.0 for the Patna Dhammapada. Licence belongs to the publication,
    never to the repository — check per publication before ingesting.
11. **A check constraint on an enumerated column is a contract with the registry.**
    Adding `public-domain` to `Pramana.Sources` without adding it to
    `license_class_known` made every insert fail. That is the constraint working: a
    licence class nothing enumerates is one no query can reason about. Extend the
    constraint in the same change as the registry.
12. **A test that hardcodes a value the registry owns will fight the registry.** Three
    licence-filter tests asserted `"cc0"` for a source and broke when the licence was
    corrected — inviting a "fix" that restores the wrong licence. Derive such values
    from the source of truth (`Sources.fetch!/1`) so the test checks the *behaviour*.
13. **When a column mirrors a claim someone else made, carry how confident you are
    separately from the claim.** bilara-data's publication ids do not always map onto
    the works they cover — `pli-tv-vi` is the whole Vinaya, not a prefix of
    `pli-tv-bu-vb-pj1` — so 66,199 renderings had no directly matching publication.
    `license_class` (what we believe) and `redistributable` (what we will act on) being
    two columns is what let those be held and searched under an inferred CC0 while
    staying unpublishable until confirmed. One column would have forced a choice between
    losing them and overclaiming.
14. **`insert_all` binds one parameter per column per row, so batch size is a function
    of row width.** A fixed 5,000 worked at 13 columns and exceeded Postgres's 65,535
    limit at 18. Derive the batch from `map_size(row)`; a constant reintroduces the
    failure the next time a column is added.
15. **A grouped query is not an aggregate.** `Repo.one` over `group_by … having count > 1`
    works while every group is unique and raises the moment a second row appears — which
    is exactly when the number becomes interesting. Count over a subquery.
16. **A convention can be the opposite of what it looks like — check before projecting
    it.** The glossary populates `pinyin` precisely when the target-language reading
    could *not* be established, and leaves it empty when it could (the reading then being
    in `canonical_english`). Reading it the obvious way recorded 元曉 as *Yuánxiǎo* under
    McCune-Reischauer, marked verified: the exact error the glossary exists to prevent,
    laundered into structured data. When importing from a curated source, verify what its
    empty fields mean.
17. **An optional dependency that silently halves a system is worse than a required
    one.** `Hybrid.search/2` ran semantic retrieval only when the caller passed
    `:serving`, so any caller that forgot got lexical-only results with the model loaded
    and idle in the same VM — no error, just worse answers. The MCP tool remembered; the
    eval harness did not, and scored 0/40 on retrieval that works. If a component can be
    absent, the presence of the thing itself should decide, not a caller's memory.
18. **A benchmark's first job is to be wrong in ways you can see.** Half the Pāli gold
    cases quoted text occurring in up to 15 places, and scoring against one arbitrary
    copy measured luck rather than retrieval — it would have published 27.5% where 37.5%
    was true. When ground truth might not be unique, expect the whole equivalence class.
19. **A session-level `SET` does not survive a connection pool.** `Repo.query!("SET
    maintenance_work_mem …")` followed by `Repo.query!("CREATE INDEX …")` checks out two
    connections: the setting applies to one that then goes idle, and the build runs at
    the default. Nothing errors — the index is built correctly, just an order of
    magnitude slower, which reads as "HNSW is slow" rather than as a bug. Measured on
    342,535 vectors: **~62k tuples/min inside one transaction, ~1.6k across two
    connections — 38×.** Any setting a statement depends on must share its transaction.
20. **A cascading delete can destroy work that cost money to produce.** `chunk_vectors`
    cascades from `chunks`, and re-chunking deletes a text's chunks before rebuilding
    them — so `mix pramana.chunk` would have thrown away 299,317 GPU-computed embeddings
    and reported success. The builder now refuses to rebuild a text whose chunks carry
    embedded vectors unless forced, and reports what it left alone. Before adding
    `ON DELETE CASCADE`, ask what the child rows cost to recreate.
21. **Positional query bindings break silently when a join is added in front of them.**
    The provenance filters read `[_c, _t, w]` — correct while the query was
    chunk-text-work, and pointing at the wrong table the moment a vector join went first.
    A filter reading the wrong column returns a plausible result set and raises nothing.
    Named bindings (`[work: w]`) cannot drift; use them anywhere a query is composed.
22. **A coverage figure's denominator is a claim about the corpus, not about the table
    you happen to be counting.** Moving vectors into their own table quietly changed
    "how much of the corpus is searchable" into "how many vector rows exist", so a
    chunked-but-unembedded corpus reported `total: 0` — "nothing to search" rather than
    "nothing embedded yet" — and a corpus with translation vectors for 2% of its chunks
    would have reported 100%. The denominator stays the corpus.
23. **A file is a packaging unit; the work is a citation unit.** `an1.1-10_root-pli-ms.json`
    holds ten suttas. Taking the work id from the filename collapsed ten distinct `1.0`
    segments onto one address — caught only by a unique constraint. Derive the work id
    from what the source *cites*, and where works do not map one-to-one onto files,
    record the file on the text (`meta["source_file"]`): without it `mix pramana.verify`
    cannot find the bytes to re-derive from, and a check that cannot run is not a check.
24. **A shared helper only helps if using it is easier than not.** The Postgres
    parameter limit was hit a fourth time after `Pramana.Batch` existed and after the
    lesson was written down twice, because `Batch.chunk/1` still left every call site
    free to forget — and an unbatched write path looks fine until the data grows.
    `Batch.insert_all/4` takes the same arguments as `Repo.insert_all/3` and cannot be
    called without batching. Wrap the dangerous call; do not offer a helper beside it.
25. **Proving absence is the expensive case for an index.** Checking 13,000 dictionary
    forms against the corpus with `LIKE '%form%'` measured 1.3 seconds *each* — the
    pg_bigm index is fast when a form is common and slow when it is missing, which is
    most of them. One streaming pass answered the same question in 2m11s. Index-per-item
    beats a scan only when the items are few.
26. **A `with` whose `else` discards everything turns a shape bug into an empty
    result.** A CC-CEDICT line matcher destructured four elements from a five-element
    `Regex.run` result; the catch-all clause swallowed every line and the build reported
    "0 entries" rather than raising. Where a fall-through means "skip this row", make the
    skip conditions explicit enough that a malformed *pattern* cannot masquerade as
    malformed *data*.
27. **Character data outside the text element is the library talking, not the book.** The
    Derge normalizer buffered every character event, so each volume's 416-byte
    `<publicationStmt>` distributor note became the first citable line of whatever work
    was running into that volume — 102 of 103 volumes, addressed by a URN that resolves.
    A normalizer's default should be to ignore text, and to buffer only where it has
    established it is inside the body.
28. **An idempotent loader makes assembly the caller's problem.** `Loader.load/2`
    replaces a text's segments rather than appending, which is what makes a re-run safe —
    and what makes loading a multi-file work once per file keep only the last file. The
    failure is silent in both directions: no error, and a text whose length looks
    plausible. Whenever the source's packaging unit is smaller than the citation unit,
    assemble first and load once.
29. **The closing check counts bytes, not units the parser defined.** Line counts,
    work counts and character counts are all downstream of how the parser decided to
    split things, so they agree with a wrong split. Non-whitespace bytes of character
    data inside `<text>`, counted by something that knows nothing else, closed the Derge
    edition to 69 bytes out of 290,863,399 — and named the 69 as the one thing dropped on
    purpose. If a fidelity check cannot state the difference exactly and explain it, it is
    not closed.
30. **A chunk size is a claim about a tokenizer, and an untested one fails silently.**
    The embedder truncates at 320 tokens, so a chunk that tokenizes longer is embedded
    from its opening while its text stays whole — no error, no count out of place, just a
    vector describing a prefix. 76.2% of Pāli chunks were in that state for two phases.
    Measure the size against the actual tokenizer, per script, and pin the numbers in a
    test.
31. **A benchmark that cannot see a tradition reports it as absent, not as bad.** The
    eval deriver's translation-anchor join was equality on a segment URN, so Tibetan —
    whose renderings are anchored to folio RANGES — produced zero cases, and the
    scorecard simply had no Tibetan row. A missing row reads as "not built yet"; a bad
    row reads as "built and weak". Before trusting a per-tradition number, check that
    the instrument can produce a case for that tradition at all.
32. **Refute the obvious explanation before acting on it.** Adding a third English layer
    coincided with a Pāli topical drop, and #44 had predicted exactly that mechanism —
    tradition competition. Measuring it took one script and refuted it: Tibetan held 1 of
    160 result slots. The second hypothesis, that the smaller chunk cut the term out of
    the returned window, died the same way — scoring over the chunk ± 3 segments gave the
    same 10/16. Two plausible stories, both wrong, and the cost of believing either would
    have been a redesign.
33. **A partial match between two editions is more dangerous than none.** 84000 numbers
    Toh 11's folios from the work's own start in its second volume, and 428 of those 610
    numbers exist in that volume of that work — so they anchor, resolve, byte-verify, and
    attach English to a passage it does not translate. A total mismatch is visible; a
    70% match looks like data quality. Where two numbering systems are being joined,
    accept or refuse a whole group, and pick the threshold from the measured distribution
    rather than from taste.
34. **`preload` through a join ships every column of the joined row, once per row.**
    Retrieval's `preload([_s, t], text: {t, [...]})` fetched `texts.body` — the entire
    normalized work, up to 13.3M characters — once per matched segment, to read a title
    and a licence class. Removing it made lexical search **32x faster** (1403 ms → 44 ms
    over five formulae, ABBA-verified). The idiomatic one-line form is the expensive one,
    it costs more the wider the joined table's widest column is, and the call site shows
    nothing. Use a separate preload query with `select: struct(t, [...])` — `struct/2`,
    not a `%Text{}` literal, which loses the binding and makes Ecto refuse the query — and
    test that the emitted SQL still names every schema field, because a column added later
    and not listed reads as `nil` with no error anywhere.
35. **Making a long run fault-tolerant is half the job; the other half is making sure the
    shrunken denominator cannot be read as a result.** One timed-out query took a 4h25m
    eval run with it, so `score_case/2` now rescues. But a rescued case is not a miss (that
    publishes a regression that did not happen) and not stale (that blames the gold set for
    our outage) — it is its own outcome, out of the denominator, printed loudly, carried in
    the JSON, and `--gate` refuses to run at all when any case errored, because missing
    hits would either trip the ratchet or *install* an under-measured run as the baseline.
    Whenever a loop learns to survive a failure, ask what the summary now claims.
36. **A tokenization rule is a rule about ONE script, and the `else` branch is where the
    next script goes to die.** This defect has now appeared three times in one module:
    jieba shattering Buddhist transliterations in Chinese, grapheme windows producing
    `་པ་` in 89.6% of Tibetan segments, and grapheme trigrams turning a 145-character
    English sentence into 135 predicates of `%the%` and `%er %`. Each time the unit was
    right for the script it was designed for and meaningless for the one that fell through
    to it. When a function branches on script, every branch must name the script it serves;
    `if tibetan?(q), do: syllables, else: graphemes` silently claimed Latin, Devanāgarī and
    everything else for a CJK tool.
37. **A speedup measured on one workload does not fix a timeout observed on another, even
    at the same line number.** `lexical.ex` was made 32x faster on Chinese phrase queries
    and the depth-120 timeout was declared fixed on that basis. It was not: the timeout was
    English n-gram fallbacks, which share the line and nothing else. The ABBA re-run that
    caught it cost 45 minutes; the claim had already been committed and written into
    STATUS. **Before crediting a fix with removing a failure, reproduce the failure.**
38. **`LIMIT` without `ORDER BY` turns a bad plan into an intermittent one.** A sequential
    scan under a limit stops as soon as it fills, so its runtime depends on where matches
    happen to fall in heap order — the same query is fast, slow, or fatal depending on the
    limit and the data layout. That is why this bug presented as "one arm in two dies" for
    three sessions rather than as a query that is simply slow, and why it was attributed to
    cache weather. An intermittent timeout under a limit is a plan problem until proven
    otherwise.
39. **When a planner abandons an index, the threshold is selectivity, not a count.** OR'd
    `LIKE` predicates dropped off `pg_bigm` at 25 on one query and at 10 on another; what
    differed was how common the terms were. A cap chosen from one query's cliff would have
    been wrong for the next. Cap by *rarity* (length is a free proxy) and verify with
    `EXPLAIN` across the whole gold set — 252 queries took seconds and turned a guess into
    a measurement.
40. **Profile the whole operation before optimising the part an error message names.** A
    `DBConnection` timeout stack trace pointed at `lexical.ex`, and a full day went into
    the lexical arm — a real 32x fix, a real n-gram defect, all of it sound. The lexical
    arm was **14 ms of a 41,169 ms search**. The stack trace named whichever arm held the
    connection when the pool gave up, not the one consuming the time; the semantic arm sat
    unprofiled underneath the entire investigation. One `:timer.tc` around each arm would
    have reordered the whole day, and it cost two minutes to run.
41. **A rule written after a fix does not sweep for the other instances.** Rule 34 was
    written the morning `texts.body` was removed from `Retrieval.Lexical`. By that
    afternoon the identical `preload([s, t], text: {t, ...})` was still live in three other
    call sites and a fourth as a `select`, one of them inside an N+1 running 120 times per
    search — together 38 of a search's 41 seconds. **When a defect is found, grep for its
    shape before writing the rule**, and prefer a shared function to a rule: `Pramana.Batch`
    exists because rule 14 was re-broken the same way, and `Text.preload_without_body/0`
    now exists for this one.
42. **A hand-maintained column list is a defect with a test, not a fix.** The first version
    of that preload listed every `texts` column explicitly, with a comment admitting the
    list was a drift surface and a test to catch drift. `__schema__(:fields) -- [:body]`
    needs neither: subtraction cannot go stale. When a test exists only to catch a list
    going out of date, ask whether the list should be derived instead.

43. **A source acquired in parts must MERGE into its lockfile entry, never replace it.**
    `put_source/1` is right for a source fetched in one pass and silently destructive for
    one fetched a collection at a time: acquiring CBETA's X dropped the Taishō's 2,471
    file records, and a corpus of 3,701 texts was left with a lockfile that could
    reproduce 1,230. Nothing failed — `raw/` was intact, `verify` re-derives from the file
    a text names rather than from the lockfile, and acquisition reported success. **When a
    write replaces a record that more than one run contributes to, the second run is a
    silent delete.**
44. **Every coverage ratio needs a denominator that can see rows that do not exist.**
    `embedding_coverage` counted chunks, and 1,230 texts with no chunks vanished from both
    halves of the fraction and reported 100.0%. A ratio computed over the artefacts of a
    stage is blind to everything that never reached that stage — which is exactly what a
    coverage number is supposed to expose. Count the corpus, not the pipeline's output.
45. **Take one census from the SOURCE, before parsing, for every ingest.** Files on disk
    against works loaded — 1,236 against 1,230 — is what found six works keeping half of
    themselves, after `verify` had passed over all 3,701 CBETA texts. Every other check in
    this project starts from a row that exists; none of them can see a row that should.
    This is rule 2 (*reproducibility is not fidelity*) in its cheapest possible form, and
    it is now check 4 in `mix pramana.integrity`.
46. **A number a check derives from raw markup must be derived by the SAME rule the
    pipeline uses.** `integrity` counted every `<lb/>` in the body; the normalizer counts
    only the ones belonging to this edition's lineation. After the two-lineation fix the
    two rules disagreed by half, and the check reported 1,228 correct X texts as having
    lost half their lines. The normalizer had the reconciling number all along and threw
    it away — **when a pipeline stage deliberately discards input, it must EXPORT the
    count**, or every downstream fidelity check has to re-implement the rule and will
    eventually re-implement it wrong. And a check that cries wolf is worse than a missing
    one: this failure sat unnoticed because the ingest ran `verify` and not `integrity`.
47. **A lesson learned from one measurement does not transfer to a different one without
    being re-measured.** "Measure discrimination, not dispersion" was correct and hard-won
    for judging whether a fine-tuned embedder had improved. Applied to judging whether a
    QUERY has an answer, the same statistic separates nothing — 6 of 8 unanswerable
    queries sit inside the answerable range. The registered prediction was wrong and the
    probe took twenty minutes; reasoning from the earlier finding would have shipped a
    signal that does not work. **Register the prediction, then measure anyway.**
48. **"Blank" must be defined once, as the ABSENCE of every kind of content, never as a
    list of the kinds someone remembered.** Three lines-dropped defects here, three
    versions of the same list: text-only (v2 dropped note-only lines), then text+notes
    (v3), then text+notes+apparatus — which dropped a line whose only content was a rare
    character. Each list was written by someone who knew about the kinds of content that
    existed *at the time*. `Pramana.Normalize.IR.Line` knows all of them; the predicate
    belongs there, derived, not restated at each call site (see rule 42).
49. **Measure the instrument's variance before attributing a delta to your change.** The
    noise floor was published as one case, measured by running the identical configuration
    twice against the identical index. Rebuilding the HNSW index over **completely
    unchanged data** then moved the gate by **six cases, four of them `retrieval/tibetan`**
    — four to six times larger, and invisible until someone ran the null experiment. Every
    import, re-embed and chunk-size change rebuilds the index. A metric whose noise you
    have not measured cannot support the claim you want to make with it, and the null
    experiment costs one run.
50. **Carry what you were given; never parse it apart and rebuild it.** `A/A091/A091n1057.xml`
    was parsed into the integer 91 and formatted back with two-digit padding, producing
    `A/A91/...`, which does not exist — because the padding width belongs to the edition
    (T, X, J, K, S, M use two; A, P, L, U use three) and the string already knew it. Two
    works failed to bake, and `verify` and `integrity` would have failed on them
    identically, because all three rebuilt the same path from the same parts. The lockfile
    records the path; the bake now carries it. This is the same shape as inferring a
    lockfile's raw root from a source id, and as inferring `addressing` from a source id
    before that: **an identifier reconstructed from its components is a guess wearing the
    costume of a fact.**
51. **A collection's NAME is not its contents, and neither is its size.** Seven CBETA
    collections were acquired on the argument that they are other witnesses to works
    already held, which would have turned 572,701 recorded variant readings into passages
    a reader could open. Of 57 works, **2** share a title with anything in T, X or J:
    CBETA publishes what is *distinctive to* each edition — the Koryŏ's own collation
    record, Song imperial compositions, phonetic glossaries — not a parallel text of the
    Taishō's works. A collection called "the Qianlong Canon" holding 21 works is not the
    Qianlong Canon. The refusal to expand a two-letter code into a canon name, three hours
    earlier and in the same module, was the identical rule one level down; **check what a
    source contains before designing around what it is called.**
52. **A volume is not the unit of loading, and this is the second source it has bitten.**
    Recorded for Derge, where 75 of 1,195 works span volumes; found again in CBETA X,
    where six do. The Taishō hid it for two phases because CBETA gives its split works
    distinct ids (`T0220a`, `T0220b`) while X reuses the number. Before baking a new
    source, **group the file list by work id and look at the groups of size > 1** — it is
    one line, and the failure it prevents is a text that resolves, verifies, and is half
    missing.

53. **A format that is "obviously" uniform across an edition is a table, and the table is
    the publisher's, not yours.** `Reader.linehead/1` padded CBETA volume numbers to two
    digits, because for two phases every volume held was two digits. Four of the ten
    collections now held use three — `A1057` is in `A091` — so 725,650 segments, 7.1% of
    the CBETA corpus, emitted a citation string CBETA's own reader cannot find. It could
    not raise: a wrong linehead is a plausible string that fails silently in someone
    else's search box, which is the failure this project treats as worse than an error.
    The same constant had already bitten `WorkList` as an `:enoent` (rule 50) and been
    fixed *there only* — rule 41 again, and now on its own recorded rule.

    **Check the artefact a reader sees, not the metadata field describing it.** The widths
    here were taken from the `id` attribute CBETA's website puts on the line. CBETA's
    catalogue API disagrees with CBETA's website: `works?work=M1540` reports volume
    `M059`, the rendered line is `M59n1540_p0789b01`, and a table built from the catalogue
    would have been silently wrong about a whole collection. This is the same shape as a
    text's own byline beating the 部 volume table for provenance — prefer the edition's
    own output over a description of it.

    **And a citation format needs a coordinate, so never feed it a range.** The other half
    of the same bug was `Corpus.provenance/1` supplying `text.volume`, which for a
    volume-spanning work is `"130-133"`. The 18 such works cited as
    `130-133n1557_p0003a01`. `IR.concat/1` had stamped every line with its own printed
    volume since the X assembly fix; the answer was recorded and never asked for. **When a
    field can be a range, the code that addresses one line must take the line's value, not
    the work's.**

54. **Normalise by the thing doing the measuring, not by the thing being measured.** The
    first gate for commentary alignment was *what fraction of the root does this commentary
    quote*, which puts the denominator on the other object and therefore ranks by that
    object's size. T1742 quotes T0278 at a density of 69.2 with 82.4% forward order, and
    covers **0.3%** of it — below what unrelated pairs score. Any root-coverage threshold
    strict enough to exclude the null band discards it. The working measure is spans per
    10,000 characters of the **commentary**, which does not shrink as its target grows.
    Before trusting a ratio, check it against the largest and smallest instance you have.

    And **a threshold calibrated against a thin tail is calibrated against nothing.** The
    floor was set to 25 against 40 null pairs — commentaries paired with roots they do not
    explain — whose p90 was 10.8, which looked like enormous margin. Tripling the null set
    to 120 moved the observed *maximum* from under 11 to **28.4**, and 25 turned out to
    admit three of them. The floor is now 30, the lowest value rejecting all 120.

    Two habits follow. **Quote the null maximum, never its p90**, because a gate's job is
    to reject the worst case and a percentile is chosen to ignore it. And when the margin
    still looks thin, **enlarge the null set rather than reason about the margin** — it
    cost one more run and it was the run that found the error.

55. **Whitespace you introduced is yours, never the edition's — do not match on it.**
    `texts.body` joins printed lines with newlines. An 8-character window taken raw over
    that can be two newlines and six characters, and a quotation running across a printed
    line break — which most do, the break being typographic — fragments into one match per
    line. Lemmas were stored beginning `\n\n`. Match over the text with whitespace removed
    and map the offsets back. Classical Chinese prints no whitespace at all, so **any**
    whitespace in a CJK body is an artefact of our own storage; this is the same root fact
    as "never use whitespace tokenization", arriving at a different layer.

56. **When a record says which files it governs, match on that — not on an identifier that
    usually correlates.** SuttaCentral publications were resolved by `text_uid` prefix,
    which works because `mn` covers `mn1` and fails because `pli-tv-vi` — the whole Vinaya
    Piṭaka — is not a prefix of `pli-tv-bu-vb-pj1`. **66,199 rows of CC0 public-domain text
    sat marked not-redistributable for two phases** as a result. The same records carry
    `source_url`, pointing at the directory the publication publishes; matching on that
    resolves 4,784 of 4,996 files exactly. Before inferring, check whether the data already
    states the thing you are about to infer.

    **And a conservative default hides its own errors.** Storing `redistributable: false`
    when unsure is right, and it is indistinguishable from a correct answer — no test
    fails, no query errors, the text is simply absent from anything public. The only way it
    surfaces is by counting what the caution costs, which is what `mix pramana.public.check`
    now exists to do. **Any policy of "when unsure, withhold" needs a report of what is
    being withheld**, or it silently becomes the answer.

57. **A safety check is not a completeness check, and the artefact needs both.** The
    public bake verified that nothing forbidden was present and reported **"✓ safe to
    expose"** over a corpus holding 1,195 Tibetan texts instead of 4,575. The Tengyur stage
    had re-run the Kangyur, because it was passed `--source derge-tengyur` to a task whose
    switch is `--collection`, and **`OptionParser.parse/2` — without the bang — drops an
    unknown switch silently**. Every stage returned `:ok`.

    That is the coverage doctrine failing inside the artefact built to embody it. A corpus
    missing a canon answers *"the tradition is silent"* to questions it was simply never
    given the text for, and it does so with total confidence. Every ingest now declares a
    row floor and the bake counts what landed. **Use `OptionParser.parse!/2` in a task, and
    when a stage's success is reported by the stage itself, verify it by counting from the
    other side.**

58. **A cache keyed on existence is a cache that poisons itself.** `Acquire.Archive`
    trusted a downloaded tarball if it existed and had `size > 0`. The CBETA archive is
    1.2 GB; an interrupted download leaves exactly that, so every later run logged
    *"archive already downloaded"*, skipped the fetch and died in `:erl_tar` with
    `{:extract_failed, :eof}` — an error that points at the extraction code and says
    nothing about the cache, which stays poisoned until someone deletes it by hand.

    **Verify with the operation that will consume it.** The check is now
    `:erl_tar.table/2`, literally the call that used to fail two steps later. Nothing
    weaker worked: the first fix streamed the gzip with `File.stream!([:compressed])`,
    which reads a truncated archive to its short end **without raising** and reported half
    a file as fine — the same bug wearing a different hat. And a failed download now
    removes its partial file rather than leaving one for the next run to trust.

---

59. **A "reasonable" constraint on a coordinate is an assumption about an edition, and the
    next edition will refute it.** `volume_token/2` guarded `volume > 0`, because a volume
    being at least 1 is the sort of thing nobody checks. Three CBETA collections number
    their first volume **zero** — `I00`, `GA000`, `GB000` — so every linehead in them came
    back `nil`. This is rule 53 wearing a different hat: there it was the *width* of the
    volume number asserted rather than read, here it is the *range*. Both were caught by the
    same test, which reproduces every token in `sources.lock.json` rather than a fixture.

    A test that encodes the assumption is part of the defect: `assert volume_token("T", 0)
    == nil` had to be deleted, not adjusted. **When a guard rejects a value, ask which
    edition told you it was impossible.**

60. **A capability the MCP surface cannot reach has not shipped.** This project's thesis is
    that *any LLM* can do citation-grounded scholarship over the corpus, and the MCP tools
    are how. A domain module with tests, a mix task and a moduledoc is not a feature until a
    model can call it. **Three times in one week**: commentary alignment and translation
    search were reachable only from the reader; `get_commentaries` and `get_parallels` were
    registered and absent from `docs/MCP.md`, which for a surface designed to be discovered
    is the same as unregistered; authority linking and translator comparison landed in the
    database and nowhere else.

    Finishing a capability means four things, and the last two are the ones that get
    skipped: the domain function, its tests, **a tool in `PramanaWeb.MCP.Server`**, and **a
    row in `docs/MCP.md`'s table**. If the reader should show it too, that is a fifth. Ask
    "can a model reach this?" before calling anything done.

---

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
