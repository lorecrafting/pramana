# Cloud: What To Rent, For Which Job

Prices checked 2026-08-14. **GPU markets move weekly and Vast.ai spot moves by the
minute — re-check before committing.**

## First: these are three different jobs, with three different answers

Conflating them is how people end up paying hyperscaler rates for batch work.

| job | when | needs |
|---|---|---|
| **A. Batch embedding** | now, once | ~30–50 min of GPU, then nothing |
| **B. Hosting the app + Postgres** | if/when it goes public | 24/7 CPU + RAM + disk, **no GPU** |
| **C. LLM inference for the Phase 7 agent** | later | tokens, not machines |

**Pramāṇa needs no GPU to serve.** Retrieval is Postgres plus a query embedding that
measures 0.3–0.5 s on CPU. There is no ongoing GPU cost in this design at all — which
is worth knowing before anyone signs up for a GPU instance by the month.

---

## Job A — batch embedding: 289,179 chunks, once

BGE-M3 (568M params) at ~300 tokens per chunk, fp16, batch 64. Realistic throughput is
150–400 chunks/s on a modern card, so **15–50 minutes**, and about an hour of wall clock
once you count model download and transfer.

| provider | card | $/hr | ~1 hr job | notes |
|---|---|---|---|---|
| **Modal** (serverless) | L4 | ~0.80 equiv | **$0.00** | per-**second** billing, **$30/mo free credit**, nothing to shut down |
| RunPod Community | RTX 4090 | 0.34 | $0.34 | cheapest instance-based |
| Vast.ai | RTX 4090 | 0.35–0.50 | ~$0.45 | marketplace; verify host reputation |
| RunPod Secure | RTX 4090 | 0.69 | $0.69 | |
| **GCP** g2-standard-4 | L4 | 0.71 | $0.71 | + GPU quota request |
| **AWS** g6.xlarge | L4 | 0.805 | $0.81 | + GPU quota request |
| **AWS** g5.xlarge | A10G | 1.006 | $1.01 | |

### Why AWS and GCP lose this one

Not mainly price, though they are **2–3× RunPod/Vast** for identical silicon. Two
things matter more:

1. **GPU quota.** A new AWS or GCP account has an effective GPU quota of zero. You file
   a limit-increase request and wait hours to days. For a job you want to run today,
   that is the whole story. (AWS has also been reported to be raising GPU instance
   prices ~20%.)
2. **Blast radius.** Hyperscaler billing is easy to leave running. A 4090 forgotten for
   a week is $60–120; an idle GPU instance is the classic cloud bill surprise.

They win for **job B**, not this one.

### Recommendation for job A: Modal

- **Per-second billing with no idle charge**, so a 40-minute job costs 40 minutes.
- **$30/month of free credits**, and this job is well under $1 of compute — so in
  practice **free**.
- **Nothing to forget to destroy.** The function exits, billing stops. That removes the
  single most expensive failure mode.
- Excellent CLI and Python ergonomics: `modal run` executes a local Python file on a
  remote GPU, streaming logs back.

Second choice: **RunPod Community 4090** at $0.34/hr if you would rather have a plain
SSH box. `docs/GPU_RUNBOOK.md` covers that path; `priv/embed/modal_embed.py` covers this
one.

---

## Job B — hosting the app (later, if it goes public)

Not a GPU question, and the hyperscalers are a poor fit here too. The corpus is a 3.7 GB
Postgres with a 1.3 GB bigram index and (once embedded) ~1.2 GB of vectors, plus HNSW.
That wants RAM and fast local disk, not elasticity.

| option | ~monthly | notes |
|---|---|---|
| **Hetzner** dedicated / CCX | €30–60 | 8–16 cores, 32–64 GB. Best value by a wide margin |
| DigitalOcean / Linode | $60–120 | simpler, pricier |
| AWS/GCP equivalent | $150–300+ | plus egress, plus managed-Postgres premium |
| Fly.io / Render | $50–150 | nice Elixir story; watch disk pricing |

For a self-hosted, non-commercial scholarly tool, **Hetzner + Postgres on the box** is
the sane default. Managed Postgres (RDS/Cloud SQL) mostly buys backups you can get from
`pg_dump` plus a lockfile — and remember `sources.lock.json` *is* the backup here, since
the corpus is reproducible from it.

---

## Job C — LLM inference for the research agent (Phase 7)

**Do not self-host a model for this.** A GPU capable of running a strong model costs
$0.70–4/hr *whether or not anyone is asking questions*, which is $500–3,000/month for a
tool with bursty, low-volume usage. Token APIs cost nothing when idle.

This also matters architecturally: `CLAUDE.md`'s decoupling contract says the model is
swappable and the corpus is the durable asset. Renting a GPU to pin one open-weights
model is exactly the coupling the design avoids. Use an API, keep the guard, and swap
models freely.

---

## CLI control, since you asked

All the credible options are scriptable; they differ in *what* you script.

| provider | tool | shape |
|---|---|---|
| **Modal** | `modal` | `modal run script.py` — you write a Python function, it runs on a GPU. No instance concept at all. |
| **Vast.ai** | `vastai` | search the marketplace by price/spec, then create/destroy. Genuinely good for scripted, price-sensitive spin-up. |
| **RunPod** | `runpodctl` + REST/GraphQL | container-first, template-based |
| **AWS** | `aws` | the most complete, and the most ceremony (VPC, SG, AMI, key pair) |
| **GCP** | `gcloud` | similar, somewhat friendlier defaults |

For a job measured in minutes, Modal's model is the least ceremony by a distance: no
VPC, no key pair, no security group, no instance to reap.

---

## Bottom line

- **Now (job A): Modal.** Free inside the monthly credit, per-second billing, nothing to
  leave running. Fall back to RunPod Community 4090 at $0.34/hr.
- **Do not open an AWS or GCP account for this.** Quota approval alone outlasts the job.
- **Later (job B): Hetzner**, not a hyperscaler, unless something else forces the choice.
- **Never (job C): don't rent GPUs for LLM inference.** Use an API.
- **Total for embedding the entire Chinese Buddhist canon: about $0.50, or free.** The
  interesting constraints in this project are correctness and provenance, not compute.
