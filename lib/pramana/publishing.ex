defmodule Pramana.Publishing do
  @moduledoc """
  What may be published, and whether a given database is safe to expose.

  `CLAUDE.md` is unambiguous: **we publish the pipeline, not the corpus**, and a public
  demo serves the CC0/CC-BY subset only. This module is the one place that decides what
  that subset is, so the check, the lockfile filter and the bake cannot disagree about it.

  ## A filter is not an enforcement mechanism

  `license_class:` is an option on some retrieval queries, and `Pramana.Corpus.resolve/1`
  takes no such option at all — a public URN endpoint over the research database serves
  every text in it, CBETA included. Options are things a caller can forget.

  So the public artefact is a **separate bake from a separate lockfile into a separate
  database**, and safety is a property of what is present rather than of what every query
  remembers to exclude. That is the same reasoning as invariant #3: reproducibility is a
  property of the artefact, not of anyone following the rules.

  ## Three buckets, because `redistributable` is false for two different reasons

  A licence that forbids redistribution and a licence we could not confirm are not the
  same fact, and reporting them together hides the actionable half. It did: 76,040 rows of
  CC0 public-domain text were counted as "must not be served" alongside CBETA, when what
  they needed was a publication record, not permission. See `audit/0`.

  ## Conservative defaults hide their own errors

  Storing `redistributable: false` when unsure is right, and it is **indistinguishable
  from a correct answer** — nothing fails, no query errors, the text is merely absent from
  everything public. The only way it surfaces is by counting what the caution costs, which
  is why `audit/0` reports the withheld bucket separately rather than folding it into the
  forbidden one.
  """

  import Ecto.Query

  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.Sources

  # Licences under which redistribution is permitted outright. A row carrying one of these
  # and still flagged not-redistributable was withheld by OUR uncertainty, not by its
  # terms — `mix pramana.sc.translations` stores `redistributable: false` whenever the
  # licence was inferred rather than matched to a publication record.
  @permissive ~w(CC0-1.0 CC-PDM-1.0 CC-BY-4.0 CC-BY-SA-4.0 CC-BY-SA-3.0)

  @type row :: %{
          id: String.t(),
          name: String.t(),
          spdx: String.t() | nil,
          redistributable: boolean(),
          rows: non_neg_integer()
        }

  @type audit :: %{
          servable: [row()],
          forbidden: [row()],
          withheld: [row()],
          safe?: boolean()
        }

  @doc """
  Source ids whose licence permits redistribution, from `Pramana.Sources`.

  Declared, not measured: this is what MAY go into a public artefact, whether or not any
  of it has been acquired.
  """
  @spec sources() :: [String.t()]
  def sources do
    Sources.ids()
    |> Enum.filter(&publishable?/1)
    |> Enum.sort()
  end

  @doc "Whether a source id may be published."
  @spec publishable?(String.t()) :: boolean()
  def publishable?(source_id) when is_binary(source_id) do
    case Sources.fetch(source_id) do
      {:ok, source} -> source.license.redistributable
      _ -> false
    end
  end

  @doc """
  What a public deployment of the connected database would serve, in three buckets.

  `safe?` is true only when `forbidden` is empty. A non-empty `withheld` does not make a
  database unsafe — that content simply will not be served.
  """
  @spec audit() :: audit()
  def audit do
    rows = text_rows() ++ translation_rows()
    {servable, held} = Enum.split_with(rows, & &1.redistributable)
    {withheld, forbidden} = Enum.split_with(held, &(&1.spdx in @permissive))

    %{
      servable: servable,
      forbidden: forbidden,
      withheld: withheld,
      safe?: forbidden == []
    }
  end

  @doc "Total rows across a bucket."
  @spec total([row()]) :: non_neg_integer()
  def total(rows), do: rows |> Enum.map(& &1.rows) |> Enum.sum()

  defp text_rows do
    Repo.all(
      from t in Text,
        join: s in Source,
        on: s.id == t.source_id,
        group_by: [s.id, s.name, s.license_spdx, s.redistributable],
        order_by: [desc: count(t.id)],
        select: %{
          id: s.id,
          name: s.name,
          spdx: s.license_spdx,
          redistributable: s.redistributable,
          rows: count(t.id)
        }
    )
  end

  # TRANSLATIONS ARE NOT IN `texts` AND CARRY THEIR OWN FLAG, because a rendering's licence
  # is not its source text's. A check answering "what would leak" from one of the two
  # tables it can leak from is the coverage-denominator failure again — rule 44.
  defp translation_rows do
    Repo.all(
      from t in "translations",
        group_by: [t.translator_id, t.redistributable, t.license_spdx],
        order_by: [desc: count(t.id)],
        select: %{
          id: t.translator_id,
          name: "translation layer",
          spdx: t.license_spdx,
          redistributable: t.redistributable,
          rows: count(t.id)
        }
    )
  end
end
