defmodule Pramana.Repo.Migrations.IndexTranslationText do
  @moduledoc """
  Makes the translation layer searchable.

  210,756 English renderings were reachable only through their anchor URN — you could ask
  "what does Sujato say about *this* line" and never "which line does Sujato render with
  this phrase". So an English query went to the lexical retriever, which reads `segments`,
  and came back with **Pāli passages that happened to share character n-grams**: three
  confident-looking results with nothing to do with the question. On the public artefact,
  where the renderings are most of what a reader can use, that is the whole surface.

  ## Full-text search here, and pg_bigm everywhere else, for the same underlying reason

  `CLAUDE.md` is emphatic that classical Chinese must never meet whitespace tokenization,
  because it has no whitespace and trigrams cannot serve two-character queries. The rule is
  about matching the tool to the script, not about preferring bigrams — and English is the
  other case: it has whitespace, morphology and stop words, so a stemmed `tsvector` is
  correct and character n-grams would be actively worse.

  ## The index is partial, on `lang = 'en'`

  `to_tsvector('english', …)` applies English stemming and an English stop list. Running
  that over a Vietnamese or German rendering would index it wrongly and silently, so the
  index covers only the language it is configured for. Everything is `en` today; the
  predicate is what makes adding another language a decision rather than an accident.
  """

  use Ecto.Migration

  # CONCURRENTLY needs its own transaction, and a 210k-row index does not need it.
  def change do
    create index(:translations, ["to_tsvector('english', text)"],
             using: :gin,
             where: "lang = 'en'",
             name: :translations_text_en_fts_index
           )
  end
end
