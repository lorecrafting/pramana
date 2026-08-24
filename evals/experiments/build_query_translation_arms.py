"""Two query-translation arms over the 12 topical/chinese cases.

`expect_contains` is NEVER changed — the scoring target stays the gold Chinese term.
Only the QUERY is rewritten, which is the whole point: the corpus is unchanged and the
question is whether an English query, rendered into Chinese, reaches what the English
one cannot (0/12) and the hand-written Chinese one does (12/12).

Arm A — the term a translator would most likely pick, in a natural Chinese question.
Arm B — a DIFFERENT but legitimate rendering of the same doctrine. This is the arm that
        matters: automatic translation fails by choosing a defensible synonym the corpus
        does not print, and B is built to probe exactly that. Where a term is genuinely
        unambiguous (四聖諦) A and B differ only in phrasing, and that is itself the
        finding — not every term carries the risk.
"""

import json
import os

BASE = os.path.dirname(os.path.abspath(__file__))

# id: (arm A query, arm B query, note on where the ambiguity lies)
ARMS = {
    "top-017": ("何謂四聖諦？", "四諦的內容是什麼？", "四諦 is the common short form"),
    "top-018": ("何謂八正道？", "八聖道分是什麼？", "八聖道分 is the Āgama-register form"),
    "top-019": ("何謂四念處？", "四念住的修法是什麼？", "四念住 is the Xuanzang-register form"),
    "top-020": ("何謂七覺支？", "七菩提分是什麼？", "七菩提分 is an equally standard rendering"),
    "top-021": ("何謂緣起？", "十二因緣是什麼？", "緣起 vs 十二因緣 — the gold term is the latter"),
    "top-022": ("何謂六入處？", "六處是什麼？", "六處 / 六入 / 六入處 all circulate"),
    "top-023": ("如何修安那般那念？", "出入息念如何修習？", "出入息念 is the translated form"),
    "top-024": ("何謂四無量心？", "四等心是什麼？", "四等心 is an older rendering"),
    "top-025": ("何謂三十七道品？", "三十七菩提分法是什麼？", "菩提分法 is the Abhidharma register"),
    "top-026": ("何謂空三昧？", "空定是什麼？", "空定 is the shorter form"),
    "top-027": ("何謂十善業道？", "十善道是什麼？", "十善 / 十善道 are common short forms"),
    "top-028": ("何謂慈悲喜捨？", "四無量的內容是什麼？", "四無量 names the same set"),
}

rows = [json.loads(l) for l in open("/Users/raymondluong/dev/pramana/evals/gold/topical.jsonl")]
zh = [r for r in rows if r.get("tradition") == "chinese"]
assert len(zh) == 12, len(zh)

for arm, idx in (("A", 0), ("B", 1)):
    out = os.path.join(BASE, f"gold_{arm}", "topical.jsonl")
    with open(out, "w") as f:
        for r in zh:
            new = dict(r)
            new["query"] = ARMS[r["id"]][idx]
            f.write(json.dumps(new, ensure_ascii=False) + "\n")
    print(f"arm {arm}: wrote {out}")

print()
print("Ambiguity notes (written before scoring):")
for cid, (_, _, note) in ARMS.items():
    print(f"  {cid}: {note}")
