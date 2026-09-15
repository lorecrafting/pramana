"""Compare the base embedder against the Tibetan LoRA adapter, language by language.

The checkpoint before spending on a full re-embed. A fine-tuned model is a DIFFERENT
model — its vectors are not comparable to base-model vectors in one index — so adopting
it means re-embedding all 617,038 vectors. This decides whether that is worth doing.

Two things are measured, on identical text, base and adapted:

1. **Mean pairwise cosine** per language. The defect is that unrelated Tibetan passages
   sit at 0.9727 while Pāli sits at 0.8397 and Chinese at 0.8039 — a 0.98 "hit" in
   Tibetan is close to noise. Lower is better here: it means the space separates.
2. **Whether Chinese and Pāli move.** Training on Tibetan can drag the other languages,
   and Chinese is the largest part of the corpus at 300,165 vectors with 97.1% retrieval
   already. A Tibetan gain paid for with a Chinese regression is not a gain.
"""

import json

import modal

MODEL = "BAAI/bge-m3"
GPU = "L4"
MAX_LENGTH = 320

TORCH = "torch==2.13.0"
TRANSFORMERS = "transformers==5.15.0"
PEFT = "peft==0.19.0"

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(TORCH, TRANSFORMERS, PEFT)
    .env({"HF_XET_HIGH_PERFORMANCE": "1"})
    .run_commands(
        f"python -c \"from transformers import AutoModel, AutoTokenizer; "
        f"AutoModel.from_pretrained('{MODEL}'); AutoTokenizer.from_pretrained('{MODEL}')\""
    )
)

app = modal.App("pramana-probe-adapter", image=image)
volume = modal.Volume.from_name("pramana-embed", create_if_missing=True)


def mean_pool(hidden, attention_mask):
    mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
    return (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)


@app.function(gpu=GPU, volumes={"/data": volume}, timeout=60 * 60)
def probe():
    import torch
    import torch.nn.functional as F
    from peft import PeftModel
    from transformers import AutoModel, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(MODEL)
    base = AutoModel.from_pretrained(MODEL).cuda().eval()

    def encode(model, texts, batch_size=16):
        out = []
        for i in range(0, len(texts), batch_size):
            batch = tokenizer(
                texts[i : i + batch_size],
                padding=True,
                truncation=True,
                max_length=MAX_LENGTH,
                return_tensors="pt",
            ).to("cuda")
            with torch.no_grad(), torch.autocast("cuda", dtype=torch.bfloat16):
                hidden = model(**batch).last_hidden_state
            pooled = mean_pool(hidden.float(), batch["attention_mask"])
            out.append(F.normalize(pooled, p=2, dim=1))
        return torch.cat(out)

    def spread(vectors):
        """Mean pairwise cosine, excluding self-similarity."""
        similarity = vectors @ vectors.T
        n = len(vectors)
        off = similarity.sum() - similarity.diag().sum()
        return (off / (n * n - n)).item()

    def discrimination(model, pairs):
        """Do genuinely related passages outrank unrelated ones?

        Mean pairwise cosine measures DISPERSION, not discrimination — a random
        projection would spread vectors beautifully and retrieve nothing. What matters is
        the GAP: adjacent chunks of one work are related text, and a chunk drawn from
        elsewhere is not. If that gap collapses, the model has stopped telling them apart
        however wide the space has become.
        """
        a = encode(model, [p["a"] for p in pairs])
        b = encode(model, [p["b"] for p in pairs])
        related = (a * b).sum(dim=1).mean().item()
        # Shift b by one to pair each chunk with someone else's neighbour.
        unrelated = (a * b.roll(1, 0)).sum(dim=1).mean().item()
        return related, unrelated, related - unrelated

    languages = ["bo", "pli", "lzh"]
    texts = {
        lang: [json.loads(line)["text"] for line in open(f"/data/probe_{lang}.jsonl")]
        for lang in languages
    }

    # `PeftModel.from_pretrained` injects the adapter into `base` IN PLACE, so anything
    # measured through `base` afterwards is the ADAPTED model. Measuring "before" and
    # "after" by holding two references gives bit-identical numbers and looks like a
    # perfectly preserved model — it is the same model twice. `disable_adapter()` is the
    # only honest toggle.
    model = PeftModel.from_pretrained(base, "/data/tibetan_lora").eval()

    results = {}
    for lang in languages:
        with model.disable_adapter():
            base_spread = spread(encode(model, texts[lang]))
        results[lang] = {"base": base_spread, "adapted": spread(encode(model, texts[lang]))}

    adjacent = {
        lang: [json.loads(line) for line in open(f"/data/adj_{lang}.jsonl")]
        for lang in languages
    }

    for lang in languages:
        with model.disable_adapter():
            results[lang]["base_disc"] = discrimination(model, adjacent[lang])

        results[lang]["adapted_disc"] = discrimination(model, adjacent[lang])

    for lang in languages:
        r = results[lang]
        br, bu, bg = r["base_disc"]
        ar, au, ag = r["adapted_disc"]
        verdict = "KEPT" if ag >= bg * 0.9 else "LOST"
        print(
            f"{lang}: spread {r['base']:.4f}->{r['adapted']:.4f} | "
            f"gap base {bg:+.4f} (rel {br:.3f} unrel {bu:.3f}) -> "
            f"adapted {ag:+.4f} (rel {ar:.3f} unrel {au:.3f})  {verdict}",
            flush=True,
        )

    return results


@app.local_entrypoint()
def main():
    print(probe.remote())
