#!/usr/bin/env python3
"""Embed exported Pramāṇa chunks on a GPU and write vectors back as JSONL.

This is the bake-time-only Python sidecar `docs/ELIXIR.md` anticipated. It does tensor
math and nothing else: no corpus knowledge, no database, no domain rules. Everything
about *which* chunks to embed and whether a vector may be trusted lives in Elixir.

Usage on the rented box:

    pip install torch transformers
    python embed_gpu.py --in chunks.jsonl --out vectors.jsonl

Input  : {"id": 1, "content": "…", "sha256": "…"} per line
Output : {"id": 1, "sha256": "…", "embedding": [1024 floats]} per line

The sha256 is carried through untouched so the Elixir side can prove the vector still
describes the chunk it claims to. Do not compute or "correct" it here — the whole point
is that this side is not trusted to.

Must match Pramana.Embed exactly, or the vectors are not comparable with any already
in the database:

    model            BAAI/bge-m3
    pooling          mean over the last hidden state, attention-masked
    normalisation    L2
    max length       320 tokens  (real chunks measure p99 298)
"""

import argparse
import json
import sys
import time

# torch and transformers are imported inside main() so that --help works on a machine
# without them — useful when checking the invocation before renting anything.

MODEL = "BAAI/bge-m3"
MAX_LENGTH = 320
DIMS = 1024


def read_chunks(path):
    with open(path, encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                # A truncated transfer must fail loudly rather than silently embed a
                # prefix of the corpus.
                raise SystemExit(f"malformed JSON on line {line_no}: {exc}")


def mean_pool(last_hidden_state, attention_mask):
    """Mean over real tokens only.

    Averaging over padding too would make a vector depend on batch padding rather than
    on the text, so two identical chunks in different batches would embed differently.
    """
    mask = attention_mask.unsqueeze(-1).to(last_hidden_state.dtype)
    summed = (last_hidden_state * mask).sum(dim=1)
    counts = mask.sum(dim=1).clamp(min=1e-9)
    return summed / counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="input", required=True)
    parser.add_argument("--out", dest="output", required=True)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--device", default=None)
    args = parser.parse_args()

    import torch
    from transformers import AutoModel, AutoTokenizer

    device = args.device or (
        "cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu"
    )
    if device == "cpu":
        print("WARNING: no GPU found; this will be very slow.", file=sys.stderr)

    print(f"loading {MODEL} on {device}", file=sys.stderr)
    tokenizer = AutoTokenizer.from_pretrained(MODEL)
    model = AutoModel.from_pretrained(MODEL).to(device).eval()
    # fp16 on GPU: roughly 2x throughput, and the difference is far below the noise
    # floor of retrieval ranking.
    if device == "cuda":
        model = model.half()

    rows = list(read_chunks(args.input))
    print(f"{len(rows)} chunk(s) to embed", file=sys.stderr)
    started = time.time()
    done = 0

    with open(args.output, "w", encoding="utf-8") as out, torch.inference_mode():
        for i in range(0, len(rows), args.batch_size):
            batch = rows[i : i + args.batch_size]
            encoded = tokenizer(
                [r["content"] for r in batch],
                padding=True,
                truncation=True,
                max_length=MAX_LENGTH,
                return_tensors="pt",
            ).to(device)

            hidden = model(**encoded).last_hidden_state
            pooled = mean_pool(hidden, encoded["attention_mask"])
            vectors = torch.nn.functional.normalize(pooled, p=2, dim=1).float().cpu()

            if vectors.shape[1] != DIMS:
                raise SystemExit(f"expected {DIMS} dims, model produced {vectors.shape[1]}")

            for row, vector in zip(batch, vectors):
                out.write(
                    json.dumps(
                        {
                            "id": row["id"],
                            # Carried through untouched: this side does not get to
                            # decide whether a vector matches its text.
                            "sha256": row["sha256"],
                            "embedding": [round(v, 6) for v in vector.tolist()],
                        }
                    )
                    + "\n"
                )

            done += len(batch)
            if done % (args.batch_size * 20) == 0 or done == len(rows):
                rate = done / max(time.time() - started, 1e-9)
                eta = (len(rows) - done) / max(rate, 1e-9)
                print(
                    f"  {done}/{len(rows)}  {rate:.1f} chunks/s  eta {eta/60:.1f} min",
                    file=sys.stderr,
                )

    elapsed = time.time() - started
    print(f"wrote {done} vectors to {args.output} in {elapsed/60:.1f} min", file=sys.stderr)


if __name__ == "__main__":
    main()
