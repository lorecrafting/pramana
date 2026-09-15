# Archived GPU_RUNBOOK.md: gpu-runbook-measurements — chapter 1

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../gpu-runbook-measurements.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

# Archived GPU_RUNBOOK.md: gpu-runbook-measurements

> Captured from `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc` on 2026-09-15. This is retained evidence, not current instructions. Prices, deployment claims, proposed APIs and outcomes below were not revalidated.
> [Current guide](../../GPU_RUNBOOK.md) · [Documentation](../../README.md)

# Runbook: Embedding the Corpus on a Rented GPU

Step-by-step for the full-corpus embedding run. Roughly **$1–3 and under an hour**.

Why rented rather than hosted API, and why not this laptop, is in `docs/EMBEDDING.md`.
The short version: cost is a wash, but a hosted API silently updates models behind a
stable endpoint name, which breaks `bake_id` reproducibility with no hash to pin and no
visible failure.

---

## A long tranche: detach it, and supervise it by asking Modal

`modal run` creates an **ephemeral** app that Modal stops when the local client
disconnects, so a laptop going to sleep kills the job. `--detach` is what prevents that,
and `bin/pramana-tranche` wraps the pair:

    bin/pramana-tranche mitra trancheC.jsonl trancheC-mitra.jsonl

**The restart condition is "Modal says no app is running", never "our client exited".**
That distinction is the whole point. An attached run and its client live and die together,
so watching the client was safe; a detached run outlives its client, and a supervisor that
restarts on client-exit would put two containers on one output file.

**Both halves were learned the hard way on 2026-09-02.** A 27,956-passage tranche ran
attached under a client-watching supervisor; switching to `--detach` for sleep-safety made
that supervisor unsafe, so it was removed; three hours later the job hit a **four-hour
function timeout** with 53% written and nothing restarted it. Two mitigations, each
assuming the other was in place.

**Size the timeout from the measured rate, not from a neighbouring script.** The four
hours came from `modal_embed.py`, where it is generous. At 0.54 passages/s a 27,956-row
tranche needs about fourteen. `modal_translate.py` now asks for 24h, Modal's per-function
ceiling; a run needing more has to be split, and resumption is what makes splitting free.

**Restarts cost only the weight download**, because `translate/2` resumes: it reads what
is on the volume, skips those ids, and **refuses to resume at all** if their
`params_sha256` does not match the current configuration — so a restart can never blend
two configurations into one tranche. Recovering 14,752 rows twice in one night is what
that field is for.

---

## 0. What you are shipping

**Two steps, and the first one is easy to miss.** Chunking creates `chunks`; the thing
that gets embedded is a `chunk_vectors` row, created empty and filled on import — that is
what makes the sha256 round-trip possible at all, since the row has to exist before there
is anything to re-check against.

```bash
mix pramana.chunk --source cbeta      # segments -> chunks
mix pramana.vectors --source cbeta    # chunks -> empty vector rows
mix pramana.embed.export --out /tmp/pramana_chunks.jsonl
```

Skip the middle step and the export succeeds and reports **`exported 0 chunk(s)`** —
which is indistinguishable from "nothing is outstanding", and is what happened here after
chunking CBETA X: 290,392 chunks existed, none of them had a vector row, and the pending
query looks for vector rows lacking an embedding. `mix pramana.vectors --source cbeta`
built all 290,392 in 29 s and the export then found them.

Measured on the Taishō-only bake (pipeline v3):

```
299,317 chunks   288.5 MB
```

That was the whole corpus **then**. It is not now: CBETA X is baked and unchunked —
1,230 texts, 87.6M characters, so roughly **285k more chunks** at the same 300-character
Literary Chinese window, and by that precedent about **35 minutes and $0.45**. Chunk
before exporting, or the export will faithfully ship a corpus that is missing a
collection. The 阿含部 proof embeddings are gone: the Phase 1 gate's
fidelity fix changed segmentation, and re-chunking replaces chunk rows, so their
vectors went with them. Nothing expensive was lost — this run was always going to
cover everything — but it is why the count is 299,317 rather than the outstanding
289,179 quoted before.

Export is a fresh dump each time and only ever emits chunks that still need a vector,
so re-running after a partial import is safe. Each row carries `content_sha256`, which
is what lets import prove the vector still describes the chunk it claims to.

```bash
gzip -k /tmp/pramana_chunks.jsonl     # ~110 MB, worth it on a metered link
                                      # (the Modal path uploads the plain file)
```

**Watch a `volume put` rather than trusting it.** A 267 MB upload stalled at ~125 MB and
sat there with no error, no timeout and no output — `modal volume put` prints its progress
to a TTY, so a backgrounded run shows nothing at all and a stall is indistinguishable from
slow. `nettop -P -l 1 -x | grep Python.<pid>` gives the byte counter; if it does not move
for a minute, kill it and start again. The retry ran at ~700 KB/s and finished in about
six minutes. Rule 3 below applies here too: make sure the first process is dead before
starting the second.

## 1a. Recommended: Modal (free within the monthly credit)

Per-second billing, a $30/month free credit that covers this job several times over, and
**nothing to forget to destroy** — which is the most expensive failure mode of renting by
the hour. See `docs/CLOUD.md` for why this beats AWS/GCP and instance rental.

### One-time: install the CLI in the project's own venv

Do **not** `pip install modal` globally. `python3` on macOS is Apple's 3.9 from the
Command Line Tools, Homebrew's Python refuses installs outside a venv
(`externally-managed-environment`), and a global install breaks on the next
`brew upgrade`. `priv/embed/.venv/` is already gitignored.

```bash
/opt/homebrew/bin/python3 -m venv priv/embed/.venv
priv/embed/.venv/bin/pip install modal
```

`bin/pramana-modal` wraps that venv, so the path is not something to remember.

```bash
bin/pramana-modal setup      # opens a browser; interactive, run it yourself
```

Verified working: **modal 1.5.4 on Python 3.14.6**. `priv/embed/modal_embed.py` loads
against that client with no deprecation warnings.

### Run it

```bash
bin/pramana-modal volume create pramana-embed
bin/pramana-modal volume put pramana-embed /tmp/pramana_chunks.jsonl /chunks.jsonl

bin/pramana-modal run --detach priv/embed/modal_embed.py   # streams progress back

```

### `--detach`, and why it is not optional

Without it the app is **ephemeral**: it lives only as long as the local client's
heartbeat, and Modal stops it the moment that connection breaks. Measured 2026-08-18 — a
19-minute run over a laptop link died at **121,600 of 170,014 chunks** with
`ConflictError: App state is APP_STATE_STOPPED`, seventeen minutes of GPU time already
spent.

What made that cheap rather than expensive is that **the job streams its output to the
volume as it goes**. 1.2 GiB of vectors were sitting there, the last line parsed cleanly,
and the pipeline is resumable by construction: import what came back, re-export (which
only ever emits chunks that still need a vector), and run the remainder. The loss was
about twelve minutes, not a run.

```bash
bin/pramana-modal volume get pramana-embed /vectors.jsonl /tmp/pramana_vectors.jsonl
mix pramana.embed.import --in /tmp/pramana_vectors.jsonl
```

### Measured, full corpus, 2026-08-14

| stage | |
|---|---|
| image build (pip + baking the weights in) | 86 s, once |
| embed 299,317 chunks on an L4 | **34.1 min at 147.4 chunks/s** |
| upload 288.5 MB / download 3.0 GB | 67 s / 82 s |
| **GPU cost** | **~$0.45**, inside the free credit |

**147 chunks/s is the honest number**, and it is below the "hundreds of chunks/sec" this
runbook used to promise. BGE-M3 is 568M parameters at `max_length=320`, so an L4 is
compute-bound here rather than starved — a bigger card would help, more batching would
not. It is still **114× the 1.29 chunks/s** measured on the M1, which is the whole
argument for renting.

**Incremental import beats a rebuild for a small addition, measured 2026-08-28.** Adding
16,984 vectors to an index already holding 1,020,280 took **15m56s without
`--rebuild-index`**, against **~70 min** for the full rebuild that 30,399 vectors triggered
the same day. The runbook's "a rebuild costs ~36 min regardless of how many rows you
import" holds; what it lacked was the other side of the crossover. **Under ~2% of the index,
skip the rebuild.**

**The import is the slow step, not the embedding**, and the HNSW index is why. Measured
on the same corpus:

| import path | total |
|---|---|
| per-row UPDATE, index maintained incrementally (original) | **88 min** |
| batched UPDATE + `--rebuild-index` | **38.7 min** — 3 min loading, **35.8 min rebuilding the index** |

So storing 299,317 vectors still costs more than computing them (34 min on the GPU), and
`--rebuild-index` buys **2.3×**, not the order of magnitude the row-write rate suggests:
batched writes run at ~1,800 rows/s against ~66/s, but that speedup is almost entirely
eaten by the one-off rebuild.

Two honest caveats:

- **The contributions of batching and of dropping the index were not isolated.** They
  shipped together; 2.3× is the combined, end-to-end figure, which is what you actually
  get.
- **`--rebuild-index` costs ~36 min regardless of how many rows you import.** It wins for
  a full-corpus load and loses badly for a small top-up. That is why it is opt-in.

Budget **~40 minutes** for a full-corpus import and run it in the background.

### Measured again, 2026-08-21, at 617,038 vectors

The corpus doubled (the Tengyur landed) and a Tibetan LoRA adapter was adopted, which
forces a full re-embed. The numbers held, and three of them are rules rather than trivia.

| stage | |
|---|---|
| embed 617,038 chunks on an L4 | **70.0 min at 146.9 chunks/s** |
| the same with the adapter merged in | **no measurable cost** — 144 vs a historical 147 |
| download 6.65 GB | ~4 min |
| import with the index **dropped** | **69 s** for 67,371 rows |
| index rebuild, table not bloated | **15 min 47 s** |
