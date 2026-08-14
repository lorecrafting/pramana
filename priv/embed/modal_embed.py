"""Embed exported Pramāṇa chunks on Modal's serverless GPUs.

The recommended path — see `docs/CLOUD.md`. Per-second billing, a $30/month free credit
that comfortably covers the whole corpus, and no instance to forget to destroy, which is
the most expensive failure mode of renting GPUs by the hour.

    pip install modal && modal setup

    # push the export (once)
    modal volume create pramana-embed
    modal volume put pramana-embed /tmp/pramana_chunks.jsonl /chunks.jsonl

    # run
    modal run priv/embed/modal_embed.py

    # pull the vectors back
    modal volume get pramana-embed /vectors.jsonl /tmp/pramana_vectors.jsonl
    mix pramana.embed.import --in /tmp/pramana_vectors.jsonl

The embedding configuration MUST match `Pramana.Embed`, or these vectors are not
comparable with the 阿含部 ones already in the database — mean pooling over the attention
mask, L2 normalisation, max length 320. `chunks.embedding_model` records the model per
row precisely so a mismatch is detectable rather than silent.

As with `embed_gpu.py`, the sha256 is carried through UNTOUCHED. This side does not get
to decide whether a vector matches its text; Elixir re-checks it on import.
"""

import json
import time

import modal

MODEL = "BAAI/bge-m3"
MAX_LENGTH = 320
DIMS = 1024

# L4 is the value pick for this workload: BGE-M3 is ~1.1 GB in fp16, so a bigger card
# buys memory that goes unused. Swap to "A10G" or "A100" if you want it finished sooner.
GPU = "L4"

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install("torch", "transformers", "hf_transfer")
    # Bake the weights into the image so every run does not re-download 2.2 GB.
    .env({"HF_HUB_ENABLE_HF_TRANSFER": "1"})
    .run_commands(
        f"python -c \"from transformers import AutoModel, AutoTokenizer; "
        f"AutoModel.from_pretrained('{MODEL}'); AutoTokenizer.from_pretrained('{MODEL}')\""
    )
)

app = modal.App("pramana-embed", image=image)
volume = modal.Volume.from_name("pramana-embed", create_if_missing=True)


def mean_pool(hidden, attention_mask):
    """Mean over real tokens only.

    Averaging over padding would make a vector depend on its batch rather than its text,
    so the same chunk would embed differently in different batches.
    """
    mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
    return (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)


@app.function(gpu=GPU, volumes={"/data": volume}, timeout=60 * 60 * 4)
def embed(input_name: str = "chunks.jsonl", output_name: str = "vectors.jsonl", batch_size: int = 64):
    import torch
    from transformers import AutoModel, AutoTokenizer

    rows = []
    with open(f"/data/{input_name}", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                # A truncated upload must fail loudly rather than embed a prefix of the
                # corpus and look successful.
                raise SystemExit(f"malformed JSON on line {line_no}: {exc}")

    print(f"{len(rows)} chunk(s) to embed on {GPU}", flush=True)

    tokenizer = AutoTokenizer.from_pretrained(MODEL)
    model = AutoModel.from_pretrained(MODEL).cuda().half().eval()

    started = time.time()
    done = 0

    with open(f"/data/{output_name}", "w", encoding="utf-8") as out, torch.inference_mode():
        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            encoded = tokenizer(
                [r["content"] for r in batch],
                padding=True,
                truncation=True,
                max_length=MAX_LENGTH,
                return_tensors="pt",
            ).to("cuda")

            pooled = mean_pool(model(**encoded).last_hidden_state, encoded["attention_mask"])
            vectors = torch.nn.functional.normalize(pooled, p=2, dim=1).float().cpu()

            if vectors.shape[1] != DIMS:
                raise SystemExit(f"expected {DIMS} dims, model produced {vectors.shape[1]}")

            for row, vector in zip(batch, vectors):
                out.write(
                    json.dumps(
                        {
                            "id": row["id"],
                            "sha256": row["sha256"],
                            "embedding": [round(v, 6) for v in vector.tolist()],
                        }
                    )
                    + "\n"
                )

            done += len(batch)
            if done % (batch_size * 25) == 0 or done == len(rows):
                rate = done / max(time.time() - started, 1e-9)
                print(
                    f"  {done}/{len(rows)}  {rate:.1f} chunks/s  "
                    f"eta {(len(rows) - done) / max(rate, 1e-9) / 60:.1f} min",
                    flush=True,
                )

    volume.commit()
    elapsed = time.time() - started
    print(f"wrote {done} vectors in {elapsed / 60:.1f} min", flush=True)
    return {"chunks": done, "seconds": round(elapsed, 1)}


@app.local_entrypoint()
def main(input_name: str = "chunks.jsonl", output_name: str = "vectors.jsonl"):
    result = embed.remote(input_name, output_name)
    print(result)
    print(f"\nmodal volume get pramana-embed /{output_name} /tmp/pramana_vectors.jsonl")
    print("mix pramana.embed.import --in /tmp/pramana_vectors.jsonl")
