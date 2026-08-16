defmodule Pramana.Evals.Score do
  @moduledoc """
  Turns case outcomes into a scorecard.

  ## What the numbers mean, and what they do not

  A score is reported **per case type**, never as one headline figure. Recall@k over
  retrieval questions and pass rate over guard questions measure different things, and
  averaging them produces a number that sounds like an accuracy and means nothing. The
  competitor claim this project exists to answer — "~98% of served answers are
  trustworthy" — is exactly that kind of number.

  Stale cases are excluded from the denominator and reported separately. A case whose
  premises no longer hold is not evidence either way, and counting it as a failure would
  make an out-of-date gold set look like a broken retriever.

  Adversarial cases are also broken out. A gold set of easy questions can score highly
  while telling you nothing about the failures that matter — a question whose only answer
  is in material we do not hold, or a quotation that has been altered by one character.
  """

  @doc "Aggregates results into a scorecard."
  @spec summarize([map()], non_neg_integer()) :: map()
  def summarize(results, elapsed_ms) do
    by_type =
      results
      |> Enum.group_by(& &1.case.type)
      |> Map.new(fn {type, rs} -> {type, tally(rs)} end)

    %{
      total: length(results),
      elapsed_ms: elapsed_ms,
      by_type: by_type,
      adversarial: results |> Enum.filter(& &1.case.adversarial) |> tally(),
      by_tradition:
        results
        |> Enum.reject(&(&1.case.tradition == nil))
        |> Enum.group_by(& &1.case.tradition)
        |> Map.new(fn {tradition, rs} -> {tradition, tally(rs)} end),
      # Type CROSSED with tradition, because the interesting comparisons live in the
      # cells and vanish in either margin. Topical cases scored 55% overall, which hides
      # that the same twelve questions score 100% asked in Chinese and 0% asked in
      # English — a difference the by-tradition row alone cannot show, since it mixes
      # case types, and the by-type row cannot show either.
      by_type_tradition:
        results
        |> Enum.reject(&(&1.case.tradition == nil))
        |> Enum.group_by(&{&1.case.type, &1.case.tradition})
        |> Map.new(fn {key, rs} -> {key, tally(rs)} end),
      # "Was the user answered at all", as distinct from "is this canon reachable".
      # A topic is satisfied when ANY of the cases asking it hit, because a reader who
      # asks about the four noble truths is well served by the Pāli or by the Chinese
      # Āgama. Kept ALONGSIDE the per-tradition rates rather than replacing them: the two
      # answer different questions and only one of them tells you a canon has gone dark.
      by_topic: topic_tally(results),
      overall: tally(results),
      failures: Enum.filter(results, &match?({:miss, _}, &1.outcome)),
      stale: Enum.filter(results, &match?({:stale, _}, &1.outcome))
    }
  end

  defp topic_tally(results) do
    grouped =
      results
      |> Enum.reject(&(&1.case.topic == nil))
      |> Enum.group_by(& &1.case.topic)

    answered =
      Enum.count(grouped, fn {_topic, rs} ->
        Enum.any?(rs, &match?({:hit, _}, &1.outcome))
      end)

    %{
      topics: map_size(grouped),
      answered: answered,
      rate: if(map_size(grouped) > 0, do: Float.round(100 * answered / map_size(grouped), 1)),
      unanswered:
        grouped
        |> Enum.reject(fn {_topic, rs} -> Enum.any?(rs, &match?({:hit, _}, &1.outcome)) end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()
    }
  end

  defp tally(results) do
    hits = Enum.count(results, &match?({:hit, _}, &1.outcome))
    misses = Enum.count(results, &match?({:miss, _}, &1.outcome))
    stale = Enum.count(results, &match?({:stale, _}, &1.outcome))
    scored = hits + misses

    %{
      hits: hits,
      misses: misses,
      stale: stale,
      scored: scored,
      # nil, not 0.0, when nothing was scored. A rate over zero cases is not zero
      # percent; it is the absence of a measurement, and printing 0.0% would be a claim.
      rate: if(scored > 0, do: Float.round(100 * hits / scored, 1), else: nil),
      # Where a hit was found, for retrieval cases. The mean rank matters as much as the
      # rate: recall@10 with everything at rank 9 is a different system from recall@10
      # with everything at rank 1.
      mean_rank: mean_rank(results)
    }
  end

  defp mean_rank(results) do
    ranks =
      results
      |> Enum.flat_map(fn
        %{outcome: {:hit, %{rank: rank}}} -> [rank]
        _ -> []
      end)

    case ranks do
      [] -> nil
      ranks -> Float.round(Enum.sum(ranks) / length(ranks), 2)
    end
  end

  @doc """
  Renders a scorecard as plain text, for the terminal and for pasting into docs.
  """
  @spec render(map()) :: String.t()
  def render(scorecard) do
    """
    #{header(scorecard)}

    #{section("BY CASE TYPE", scorecard.by_type)}
    #{section("BY TRADITION", scorecard.by_tradition)}
    #{cross_section(scorecard.by_type_tradition)}
    #{topics(scorecard.by_topic)}
    #{adversarial(scorecard.adversarial)}
    #{stale(scorecard.stale)}
    #{failures(scorecard.failures)}
    """
  end

  defp header(s) do
    """
    pramana evals — #{s.total} case(s) in #{Float.round(s.elapsed_ms / 1000, 1)}s
      scored:  #{s.overall.scored}   hits #{s.overall.hits}   misses #{s.overall.misses}
      stale:   #{s.overall.stale}   (premises no longer hold; excluded from the rate)
      overall: #{rate(s.overall)}
    """
  end

  defp section(_title, map) when map == %{}, do: ""

  defp section(title, map) do
    rows =
      map
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join("\n", fn {key, t} ->
        "      #{String.pad_trailing(to_string(key), 16)} #{rate(t)}" <>
          "  (#{t.hits}/#{t.scored})#{rank_suffix(t)}#{stale_suffix(t)}"
      end)

    "    #{title}\n#{rows}\n"
  end

  defp cross_section(map) when map == %{}, do: ""

  defp cross_section(map) do
    rows =
      map
      |> Enum.sort_by(fn {{type, tradition}, _} -> {to_string(type), tradition} end)
      |> Enum.map_join("\n", fn {{type, tradition}, t} ->
        label = "#{type} / #{tradition}"

        "      #{String.pad_trailing(label, 28)} #{rate(t)}" <>
          "  (#{t.hits}/#{t.scored})#{rank_suffix(t)}"
      end)

    "    BY CASE TYPE x TRADITION\n#{rows}\n"
  end

  defp rank_suffix(%{mean_rank: nil}), do: ""
  defp rank_suffix(%{mean_rank: rank}), do: "  mean rank #{rank}"

  defp stale_suffix(%{stale: 0}), do: ""
  defp stale_suffix(%{stale: n}), do: "  [#{n} stale]"

  defp rate(%{rate: nil}), do: "no cases scored"
  defp rate(%{rate: rate}), do: "#{rate}%"

  defp topics(%{topics: 0}), do: ""

  defp topics(t) do
    unanswered =
      case t.unanswered do
        [] -> ""
        list -> "\n      unanswered: #{Enum.join(list, ", ")}"
      end

    "    ANSWERED FROM ANY TRADITION   #{t.rate}%  (#{t.answered}/#{t.topics} topics)" <>
      unanswered <> "\n"
  end

  defp adversarial(%{scored: 0}), do: ""

  defp adversarial(t) do
    "    ADVERSARIAL       #{rate(t)}  (#{t.hits}/#{t.scored})\n"
  end

  defp stale([]), do: ""

  defp stale(results) do
    lines =
      Enum.map_join(Enum.take(results, 10), "\n", fn %{case: kase, outcome: {:stale, reason}} ->
        "      #{kase.id}: #{inspect(reason)}"
      end)

    "\n    STALE — the gold set is out of date, not the retriever\n#{lines}\n"
  end

  defp failures([]), do: ""

  defp failures(results) do
    lines =
      Enum.map_join(Enum.take(results, 15), "\n", fn %{case: kase, outcome: {:miss, detail}} ->
        "      [#{kase.type}] #{kase.id}\n" <>
          "        #{describe(kase)}\n" <>
          "        #{inspect(detail, limit: 3, printable_limit: 200)}"
      end)

    "\n    FAILURES\n#{lines}\n"
  end

  defp describe(%{query: nil, quote: quoted}) when is_binary(quoted),
    do: "quote: #{String.slice(quoted, 0, 60)}"

  defp describe(%{query: query}) when is_binary(query), do: "query: #{query}"
  defp describe(_), do: ""

  @doc """
  A compact map for machine consumption — the CI gate and the README table.

  Deliberately separate from `render/1`: a number that a gate reads and a number a human
  reads should come from the same computation, not from parsing a report.
  """
  @spec to_map(map()) :: map()
  def to_map(scorecard) do
    %{
      "total" => scorecard.total,
      "overall" => rate_of(scorecard.overall),
      "stale" => scorecard.overall.stale,
      "by_type" => Map.new(scorecard.by_type, fn {k, v} -> {to_string(k), rate_of(v)} end),
      "by_type_tradition" =>
        Map.new(scorecard.by_type_tradition, fn {{type, tradition}, v} ->
          {"#{type}/#{tradition}", rate_of(v)}
        end),
      "adversarial" => rate_of(scorecard.adversarial),
      "answered_any_tradition" => %{
        "rate" => scorecard.by_topic.rate,
        "answered" => scorecard.by_topic.answered,
        "topics" => scorecard.by_topic.topics
      }
    }
  end

  defp rate_of(t), do: %{"rate" => t.rate, "hits" => t.hits, "scored" => t.scored}
end
