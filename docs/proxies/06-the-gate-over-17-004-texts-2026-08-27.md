# Why every proxy lied — chapter 6

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### The gate over 17,004 texts — 2026-08-27

`mix pramana.gate --from verify`, after J:

    verify --all     17,004 texts, 11,519,879 segments, 26m05s
                     body re-normalized from raw/ and byte-identical for every text

    integrity        13m39s
      source anchors            15,789,259
      IR lines                  11,621,580
      another edition's lines    4,167,679   (skipped, not lost)
      lines with printed content 11,519,879
      segments in the bake       11,519,879   (every one addressable)
      gaiji in raw body            231,631
      gaiji reachable in segments  222,763   (repeats collapsed per line)
      stranded on dropped lines          0

      cbeta: 3,994 file(s) -> 3,986 work(s) -> 3,986 loaded
        8 works span volumes: JB271, JB277, X0240, X0367, X0714, X0822, X1568, X1571

**That census line is the one worth reading.** This morning it read 1,236 files against
1,230 works and six works had each silently lost a volume. It now reconciles across two
collections and eight spanning works, and the two J works it names — JB271 and JB277 —
were caught *before* the bake by a check that did not exist twelve hours ago.

`verify --all` at this scale is 26 minutes, which is the expensive half of the gate and
the half worth paying for: the sampled run checks 1,000 segments per text, and only the
full one can prove the sentence it prints.

### J changed nothing, and the prediction that it would was wrong — 2026-08-27

Registered before the run: *"`retrieval/chinese` drops again, because J is almost entirely
commentarial and definitional formulae now match still more commentaries quoting them."*

    overall            93.1%   ->  93.1%
    retrieval/chinese  96.1%   ->  96.1%   (223/232)
    every other row    unchanged

**Identical. The gate passed.** So the X displacement was not the general law it looked
like — *more commentary makes Chinese retrieval worse* is not what happened.

What actually happened with X is narrower and more interesting. X is **1,230 works of
exegesis on the same sūtras**, quoting the same 云何為X formulae the definitional gold
cases search for, so it competed directly for those slots. J is 285 works of Ming and Qing
Chan material — a different genre asking different questions — and it barely touches those
formulae. Volume was never the mechanism; **genre overlap with the gold set was.**

That matters for what comes next. It means the answer to X's displacement is not "filter
every definitional query by role" applied globally, and it means the next collection's
effect on retrieval is predictable from what KIND of text it is rather than from how much
of it there is. B (大藏經補編) and ZW (藏外佛教文獻) are next by size and are both
miscellanies; N (漢譯南傳大藏經) is a Chinese rendering of the Pāli canon and would compete
with the Āgama material directly.

Caveat stated: J was baked and **not chunked or embedded** for this run, so it participated
in the lexical arm only. The post-embedding run measures the semantic half separately,
which is why the two were kept apart.

### HNSW is not stable under insertion, and Tibetan is where that shows — 2026-08-27

J embedded, index rebuilt over 966,931 vectors, gate re-run:

    overall             93.1% -> 93.4%   +3 cases
    retrieval/chinese   96.1% -> 96.6%   +1
    retrieval/tibetan   46.9% -> 50.0%   +2      <- not attributable to J

**The Tibetan gain is not being claimed.** 285 Chinese works cannot answer a Tibetan gold
question — those cases expect Tibetan URNs — so J did not supply the two new hits. Two
mechanisms can, and neither is J being useful:

1. **An HNSW rebuild is not deterministic.** The graph is built with randomisation, so
   the same vectors reindexed give slightly different approximate neighbourhoods.
2. **Adding vectors reorders results for queries that have nothing to do with them.**
   59,501 new Chinese vectors change the graph globally, and approximate search is
   approximate for everyone in it.

Tibetan is the tradition most exposed to both, and the reason is already measured:
**BGE-M3 packs Tibetan at 0.9727 mean pairwise cosine** against 0.84 for Pāli. Its
candidates are near-ties by construction, so a small perturbation of the graph reorders
them where Chinese and Pāli hold their positions.

**This invalidates the noise floor as previously stated.** The 1-case figure came from
running the identical configuration twice **against the same index**. It measures query
nondeterminism and nothing else. Any change that involves an index rebuild — every import,
every re-embed, every chunk-size experiment — carries a second and larger source of
variance that has never been measured.

**The experiment that would settle it:** rebuild the index over unchanged data and re-run
the gate. About 55 minutes, unattended, and it is worth more than the configuration sweep,
because until it is done every future claim of the form *"this change improved Tibetan by
two cases"* is unfalsifiable.

The baseline is updated to 93.4%, which is the true state of this bake. The Tibetan row is
recorded with this caveat attached rather than as a gain.

### The alternative editions are 23% volume-spanning, and one runs to four volumes

74 files acquired in a single download — the whole CBETA tarball is ~2 GB and fetching
seven collections separately would have downloaded it seven times for less material than
one Taishō volume. Read from disk before baking:

    K  10 files   9 works   高麗大藏經（新文豐版）    唐 玄奘譯
    A  12 files   9 works   趙城金藏               唐 慧菀述
    P  20 files  13 works   永樂北藏               宋 宗永集 元 清茂續集
    L  26 files  21 works   乾隆大藏經（新文豐版）    隋 智顗說、灌頂記 唐 湛然釋
    U   3 files   2 works   洪武南藏               唐 義忠述
    S   2 files   2 works   宋藏遺珍（新文豐版）      唐 詮明集
    M   1 file    1 work    卍正藏經（新文豐版）      宋 蘊聞錄

**13 of 57 works span volumes — 23%, against 0.5% in X and 0.7% in J.** That is not an
anomaly, it is what these collections are: CBETA has digitised a *selection* from each
edition, and what gets selected is the large multi-fascicle work. Every one of them would
have lost a volume under the pre-2026-08-27 loader.

**Three of them span more than two volumes, which `IR.concat/1` has never seen.** P1612
runs across three, and **L1557 across four**. The URN assumption was re-checked on the raw
files rather than assumed to generalise:

    L1557   4 volumes   104,959 lines   juan 1->17, 17->34, 34->51, 51->80
              anchor-only collisions  78,080
              juan+anchor collisions       0

Page numbering restarts at each volume, so the bare anchor collides seventy-eight thousand
times; the juan disambiguates every one. Note the boundaries **overlap** — volume 130 ends
in juan 17 and volume 131 begins in juan 17 — so the rule is not "each volume holds whole
fascicles" but "juan is monotonic and may straddle a boundary", and the absence of
collisions inside a shared juan is measured rather than argued.

`config/dev.exs` pool timeout 300s -> 600s in advance: L1557 assembles to 104,959 lines in
one transaction, 1.4x the X1571 load that forced 120s -> 300s. Raised from a measurement
taken before the bake instead of from a failure during it.

### The index rebuild moves the gate by six cases, over unchanged data — 2026-08-27

The experiment that had to be run, and the answer is worse than the guess. HNSW index
rebuilt over **completely unchanged data** — same corpus, same 966,931 vectors, same code,
byte-identical inputs — and the full 1,400-case gate re-run:

    overall             93.4% -> 92.9%    -6 cases
    retrieval/tibetan   50.0% -> 43.8%    -4 cases
    retrieval/pali      81.3% -> 80.7%    -1
    retrieval/chinese   96.6% -> 96.1%    -1

**Nothing changed except the graph.** An HNSW build is randomised, so reindexing the same
vectors yields different approximate neighbourhoods, and Tibetan absorbs most of it for a
reason already on record: BGE-M3 packs Tibetan at **0.9727 mean pairwise cosine** against
0.84 for Pāli, so its candidates are near-ties by construction and reorder under any
perturbation while the other traditions mostly hold position.

**What this retires.** The noise floor was published this morning as **1 case**, measured
by running the identical configuration twice against the identical index. That number is
correct and it measures only query nondeterminism. Across a rebuild the floor is **at
least 4 cases on `retrieval/tibetan` and 6 overall** — four to six times larger.

**What it does and does not invalidate**, stated precisely because the difference matters:

| kind of change | rebuilds the index? | floor |
|---|---|---|
| configuration — depth, rerank, `rrf_k`, balance | no | ~1 case |
| corpus or embedding — import, re-embed, chunk size | **yes** | ≥4 Tibetan, ≥6 overall |

So the configuration findings stand: per-arm depth, the reranker's +46, `balance:
:tradition`, `hnsw.ef_search` — none of those rebuilt the index. **The Tibetan claims
attached to corpus changes do not.** Today's own "J improved Tibetan by 2 cases" was
already refused on reasoning; it is now refuted by measurement, and refuted in the
direction of being smaller than the noise rather than larger.

It also means `retrieval/tibetan`'s recorded history — 48.4%, 46.9%, 50.0%, 43.8% — is one
number with a ±4-case band around it, not a trend.

**What was changed as a result.** `mix pramana.evals.compare --rebuilt` uses 4, measured,
and the proportional guard moved from 5% to 10% of a row because 4 cases on a 64-case row
is 6.25% and a 5% cap would have called a measured non-event a regression. The threshold
is set by the measurement rather than by a round number, and if a later probe measures a
wider swing it moves again.

**Still owed:** one rebuild is one sample. Four is a floor on the floor, not the floor, and
three or four rebuilds would give a real distribution. Until then, treat a Tibetan movement
under five cases across any corpus change as carrying no information.

### The alternative editions are not alternative witnesses — 2026-08-27

Stated twice today, written into `docs/PLAN.md` and a commit message: acquiring K, A, P,
L, U, S and M would turn the **572,701 segments carrying a variant apparatus** into
passages a reader could open, because those readings name 【宋】【元】【明】【麗】 editions
the corpus did not hold.

**Measured after baking: of 57 works, 2 share a title with anything in T, X or J.**

CBETA does not publish a parallel Koryŏ *text* of the Taishō's works. Its K is a selection
of what is **distinctive to** that edition — 高麗國新雕大藏校正別錄, the Koryŏ's own
collation record; 御製秘藏詮 and 御製逍遙詠, Song imperial compositions preserved there;
新集藏經音義隨函錄, a phonetic glossary. A is Song catalogue records (大中祥符法寶錄,
景祐新修法寶錄) and 趙城金藏 survivals. L is largely Ming-Qing Chan recorded sayings.

The error was reasoning from the *name* of a collection to its *contents*, which is the
same mistake as reading a two-letter code as a canon name — refused three hours earlier in
`Cbeta.Collections` for exactly this reason, and then made anyway one level up. A
collection called "the Qianlong Canon" containing 21 works is not the Qianlong Canon; it is
what CBETA chose to digitise from it.

**What this leaves open.** The apparatus gap is real and is not closable from CBETA:
opening a 【麗】 reading needs the Koryŏ text of *that Taishō work*, which is the Tripiṭaka
Koreana project — a new source with its own licence and citation grammar, not a collection
flag. Recorded as such rather than quietly dropped.

**What survives.** 57 works of rare material, much of it digitised nowhere else, and the
first exercise of `IR.concat/1` four volumes deep (L1557, 1,329,342 characters).
