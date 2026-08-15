defmodule Pramana.Retrieval.Survey do
  @moduledoc """
  Exhaustive counts over the corpus, rather than a ranked sample.

  Top-k retrieval structurally cannot answer "how often does the canon actually say
  this, and where?" — it returns the best five hits and says nothing about whether
  there are six or six thousand, or whether they cluster in one text or spread across
  the tradition. A model given five hits will happily generalise from them.

  So this counts everything: total occurrences, distinct works, and the breakdown by
  composition origin, text role, and division. The idea is taken from
  `tripitaka-mcp`'s `survey_corpus`, which is the best single idea in that project.

  Counting is done in SQL over the bigram index, so it stays fast at 4.7M segments.
  """

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  @type opts :: [
          origin: String.t() | [String.t()],
          role: String.t() | [String.t()],
          division: String.t(),
          top_works: pos_integer()
        ]

  @doc """
  Surveys the corpus for a phrase.

      survey("一切眾生皆有佛性")
      survey("空", origin: "indic")

  Returns totals plus breakdowns. Every number is a full count, never a sample.
  """
  @spec survey(String.t(), opts()) :: {:ok, map()} | {:error, atom()}
  def survey(query, opts \\ [])

  def survey(query, opts) when is_binary(query) do
    case String.trim(query) do
      "" -> {:error, :empty_query}
      phrase -> {:ok, run(phrase, opts)}
    end
  end

  def survey(_, _), do: {:error, :bad_query}

  defp run(phrase, opts) do
    pattern = "%" <> escape_like(phrase) <> "%"
    top_n = Keyword.get(opts, :top_works, 10)

    base =
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        join: w in Work,
        on: w.id == t.work_id,
        where: like(s.content, ^pattern)

    base = apply_filters(base, opts)

    %{
      query: phrase,
      total_segments: Repo.aggregate(base, :count),
      distinct_works: Repo.one(from [s, t, w] in base, select: count(w.id, :distinct)),
      by_origin: group_count(base, :composition_origin),
      by_role: group_count(base, :text_role),
      by_division: division_count(base),
      top_works: top_works(base, top_n),
      bake_id: Pramana.Bake.current_id(),
      # Survey is the tool whose whole purpose is supporting claims about how often and
      # WHERE something occurs, so it is the one place a missing part of the canon turns
      # directly into a false claim — "no Japanese-composed hits" read as "the Japanese
      # tradition is silent". Absent when nothing is missing.
      coverage_caveat: Pramana.Coverage.caveat()
    }
  end

  defp apply_filters(query, opts) do
    query
    |> filter_in(opts[:origin], :composition_origin)
    |> filter_in(opts[:role], :text_role)
    |> filter_division(opts[:division])
    |> filter_license(opts)
  end

  # See `Pramana.Retrieval.Lexical.filter_license/2`. A survey is a claim about how much
  # the corpus contains, so it must be able to answer that question for a PUBLIC corpus
  # too, not only the full one.
  defp filter_license(query, opts) do
    query
    |> filter_redistributable(opts[:redistributable_only])
    |> filter_license_class(opts[:license_class])
  end

  defp filter_redistributable(query, true) do
    join(query, :inner, [s, t], src in Source, on: src.id == t.source_id and src.redistributable)
  end

  defp filter_redistributable(query, _), do: query

  defp filter_license_class(query, nil), do: query

  defp filter_license_class(query, value) do
    values = List.wrap(value)

    join(query, :inner, [s, t], src in Source,
      on: src.id == t.source_id and src.license_class in ^values
    )
  end

  defp filter_in(query, nil, _field), do: query

  defp filter_in(query, value, field) do
    values = List.wrap(value)
    where(query, [_s, _t, w], field(w, ^field) in ^values)
  end

  defp filter_division(query, nil), do: query
  defp filter_division(query, division), do: where(query, [_s, _t, w], w.division == ^division)

  defp group_count(base, field) do
    Repo.all(
      from [s, t, w] in base,
        group_by: field(w, ^field),
        select: {field(w, ^field), count(s.id)},
        order_by: [desc: count(s.id)]
    )
    |> Enum.map(fn {key, n} -> %{key: key || "unattributed", segments: n} end)
  end

  defp division_count(base) do
    Repo.all(
      from [s, t, w] in base,
        where: not is_nil(w.division),
        group_by: [w.division, w.division_en],
        select: {w.division, w.division_en, count(s.id)},
        order_by: [desc: count(s.id)]
    )
    |> Enum.map(fn {zh, en, n} -> %{division: zh, division_en: en, segments: n} end)
  end

  # Which texts carry the phrase most heavily. Concentration in one work versus spread
  # across a tradition is exactly what a ranked sample hides.
  defp top_works(base, limit) do
    Repo.all(
      from [s, t, w] in base,
        group_by: [w.id, w.title, w.composition_origin, w.text_role, w.division],
        select: {w.id, w.title, w.composition_origin, w.text_role, w.division, count(s.id)},
        order_by: [desc: count(s.id)],
        limit: ^limit
    )
    |> Enum.map(fn {id, title, origin, role, division, n} ->
      %{
        work_id: id,
        title: title,
        composition_origin: origin,
        text_role: role,
        division: division,
        segments: n
      }
    end)
  end

  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
