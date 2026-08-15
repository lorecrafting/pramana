# Variant-character equivalence classes

`unihan_variants.tsv` — one equivalence class per line, characters concatenated.

## Where it comes from

Derived from the Unicode Character Database's **Unihan_Variants.txt**.

| | |
|---|---|
| upstream | `https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip` |
| `Unihan.zip` sha256 | `f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e` |
| upstream last-modified | 2025-08-18 |
| derived on | 2026-08-15 |
| licence | Unicode License (permissive, requires attribution) |

Regenerate by unioning three fields into equivalence classes:
`kSimplifiedVariant`, `kTraditionalVariant`, `kZVariant`.

Result: **6,447 classes over 13,066 characters** — 說説说, 眾众衆, 為为爲, 戶户戸.

## What is deliberately EXCLUDED, and why

- **`kSemanticVariant`** (2,151 pairs). It means "characters that share a meaning",
  which mixes true orthographic variants with genuinely *different words*. Expanding a
  search across those would return passages using another word, and a precision failure
  is worse than a recall miss here because the reader cannot see it.

  **Known cost:** 眞/真 is filed under `kSemanticVariant`, so searching 眞 will not find
  真. In this corpus that matters little — CBETA has 真 113,073 times and 眞 once — but
  it is a real gap, not an oversight.

- **`kSpoofingVariant`.** Visually confusable characters with different meanings. Exactly
  what must never be silently substituted.

## This is a QUERY-side table

It is never applied at index time. Stored text stays byte-identical to the witness:
which Han form an edition prints is scholarly data, not noise. See
`Pramana.Retrieval.Variants`.
