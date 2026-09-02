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

## One route to decide about before a public deploy — `/check`

`/check` takes a pasted document and runs up to 25 retrievals from it, synchronously.
That is correct for a self-hosted reader with one person in front of it and it is an
obvious workload amplifier from the open internet: the paste box is the cheapest way for a
stranger to make the corpus do 25 surveys. Nothing about it is unsafe — the MCP surface it
executes through is read-only by invariant #7, and a public node serves the public
database — so this is a **capacity** decision, not a safety one.

Three options, in the order they cost: leave it (a small node, and the 200 KB input cap
and 25-replay cap already bound one request), rate-limit the route, or omit it from the
public router. **Decide it deliberately**; it is written here because a route added on
2026-08-31 for a local reader is exactly the kind of thing a later deploy inherits without
anyone having chosen it.

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

**No people, and therefore no dates.** `get_person`, `get_works_by_person` and
`search`'s `composed_after`/`composed_before` are all reached through
`works.authority_id`, and **no work in the public artefact carries one**. That is not a
build defect: DILA's person authority records the Chinese Buddhist tradition, and the
public subset is exactly the part of the corpus that is not CBETA. The tables ship empty
because the migrations run; the data does not, because there is nothing to link.

Nothing degrades silently. A date-filtered search there returns nothing and reports
`date_coverage` as *0 of 13,017*, which is `Pramana.Coverage.dated/0` doing what the whole
module exists for — and it is the right answer, not a bug to route around. But **two of
sixteen tools are inert on the public artefact**, and a demo that lists a tool a caller
cannot use is the discoverability failure of rule 60 pointed the other way. If a public
demo ever ships, either say this on the page or do not register those tools in that
build.
