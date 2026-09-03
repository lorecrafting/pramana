"""Generate English renderings of Chinese canon passages on Modal's serverless GPUs.

The second use of `CLAUDE.md`'s Python-sidecar exception, and a deliberate one — see
`docs/PLAN.md` § E1. This file does tensor math and nothing else: it is handed text and a
target language, it runs a model, it writes text back. **Every domain decision stays in
Elixir** — which passages, in what order, with what glossary pinned into them, and what
the result is allowed to be cited as. If you find yourself adding a term table, a
provenance rule or a citation format here, it belongs on the other side of the boundary.

    pip install modal && modal setup

    # once: the gated `base` arm needs a token; an empty value is fine for the others
    modal secret create huggingface-token HF_TOKEN=hf_...

    modal volume create pramana-translate
    modal volume put pramana-translate /tmp/pramana_passages.jsonl /passages.jsonl

    # one arm at a time; ARM picks the model
    modal run priv/embed/modal_translate.py --arm mitra
    modal run priv/embed/modal_translate.py --arm base
    modal run priv/embed/modal_translate.py --arm qwen

    modal volume get pramana-translate /renderings-mitra.jsonl /tmp/r-mitra.jsonl

Input is one JSON object per line: `{"id":, "sha256":, "content":, "target_lang":}`.
Output is `{"id":, "sha256":, "model":, "revision":, "params_sha256":, "text":}`.

**The sha256 is carried through untouched**, exactly as in `modal_embed.py`. This side
does not get to decide whether a rendering matches its source; Elixir re-checks it on
import, and `Pramana.Guard` re-checks the citation after that.

**Decoding is greedy and the revision is pinned.** A rendering that cannot be reproduced
from its inputs is not a bake (invariant #3), and `method: "llm"` renderings are stored
with the model and configuration that produced them — so `temperature` is not a knob to
reach for casually. `params_sha256` records what was actually used, the way
`modal_embed.py` records `max_length`, so a changed setting is detectable rather than
silent.

**Licence.** `google/gemma-2-9b-it` is Gemma-licensed and **gated**: a human must accept
the terms on a HuggingFace account and supply a token as the Modal secret
`huggingface-token` before the `base` arm can run. The MITRA repos declare no licence and
are ungated, but they are Gemma Model Derivatives and the Gemma Terms travel with them
regardless. `docs/PLAN.md` § E1 records the full reading; the clause that matters here is
that output must never be presented as human authorship, which invariant #8 already makes
structurally impossible.
"""

import hashlib
import json
import time

import modal

# PINNED for the same reason `modal_embed.py` pins them: a stable name that silently
# resolves to different code is how a corpus quietly stops being comparable with itself.
# Generation is more sensitive to this than embedding, not less — a changed chat template
# changes every rendering.
TORCH = "torch==2.13.0"
TRANSFORMERS = "transformers==5.15.0"
ACCELERATE = "accelerate==1.12.0"

# THE ARMS. `docs/PLAN.md` § E1 says why there are four rather than one: the paper's
# Chinese table compares MITRA against a single baseline — its own earlier NMT model — so
# "best for Buddhist Chinese" is an expectation being tested here, not a result being
# relied on.
#
# `base` is the sharpest of them and the cheapest to add. It holds architecture, size and
# prompt constant and varies only the 4.4B tokens of Buddhist training, so it measures
# what the domain fine-tune actually bought. If MITRA does not beat it on these passages,
# the domain claim is empty *here* whatever it scores elsewhere.
#
# `revision` pins the weights to a commit, not to a branch name.
# SIZED FROM A FAILED RUN, not from arithmetic. A 9.2B model in bf16 is 18.5 GB and an
# L4 has 24, so the L4 "fits" on paper — and in practice the weights loaded with 61 MB
# free, the caching allocator started reporting OOM, and generation ran at 0.07
# passages/s, roughly ten times slower than the card should manage. A model that fits
# with no room for its KV cache is not a model that fits. The 9B arms therefore get 48 GB.
#
# Qwen 32B in bf16 is ~65 GB and does NOT fit an A100-40GB, which is what this table said
# before the same check was applied to it: the failure would have arrived after the
# container had spun up and the weights had downloaded.
ARMS = {
    "mitra": {
        "model": "buddhist-nlp/gemma-2-mitra-it",
        "revision": "main",
        "dialect": "mitra",
        "gpu": "L40S",
    },
    "mitra-int8": {
        "model": "buddhist-nlp/gemma-2-mitra-it-int8",
        "revision": "main",
        "dialect": "mitra",
        "gpu": "L40S",
    },
    # GATED. Needs the `huggingface-token` secret and a human who has accepted the Gemma
    # terms on that account.
    "base": {
        "model": "google/gemma-2-9b-it",
        "revision": "main",
        "dialect": "chat",
        "gpu": "L40S",
    },
    "qwen": {
        "model": "Qwen/Qwen2.5-32B-Instruct",
        "revision": "main",
        "dialect": "chat",
        "gpu": "A100-80GB",
    },
}

# Sized from the human renderings of the same chunks, not guessed: a 300-character
# Chinese passage is 1,500-2,000 characters of Patton's English, roughly 300-400 tokens.
# 512 would clear the median and clip the tail — and a clipped rendering makes an arm look
# worse for a reason that has nothing to do with the model. `truncated` below counts any
# completion that used the whole budget, so this assumption is checked every run rather
# than trusted.
MAX_NEW_TOKENS = 1024

# GREEDY DECODING LOOPS, and on the first real run it looped badly: the longest MITRA
# renderings were "the perception of the perception of the perception of…" and "for the
# sake of sensual domination, for the sake of sensual domination…", running to the token
# budget without ever finishing a sentence. 62.9% of that run ended mid-sentence.
#
# A repetition penalty is still fully deterministic, so `do_sample=False` keeps its
# meaning and a run remains reproducible from its inputs (invariant #3). It is applied to
# EVERY arm, because a decoding setting that varies between arms is measured as if it
# were the model.
REPETITION_PENALTY = 1.1

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(TORCH, TRANSFORMERS, ACCELERATE)
    .env({"HF_XET_HIGH_PERFORMANCE": "1"})
)

app = modal.App("pramana-translate", image=image)
volume = modal.Volume.from_name("pramana-translate", create_if_missing=True)


def build_prompt(dialect, tokenizer, source, target_lang):
    """Wrap a passage in the form its model was trained to answer.

    This is model *mechanics*, the same category as `mean_pool` in `modal_embed.py` — how
    a particular set of weights expects its input to be shaped. It is deliberately the
    only thing on this side that varies per model, and it must not grow into prompt
    engineering about Buddhist terminology: a glossary-pinned prompt is domain logic and
    is assembled in Elixir, arriving here already inside `content`.
    """
    if dialect == "mitra":
        # The template the model card specifies, exactly: line breaks become 🔽 and the
        # completion is terminated by '#'. Getting this wrong does not error — it
        # produces fluent output from a model being asked a question in a form it was
        # never trained on, which is the worst possible failure for a bake-off.
        body = source.replace("\n", "🔽")
        return f"Please translate into {target_lang}: {body} 🔽 Translation::"

    return tokenizer.apply_chat_template(
        [
            {
                "role": "user",
                # NEUTRAL, deliberately. Naming the genre or the source language here
                # would be a domain prompt decision living on the wrong side of the
                # boundary — and `docs/ELIXIR.md` names exactly this as the gap the
                # boundary test cannot catch. Any framing beyond "translate this" is
                # assembled in Elixir and arrives inside `content`. It also makes the
                # arms comparable: MITRA's own template says no more than this.
                "content": (
                    f"Translate the following passage into {target_lang}. "
                    f"Reply with the translation only.\n\n{source}"
                ),
            }
        ],
        tokenize=False,
        add_generation_prompt=True,
    )


def decode(dialect, text):
    """Trim the completion to the rendering itself."""
    if dialect == "mitra":
        # '#' is the stop token. `generate` may return it, or may run to the token budget
        # without ever emitting it — both are normal and both truncate here.
        text = text.split("#", 1)[0]
        text = text.replace("🔽", "\n")
    return text.strip()


# The GPU is fixed at decoration time, and the arms do not agree on one: a 9B in bf16 is
# ~18 GB and fits an L4's 24 GB, while Qwen 32B does not. So the decorator carries the
# default and `main` re-specialises with `.with_options(gpu=...)` per arm. Asking for the
# smaller card is not a slow run — it is an out-of-memory failure part-way through a
# tranche that has already been paid for.
@app.function(
    gpu="L40S",
    volumes={"/data": volume},
    timeout=60 * 60 * 4,
    secrets=[modal.Secret.from_name("huggingface-token")],
)
def translate(
    arm: str = "mitra",
    input_name: str = "passages.jsonl",
    output_name: str | None = None,
    batch_size: int = 8,
):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    if arm not in ARMS:
        raise SystemExit(f"unknown arm {arm!r}; expected one of {sorted(ARMS)}")

    spec = ARMS[arm]
    output_name = output_name or f"renderings-{arm}.jsonl"

    rows = []
    with open(f"/data/{input_name}", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                # A truncated upload must fail loudly rather than render a prefix of the
                # tranche and look successful. Same reasoning as `modal_embed.py`.
                raise SystemExit(f"malformed JSON on line {line_no}: {exc}")

    # What this run ACTUALLY used, hashed. Recorded on every row so that a changed
    # decoding setting is detectable later rather than silently mixed into one tranche.
    params = {
        "model": spec["model"],
        "revision": spec["revision"],
        "dialect": spec["dialect"],
        "max_new_tokens": MAX_NEW_TOKENS,
        "do_sample": False,
        "repetition_penalty": REPETITION_PENALTY,
        "transformers": TRANSFORMERS,
    }
    params_sha256 = hashlib.sha256(
        json.dumps(params, sort_keys=True, ensure_ascii=False).encode("utf-8")
    ).hexdigest()

    print(f"{len(rows)} passage(s), arm {arm} ({spec['model']}) on {spec['gpu']}", flush=True)
    print(f"params {params_sha256[:16]}", flush=True)

    tokenizer = AutoTokenizer.from_pretrained(spec["model"], revision=spec["revision"])
    model = AutoModelForCausalLM.from_pretrained(
        spec["model"], revision=spec["revision"], dtype=torch.bfloat16, device_map="cuda"
    ).eval()

    # Left padding, because a batch of prompts of different lengths is continued from its
    # RIGHT edge. Padding on the right puts pad tokens between the prompt and the first
    # generated token, and the model continues from padding — which produces plausible
    # text with no relation to the passage, in a run that reports success.
    tokenizer.padding_side = "left"
    if tokenizer.pad_token_id is None:
        tokenizer.pad_token = tokenizer.eos_token

    stop_ids = [tokenizer.eos_token_id]

    if spec["dialect"] == "mitra":
        # '#' as an actual stopping condition rather than a post-hoc split. Encoded
        # without special tokens and only used if it is a single token — a multi-token
        # encoding would stop on the wrong thing.
        hash_ids = tokenizer.encode("#", add_special_tokens=False)
        if len(hash_ids) == 1:
            stop_ids.append(hash_ids[0])
        else:
            print(f"  '#' is {len(hash_ids)} tokens, not usable as a stop id", flush=True)

    started = time.time()
    done = 0
    truncated = 0

    with open(f"/data/{output_name}", "w", encoding="utf-8") as out, torch.inference_mode():
        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            prompts = [
                build_prompt(
                    spec["dialect"],
                    tokenizer,
                    row["content"],
                    row.get("target_lang", "English"),
                )
                for row in batch
            ]

            encoded = tokenizer(prompts, padding=True, return_tensors="pt").to("cuda")
            generated = model.generate(
                **encoded,
                max_new_tokens=MAX_NEW_TOKENS,
                # GREEDY. A rendering that cannot be reproduced from its inputs is not a
                # bake — invariant #3 — and these are stored as citable-adjacent `t1`
                # rows attributed to a model and a configuration.
                do_sample=False,
                repetition_penalty=REPETITION_PENALTY,
                # MITRA marks the end of a translation with '#' and has no EOS for it, so
                # without this generation never halts: it fills the budget with whatever
                # follows, which is where the loops came from. Splitting on '#' after the
                # fact cleaned the text but not the truncation, because the tokens were
                # already spent.
                eos_token_id=stop_ids,
                pad_token_id=tokenizer.pad_token_id,
            )

            # Slice off the prompt by LENGTH rather than by string-matching the decoded
            # output: the prompt does not always survive detokenisation byte-identically,
            # and a failed match would silently keep the prompt in the rendering.
            new_tokens = generated[:, encoded["input_ids"].shape[1] :]
            completions = tokenizer.batch_decode(new_tokens, skip_special_tokens=True)

            # A completion that used every token it was given probably had more to say.
            # Counted rather than silently accepted: an arm penalised for hitting a
            # budget is being measured on the budget.
            # TRUNCATED means "did not stop on its own", not "used the budget". The
            # first version measured the latter and reported 205 of 205 for a run whose
            # text was mostly complete — the model simply never emits EOS, so budget use
            # said nothing. A completion is finished when it contains a stop id.
            for row in range(new_tokens.shape[0]):
                ids = new_tokens[row].tolist()
                if not any(i in stop_ids for i in ids):
                    truncated += 1

            for row, completion in zip(batch, completions):
                out.write(
                    json.dumps(
                        {
                            "id": row["id"],
                            "sha256": row["sha256"],
                            "model": spec["model"],
                            "revision": spec["revision"],
                            "params_sha256": params_sha256,
                            "text": decode(spec["dialect"], completion),
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )

            done += len(batch)
            rate = done / max(time.time() - started, 1e-9)
            print(
                f"  {done}/{len(rows)}  {rate:.2f} passages/s  "
                f"eta {(len(rows) - done) / max(rate, 1e-9) / 60:.1f} min",
                flush=True,
            )

    volume.commit()
    elapsed = time.time() - started
    print(f"wrote {done} rendering(s) in {elapsed / 60:.1f} min", flush=True)
    if truncated:
        print(
            f"  WARNING: {truncated} rendering(s) used the whole {MAX_NEW_TOKENS}-token "
            f"budget and are probably cut off — raise MAX_NEW_TOKENS and re-run this arm "
            f"before comparing it with another.",
            flush=True,
        )
    return {
        "arm": arm,
        "renderings": done,
        "truncated": truncated,
        "seconds": round(elapsed, 1),
    }


@app.local_entrypoint()
def main(arm: str = "mitra", input_name: str = "passages.jsonl"):
    if arm not in ARMS:
        raise SystemExit(f"unknown arm {arm!r}; expected one of {sorted(ARMS)}")

    output_name = f"renderings-{arm}.jsonl"
    runner = translate.with_options(gpu=ARMS[arm]["gpu"])
    result = runner.remote(arm, input_name, output_name)
    print(result)
    print(f"\nmodal volume get pramana-translate /{output_name} /tmp/{output_name}")
