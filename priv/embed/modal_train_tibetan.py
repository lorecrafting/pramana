"""LoRA fine-tune of BGE-M3 on aligned Tibetan-English pairs, on Modal's L4.

## Why

BGE-M3 barely separates Tibetan. Measured over 20,000 random pairs per language, mean
pairwise cosine is 0.9727 for `bo` against 0.8397 `pli` and 0.8039 `lzh` — two *random*
Tibetan chunks sit at ~0.97, so a 0.98 "hit" carries almost no information. Recall is
fine; ranking is weak, and it caps a third of the corpus. A cross-encoder reranker was
tried first because it needs no training, and scored Tibetan at exactly chance. The
embedder itself has to learn the language.

## What is trained

LoRA adapters on the attention projections only. The 568M base weights stay frozen, so
what ships is a small adapter that can be discarded if it does not earn its place. The
objective is InfoNCE over in-batch negatives: each Tibetan folio is pulled toward its own
English rendering and pushed away from every other rendering in the batch. That is
directly the defect — "unrelated Tibetan passages sit at 0.97" is what in-batch negatives
punish.

## The part that must not drift

Pooling, normalisation and `MAX_LENGTH` are copied from `modal_embed.py` and must stay
identical to it. A vector's meaning is decided by how the token states are reduced, not
only by the weights: train with mean pooling and serve with CLS and the adapter is
worthless, silently. Same reason the library versions are pinned there.

## What this does NOT touch

Citations. A fine-tuned embedder changes what is *found*. The passage cited is still the
Tibetan, resolved and guard-verified exactly as before. See `CLAUDE.md` invariant #2.
"""

import json
import os

import modal

MODEL = "BAAI/bge-m3"
GPU = "L4"

# Identical to `modal_embed.py`. Training at a different window than inference would
# teach the model on text the served model never sees.
MAX_LENGTH = 320

# Pinned for the reason given in `modal_embed.py`: a stable name that silently resolves
# to different code is how an index quietly stops being comparable with itself.
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

app = modal.App("pramana-train-tibetan", image=image)
volume = modal.Volume.from_name("pramana-embed", create_if_missing=True)


def mean_pool(hidden, attention_mask):
    """Mean over real tokens only. Copied verbatim from `modal_embed.py`."""
    mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
    return (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)


@app.function(gpu=GPU, volumes={"/data": volume}, timeout=60 * 60 * 4)
def train(
    epochs: int = 2,
    batch_size: int = 24,
    lr: float = 1e-4,
    rank: int = 16,
    holdout: int = 500,
):
    import torch
    import torch.nn.functional as F
    from peft import LoraConfig, get_peft_model
    from transformers import AutoModel, AutoTokenizer

    pairs = [json.loads(line) for line in open("/data/tibetan_pairs.jsonl")]
    # A fixed holdout, taken before shuffling, so the reported number is not the one the
    # adapter was fitted to. Without it "loss went down" says nothing about retrieval.
    validation, training = pairs[:holdout], pairs[holdout:]
    print(f"{len(training)} training pairs, {len(validation)} held out", flush=True)

    tokenizer = AutoTokenizer.from_pretrained(MODEL)
    model = AutoModel.from_pretrained(MODEL).cuda()

    # Both sides of every pair are encoded before the backward pass, so two full graphs
    # of batch x MAX_LENGTH are live at once and an L4's 22 GB does not hold them at
    # batch 24 in fp32. Recomputing activations instead of storing them trades ~30% speed
    # for the memory, which is the right trade here: shrinking the batch would weaken the
    # training signal itself, since the in-batch negatives ARE the supervision.
    model.gradient_checkpointing_enable()
    model.enable_input_require_grads()

    # Attention projections only. XLM-RoBERTa names them `query`/`key`/`value`; touching
    # the feed-forward as well trains far more parameters for little gain on a set this
    # size, and every extra trained parameter is more room to forget Chinese and Pāli.
    config = LoraConfig(
        r=rank,
        lora_alpha=rank * 2,
        lora_dropout=0.05,
        bias="none",
        target_modules=["query", "key", "value"],
    )
    model = get_peft_model(model, config)
    model.print_trainable_parameters()

    optimizer = torch.optim.AdamW(
        [p for p in model.parameters() if p.requires_grad], lr=lr
    )

    def encode(texts):
        batch = tokenizer(
            texts,
            padding=True,
            truncation=True,
            max_length=MAX_LENGTH,
            return_tensors="pt",
        ).to("cuda")
        # bf16 for the forward pass: half the activation memory, and an L4 runs it
        # natively. The pooled vector is cast back to fp32 before normalising, because
        # the similarity matrix and the loss are sensitive to precision in a way the
        # hidden states are not.
        with torch.autocast("cuda", dtype=torch.bfloat16):
            out = model(**batch).last_hidden_state

        pooled = mean_pool(out.float(), batch["attention_mask"])
        # Normalised, because the index compares by inner product on unit vectors.
        return F.normalize(pooled, p=2, dim=1)

    def info_nce(bo, en, temperature=0.05):
        """Each folio against its own rendering, and against every other in the batch.

        The diagonal is the true pair; everything off it is a negative that the model
        currently rates at ~0.97. Symmetric, so the penalty applies in both directions —
        an English question must find its Tibetan and a Tibetan passage its English.
        """
        logits = bo @ en.T / temperature
        labels = torch.arange(len(bo), device=logits.device)
        return (
            F.cross_entropy(logits, labels) + F.cross_entropy(logits.T, labels)
        ) / 2

    @torch.no_grad()
    def validate():
        model.eval()
        ranks, spreads = [], []
        for i in range(0, len(validation), batch_size):
            batch = validation[i : i + batch_size]
            if len(batch) < 4:
                continue
            bo = encode([p["bo"] for p in batch])
            en = encode([p["en"] for p in batch])
            similarity = bo @ en.T
            gold = similarity.diag()
            # Retrieval rank of the true rendering among the batch, and how far the true
            # pair sits above the rest. The spread is the number that matters: the defect
            # is that unrelated passages are indistinguishable, not that pairs are far.
            ranks += (similarity > gold.unsqueeze(1)).sum(dim=1).add(1).tolist()
            off = similarity - torch.eye(len(batch), device=similarity.device) * 2
            spreads += (gold - off.max(dim=1).values).tolist()
        model.train()
        top1 = sum(1 for r in ranks if r == 1) / max(len(ranks), 1)
        mrr = sum(1 / r for r in ranks) / max(len(ranks), 1)
        return top1, mrr, sum(spreads) / max(len(spreads), 1)

    top1, mrr, spread = validate()
    print(f"BEFORE  top1={top1:.3f} mrr={mrr:.3f} margin={spread:+.4f}", flush=True)

    import random

    step = 0
    for epoch in range(epochs):
        random.Random(epoch).shuffle(training)

        for i in range(0, len(training), batch_size):
            batch = training[i : i + batch_size]
            if len(batch) < 4:
                continue

            loss = info_nce(
                encode([p["bo"] for p in batch]), encode([p["en"] for p in batch])
            )
            loss.backward()
            optimizer.step()
            optimizer.zero_grad()
            step += 1

            if step % 100 == 0:
                print(f"epoch {epoch} step {step} loss {loss.item():.4f}", flush=True)

        top1, mrr, spread = validate()
        print(
            f"EPOCH {epoch}  top1={top1:.3f} mrr={mrr:.3f} margin={spread:+.4f}",
            flush=True,
        )

    os.makedirs("/data/tibetan_lora", exist_ok=True)
    model.save_pretrained("/data/tibetan_lora")
    volume.commit()
    print("adapter written to /data/tibetan_lora", flush=True)
    return {"top1": top1, "mrr": mrr, "margin": spread}


@app.function(gpu=GPU, volumes={"/data": volume}, timeout=60 * 60)
def export_merged():
    """Fold the adapter into the base weights and write a loadable model to the volume.

    The GPU embeds documents with the adapter, but QUERIES are embedded locally by
    Bumblebee, and it cannot apply a PEFT adapter. If the two sides use different weights
    the ranking is noise and nothing fails — so the merged model has to come back whole.

    Merged rather than shipped as base + adapter for the same reason `modal_embed.py`
    merges: one set of weights, one code path, no runtime adapter arithmetic.
    """
    from peft import PeftModel
    from transformers import AutoModel, AutoTokenizer

    model = AutoModel.from_pretrained(MODEL)
    model = PeftModel.from_pretrained(model, "/data/tibetan_lora").merge_and_unload()
    model.save_pretrained("/data/merged_model", safe_serialization=True)

    # The tokenizer is untouched by LoRA, but shipping it with the weights keeps the
    # directory self-contained and loadable without reaching for the Hub.
    AutoTokenizer.from_pretrained(MODEL).save_pretrained("/data/merged_model")

    volume.commit()
    print("merged model written to /data/merged_model", flush=True)


@app.local_entrypoint()
def main(epochs: int = 2, batch_size: int = 24, lr: float = 1e-4, merge_only: bool = False):
    if merge_only:
        export_merged.remote()
    else:
        print(train.remote(epochs=epochs, batch_size=batch_size, lr=lr))
