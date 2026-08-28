# Deploying a public Pramāṇa

**We publish the pipeline, not the corpus.** A deployment serves the redistributable
subset that `mix pramana.public.bake` produces, and the image contains no corpus at all —
the database is external and is built separately.

## The three properties that make this safe

1. **A separate bake into a separate database.** Not a query filter. `license_class:` is an
   option on some retrieval queries and `Corpus.resolve/1` takes none at all, so a public
   URN endpoint over the research corpus serves every text in it. Safety is a property of
   what is present.
2. **The release has no Mix.** A deployed node physically cannot acquire, bake or ingest,
   so invariant #7 — *tools read, the CLI writes* — is a property of the image rather than
   a rule the router enforces.
3. **`PRAMANA_PUBLIC=1` audits the database it actually connected to, and refuses to
   serve.** The bake is careful and the deploy is one environment variable; a `DATABASE_URL`
   typo would otherwise start a healthy node serving CBETA to the public with nothing
   anywhere reporting it. Verified in a real release, both directions.

       DATABASE_URL=…/pramana_dev     PRAMANA_PUBLIC=1  →  REFUSED, node stops
       DATABASE_URL=…/pramana_public  PRAMANA_PUBLIC=1  →  ALLOWED

## Build it

```bash
createdb pramana_public
PRAMANA_DATABASE=pramana_public mix ecto.migrate
PRAMANA_DATABASE=pramana_public mix pramana.public.bake   # verifies itself
PRAMANA_DATABASE=pramana_public mix pramana.chunk
docker build -t pramana .
```

Then run it with `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, and `PRAMANA_PUBLIC=1`.

## What it costs to host, honestly

The public corpus is **3.5 GB** without vectors, and roughly **6 GB** with them — 260,073
chunk vectors at 1024 dimensions plus an HNSW index. That number decides everything below,
and it rules out every free managed Postgres:

| | free storage | verdict |
|---|---|---|
| Neon | 0.5 GB | 7× too small |
| Supabase | 0.5 GB | 7× too small |
| Render Postgres | 1 GB, expires at 90 days | too small, and not permanent |
| Fly Postgres | volumes are billed | ~$1/mo for the volume, not free |

**The one genuinely free option that fits is a free-tier VM you run Postgres on yourself.**

- **Oracle Cloud Always Free** — 4 ARM cores, 24 GB RAM, 200 GB block storage, free with no
  time limit. It is the only free tier in this table that can hold 6 GB and run pgvector,
  and 24 GB of RAM is enough that the HNSW index stays in page cache. The catch is that
  ARM capacity in popular regions is often unavailable; it is worth trying more than once.
- **Google Cloud** e2-micro is free forever but has 1 GB of RAM. It will hold the data on
  disk and thrash on any vector query. Lexical-only, it would work.
- **AWS free tier** is 12 months, not forever.

If none of that appeals, a €4/month Hetzner CX22 is the honest answer and about a tenth the
effort.

**Or serve less.** Nothing requires the whole subset. A demo of the Pāli canon alone —
`mix pramana.public.bake` minus the two Degé sources — is well under a gigabyte and fits a
free tier comfortably. `Coverage.caveat/0` will say what is missing, which is the point: a
smaller demo that states its own boundaries is a better demonstration of this project than
a larger one that does not.

## What it cannot do yet

**No vectors.** The public corpus is chunked but not embedded, so retrieval is lexical
only, and `retrievers` in every response says so. Embedding 1.8 M segments is a GPU spend
and a separate decision; see `docs/GPU_RUNBOOK.md`.

The translation layer *is* searchable — `Translations.search/2` over a Postgres FTS index —
so an English question reaches the 210,756 English renderings rather than returning Pāli
that happens to share character n-grams with it.
