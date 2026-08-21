defmodule Mix.Tasks.Pramana.Tibetan.Pairs do
  @shortdoc "Exports aligned Tibetan-English pairs for embedder fine-tuning"

  @moduledoc """
  Builds the training set for a Tibetan-aware embedder, from data already in the corpus.

      mix pramana.tibetan.pairs --out priv/train/tibetan_pairs.jsonl
      mix pramana.tibetan.pairs --limit 100 --out /tmp/sample.jsonl

  ## Why this exists

  BGE-M3 barely separates Tibetan. Measured over 20,000 random pairs per language, mean
  pairwise cosine is **0.9727** for `bo` against 0.8397 for `pli` and 0.8039 for `lzh` —
  two *random* Tibetan chunks sit at ~0.97, so a 0.98 "hit" is close to noise. Recall is
  fine; ranking is weak, and it caps a third of the corpus (Tibetan is 215,354 of 617,038
  vectors). A cross-encoder reranker was tried first because it needs no training and
  scored Tibetan at **exactly chance** (top-1 20.0%, MRR 0.522 vs 0.457) — that model has
  no Tibetan competence either. The embedder itself has to learn it.

  ## Folio-level, not chunk-level, and the measurement that decided it

  A chunk carrying both a `source/bo` and a `translation/en` vector is also an aligned
  pair — 32,483 of them exist. They are **not** used, because the English overshoots:
  a chunk's translation vector concatenates every rendering that overlaps the chunk, so
  it describes Tibetan outside the chunk's own span. The character ratio shows it plainly:

  | pairing | bo median | en median | en/bo ratio |
  |---|---|---|---|
  | chunk-level | 1,411 | 3,297 | **2.32** |
  | folio-level | 1,515 | 1,721 | **1.14** |

  84000 renders folio by folio, so a folio's rendering corresponds to exactly the lines
  on it. Chunk pairs also admit up to half the Tibetan unrendered, since
  `Pramana.Chunk.Vectors` builds a translation vector at `@min_coverage 0.5`. Tighter
  supervision wins.

  ## What a positive is

  One folio's Tibetan (its segments joined, in printed order) and 84000's English for that
  folio. Both sides carry the anchor they came from, so any pair can be traced back to a
  citable passage and checked — a training set whose provenance cannot be audited is the
  same problem as a citation that cannot be verified.

  **Hard negatives are not mined here.** They belong with the training run, which knows
  its batch size and sampling strategy; mining them into a static file fixes a choice that
  should stay tunable. The obvious source is same-work, nearby-folio Tibetan — the
  confusions that actually matter — and `work_id` and `anchor` are emitted for exactly
  that.

  ## What this does NOT touch

  Citations. A fine-tuned embedder changes what is *found*; the passage cited is still the
  Tibetan, still resolved through `Pramana.Corpus.resolve/1`, still gated by
  `Pramana.Guard.verify/2`. See `CLAUDE.md` invariant #2 and the standing note against
  training the corpus into a generative model.
  """

  use Mix.Task

  alias Pramana.Repo

  @switches [out: :string, limit: :integer]

  # A pair whose sides are wildly disproportionate is not a translation of that folio —
  # it is an alignment error. Measured p10/p90 of the real distribution is 1.23/2.90 at
  # chunk level and tighter at folio level, so this band rejects the tail without
  # discarding honest variation.
  @min_ratio 0.4
  @max_ratio 4.0

  # Below this a "rendering" is a heading, a folio marker, or an artefact.
  @min_chars 60

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    path = Keyword.get(opts, :out, "priv/train/tibetan_pairs.jsonl")

    File.mkdir_p!(Path.dirname(path))

    {kept, rejected} =
      opts[:limit]
      |> pairs()
      |> Enum.split_with(&usable?/1)

    write(path, kept)
    report(path, kept, rejected)
  end

  defp pairs(limit) do
    query = """
    WITH r AS (
      SELECT tr.anchor_urn,
             tr.text AS en,
             (tr.meta->>'ordinal_start')::int AS o1,
             (tr.meta->>'ordinal_end')::int AS o2,
             t.id AS text_id,
             t.work_id
        FROM translations tr
        JOIN texts t ON t.urn_prefix = split_part(tr.anchor_urn, '@', 1)
       WHERE tr.translator_id = '84000'
         AND tr.lang = 'en'
         AND tr.meta ? 'ordinal_start'
    )
    SELECT r.anchor_urn, r.work_id, r.en,
           string_agg(s.content, '' ORDER BY s.ordinal) AS bo
      FROM r
      JOIN segments s ON s.text_id = r.text_id AND s.ordinal BETWEEN r.o1 AND r.o2
     GROUP BY r.anchor_urn, r.work_id, r.en
    """

    query = if limit, do: query <> " LIMIT #{limit}", else: query

    Repo.query!(query, [], timeout: :infinity).rows
    |> Enum.map(fn [anchor, work_id, en, bo] ->
      %{anchor: anchor, work_id: work_id, en: String.trim(en || ""), bo: String.trim(bo || "")}
    end)
  end

  @doc """
  Whether a pair is proportionate enough to train on.

  Public because this is the substance of the task: a pair that is not really parallel
  teaches the model something false, and nothing downstream flags it the way a bad
  citation would.
  """
  @spec usable?(%{bo: String.t(), en: String.t()}) :: boolean()
  def usable?(%{bo: bo, en: en}) do
    bo_len = String.length(bo)
    en_len = String.length(en)

    bo_len >= @min_chars and en_len >= @min_chars and
      ratio_ok?(en_len / bo_len)
  end

  defp ratio_ok?(ratio), do: ratio >= @min_ratio and ratio <= @max_ratio

  defp write(path, pairs) do
    File.open!(path, [:write, :utf8], fn file ->
      Enum.each(pairs, fn pair ->
        IO.write(file, Jason.encode!(pair) <> "\n")
      end)
    end)
  end

  # Lengths here are GRAPHEMES (`String.length/1`), not codepoints. Tibetan stacks
  # combining marks, so these run below a `length()` count taken in SQL — 1,188 against
  # 1,515 for the same set. Neither is wrong; they are different units.
  defp report(path, kept, rejected) do
    works = kept |> Enum.map(& &1.work_id) |> Enum.uniq() |> length()
    bo = kept |> Enum.map(&String.length(&1.bo)) |> median()
    en = kept |> Enum.map(&String.length(&1.en)) |> median()

    Mix.shell().info("""

    Tibetan-English training pairs
      written:        #{length(kept)}
      rejected:       #{length(rejected)} (length or ratio outside #{@min_ratio}-#{@max_ratio})
      works covered:  #{works}
      bo chars med:   #{bo}
      en chars med:   #{en}
      file:           #{path}

      Positives only. Hard negatives are mined at training time from same-work,
      nearby-folio Tibetan — the confusions that matter — using the emitted work_id
      and anchor.
    """)
  end

  defp median([]), do: 0

  defp median(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end
end
