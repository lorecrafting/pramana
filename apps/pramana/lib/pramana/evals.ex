defmodule Pramana.Evals do
  @moduledoc """
  A reproducible scorecard for retrieval, citation and provenance.

  ## Why this is its own phase

  `docs/COMPETITIVE.md`: the nearest comparable project asserts "~98% of served answers
  are trustworthy" with no public benchmark, and nobody in this field publishes retrieval
  numbers. Measuring is therefore the cheapest credibility available — and it compounds,
  because every later retrieval change gets measured instead of argued about.

  It also settles questions this codebase has been carrying as open admissions rather
  than facts: whether BGE-M3 is adequate on Literary Chinese, whether translation vectors
  actually improve cross-lingual recall, and whether the 320-token window truncating 23.6%
  of English vectors costs anything.

  ## Where the expected answers come from

  **Nothing here is invented.** A gold case's expected citation is either

  - a **curated parallel** — SuttaCentral's hand-made relations, decades of comparative
    scholarship,
  - a **translation anchor** — a published translator's rendering of a specific segment,
  - a **catalogue fact** — the Taishō's own division table, which classifies every work,
  - or a passage located by the canon's **own definitional formula**.

  Each is checkable independently of this system. A gold set whose answers came from a
  model would measure agreement with that model, which is not the same as being right.

  ## Ground truth is re-verified on every run

  Before scoring a case, the harness confirms the case's own premises still hold: that
  the expected URN resolves, and that any quoted text is really there. A case whose
  premises have broken is reported as **stale**, never as a failure.

  That distinction is the difference between a useful harness and a misleading one. After
  a re-bake, a changed corpus would otherwise make every affected case look like a
  retrieval regression, and the honest signal — *your gold set is out of date* — would be
  buried in a number that went down.
  """

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Embed.Serving
  alias Pramana.Evals.Case
  alias Pramana.Evals.Score
  alias Pramana.Guard
  alias Pramana.Repo
  alias Pramana.Retrieval.Hybrid
  alias Pramana.URN

  @default_dir "evals/gold"

  @doc """
  Loads every gold case from a directory of JSONL files.

  JSONL so a case is one line: a malformed case fails on its own line rather than taking
  the file with it, and a diff shows exactly which case changed.
  """
  @spec load(String.t()) :: {:ok, [Case.t()]} | {:error, term()}
  def load(dir \\ @default_dir) do
    files = dir |> Path.join("*.jsonl") |> Path.wildcard() |> Enum.sort()

    case files do
      [] -> {:error, {:no_gold_set, dir}}
      files -> {:ok, Enum.flat_map(files, &load_file/1)}
    end
  end

  defp load_file(path) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Stream.reject(fn {line, _} -> String.trim(line) in ["", "//"] end)
    |> Enum.map(fn {line, n} -> Case.parse!(line, path, n) end)
  end

  @doc """
  Runs every case and returns a scorecard.

  Options:

    * `:only` — run one case type
    * `:tradition` — run only cases from one tradition
    * `:on_progress` — `fn done, total, elapsed_ms -> :ok end`, called after each case.
      A run of the full set takes hours and printed NOTHING until it finished, which made
      "how far along is it" unanswerable and made a run that had died look exactly like
      one still working. The domain does no IO of its own; the caller decides what to
      show.
    * `:serving` — a preloaded embedding serving, so a caller embedding many queries
      pays the model load once
  """
  @spec run([Case.t()], keyword()) :: map()
  def run(cases, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    cases =
      case opts[:only] do
        nil -> cases
        type -> Enum.filter(cases, &(&1.type == type))
      end

    # A tradition filter, so an experiment aimed at one canon does not have to score all
    # 1,400 cases to see its effect. It NARROWS the set, so any figure from such a run is
    # about that canon and nothing else — the scorecard still prints the case count, which
    # is what stops a narrowed run being read as a full one.
    cases =
      case opts[:tradition] do
        nil -> cases
        tradition -> Enum.filter(cases, &(&1.tradition == tradition))
      end

    total = length(cases)
    on_progress = Keyword.get(opts, :on_progress, fn _done, _total, _elapsed_ms -> :ok end)

    results =
      cases
      |> Enum.with_index(1)
      |> Enum.map(fn {kase, i} ->
        result = score_case(kase, opts)
        on_progress.(i, total, System.monotonic_time(:millisecond) - started)
        result
      end)

    Score.summarize(results, System.monotonic_time(:millisecond) - started)
  end

  # Every case is first asked whether it is still a valid question, and only then whether
  # the system answers it.
  defp score_case(%Case{} = kase, opts) do
    case stale_reason(kase) do
      nil -> %{case: kase, outcome: evaluate(kase, opts)}
      reason -> %{case: kase, outcome: {:stale, reason}}
    end
  end

  # A case's premises: the URNs it expects must exist, and quoted text must really be
  # there. Checked against the corpus, not against the harness's memory of it.
  defp stale_reason(%Case{type: :absence}), do: nil

  # A topical case is stale when its locator term has left the corpus entirely — then it
  # is not a question this bake can be asked, and scoring it as a miss would blame the
  # retriever for an ingest change.
  defp stale_reason(%Case{type: :topical} = kase) do
    if Enum.any?(kase.expect_contains, &term_present?/1),
      do: nil,
      else: {:no_locator_term_in_corpus, kase.expect_contains}
  end

  defp stale_reason(%Case{expect_urns: []} = kase) do
    if kase.type in [:quote_reject], do: nil, else: {:no_expected_urns, kase.id}
  end

  # A case is stale when NONE of its expected anchors is answerable — not when one of
  # them is. Formulaic passages expect every byte-identical location, sometimes dozens of
  # them, and requiring all to resolve would let a single re-segmented anchor mark a
  # perfectly good question stale.
  defp stale_reason(%Case{} = kase) do
    case Enum.find_value(kase.expect_urns, &answerable(kase, &1)) do
      :ok -> nil
      nil -> {:no_expected_urn_answerable, kase.expect_urns |> Enum.take(3)}
    end
  end

  defp answerable(kase, urn) do
    with {:ok, span} <- Corpus.resolve(urn),
         nil <- quote_present(kase, span, urn) do
      :ok
    else
      _ -> nil
    end
  end

  defp term_present?(term) do
    Repo.exists?(from s in Segment, where: like(s.content, ^"%#{term}%"))
  end

  defp quote_present(%Case{quote: nil}, _span, _urn), do: nil

  defp quote_present(%Case{quote: quoted}, span, urn) do
    if String.contains?(span.content, String.trim(quoted)),
      do: nil,
      else: {:quote_no_longer_present, urn}
  end

  # ---- the case types ----

  # Does a natural-language query retrieve the passage the scholarship points at?
  defp evaluate(%Case{type: :retrieval} = kase, opts) do
    hits = search(kase, opts)
    rank = rank_of(hits, kase.expect_urns)

    cond do
      rank == nil -> {:miss, %{retrieved: Enum.take(hits, 3)}}
      rank <= kase.k -> {:hit, %{rank: rank, matched_via: matched_via(hits, rank)}}
      true -> {:miss, %{rank: rank, beyond_k: kase.k}}
    end
  end

  # Did a topical question return a passage that genuinely discusses the topic?
  #
  # This is the question users actually ask, and it is scored differently on purpose. A
  # derived `retrieval` case asks "did you find the one anchor whose translation I
  # quoted"; this asks "did you find something that talks about this". The second is
  # easier — which is the point. Measuring the harder task and calling the result a
  # user-experience number is how a benchmark misleads.
  defp evaluate(%Case{type: :topical} = kase, opts) do
    hits = search(kase, opts)

    rank =
      hits
      |> Enum.with_index(1)
      |> Enum.find_value(fn {hit, i} -> if mentions?(hit, kase.expect_contains), do: i end)

    cond do
      rank == nil -> {:miss, %{retrieved: hits |> Enum.take(3) |> Enum.map(& &1.urn)}}
      rank <= kase.k -> {:hit, %{rank: rank, matched_via: matched_via(hits, rank)}}
      true -> {:miss, %{rank: rank, beyond_k: kase.k}}
    end
  end

  # Does the guard confirm a quotation that really is there?
  defp evaluate(%Case{type: :quote_verify} = kase, _opts) do
    urn = hd(kase.expect_urns)

    case Guard.check(urn, kase.quote) do
      %{verdict: :ok} -> {:hit, %{urn: urn}}
      %{verdict: verdict} -> {:miss, %{verdict: verdict}}
    end
  end

  # Does the guard REFUSE a quotation that is not there, or a URN that does not exist?
  # A harness that only tests the positive case measures nothing: a guard that returns
  # `:ok` unconditionally would pass every quote_verify case.
  defp evaluate(%Case{type: :quote_reject} = kase, _opts) do
    urn = kase.urn || hd(kase.expect_urns)

    case Guard.check(urn, kase.quote) do
      %{verdict: :ok} -> {:miss, %{wrongly_accepted: urn}}
      %{verdict: verdict} -> {:hit, %{verdict: verdict}}
    end
  end

  # Is the work labelled with the origin and role the catalogue gives it?
  defp evaluate(%Case{type: :provenance} = kase, _opts) do
    urn = hd(kase.expect_urns)

    with {:ok, span} <- Corpus.resolve(urn) do
      actual = Map.take(span.provenance, Map.keys(kase.expect_provenance))

      if actual == kase.expect_provenance,
        do: {:hit, %{}},
        else: {:miss, %{expected: kase.expect_provenance, actual: actual}}
    end
  end

  # Does the system say it does not hold something, rather than returning a near-miss?
  # This is the case type that most projects have no answer for at all.
  defp evaluate(%Case{type: :absence} = kase, opts) do
    hits = search(kase, opts)

    forbidden =
      Enum.filter(hits, fn hit ->
        Enum.any?(kase.forbid_works, &String.starts_with?(hit.urn, &1))
      end)

    cond do
      forbidden != [] -> {:miss, %{returned_forbidden: Enum.map(forbidden, & &1.urn)}}
      kase.expect_empty and hits != [] -> {:miss, %{expected_empty: length(hits)}}
      true -> {:hit, %{returned: length(hits)}}
    end
  end

  defp mentions?(hit, terms) do
    text = hit_text(hit)
    Enum.any?(terms, &String.contains?(text, &1))
  end

  # A hybrid hit carries its span; a chunk hit carries content directly.
  defp hit_text(hit) do
    cond do
      is_binary(Map.get(hit, :content)) -> hit.content
      is_map(Map.get(hit, :span)) and is_binary(hit.span[:content]) -> hit.span.content
      true -> ""
    end
  end

  defp search(%Case{} = kase, opts) do
    search_opts =
      kase.search_opts
      |> Keyword.put(:limit, max(kase.k * 2, 20))
      # Explicit, even though `Hybrid` now defaults to the running serving: a harness
      # that publishes a number must not depend on an implicit default for whether half
      # the retrieval stack ran.
      |> Keyword.put(:serving, opts[:serving] || Serving.name())
      # Nothing in `evaluate/2` reads `:coverage`, and computing it counts 560,238 chunks
      # and probes each for a vector. Measured end to end on `--only topical`, 49 cases,
      # identical scores both ways: **6m43s -> 5m22s, ~1.65 s saved per case**, which is
      # ~13.7 minutes over the ~500 searching cases of a full run. It is database time, so
      # it appears in no CPU profile and in nobody's intuition about why a run is slow.
      #
      # The number matters to a CALLER, who might otherwise read an empty result as a
      # small canon; it cannot matter to a harness that scores URNs.
      |> Keyword.put(:coverage, false)
      # An experiment override wins over the case's own options, so a whole run can be
      # scored under one configuration.
      |> Keyword.merge(opts[:search_override] || [])

    case Hybrid.search(kase.query, search_opts) do
      {:ok, %{results: results}} -> results
      {:error, _} -> []
    end
  end

  # A chunk URN is a RANGE, and the expected anchor is usually a single line inside it, so
  # a string equality test would score a correct retrieval as a miss. Containment is what
  # the question actually asks: did the system return the passage this citation is in?
  defp rank_of(hits, expected) do
    hits
    |> Enum.with_index(1)
    |> Enum.find_value(fn {hit, i} ->
      if Enum.any?(expected, &covers?(hit.urn, &1)), do: i
    end)
  end

  @doc """
  True when `hit_urn` addresses a span that contains `expected_urn`.

  Exposed because it is the one piece of scoring logic with a judgement call in it, and a
  reader checking a published number is entitled to see exactly what counted as a hit.
  """
  @spec covers?(String.t(), String.t()) :: boolean()
  def covers?(hit_urn, expected_urn) do
    with {:ok, hit} <- URN.parse(hit_urn),
         {:ok, want} <- URN.parse(expected_urn) do
      hit.source == want.source and hit.witness == want.witness and
        hit.work == want.work and locator_covers?(hit, want)
    else
      _ -> false
    end
  end

  defp locator_covers?(%{locator: l, locator_end: nil}, %{locator: w}), do: l == w

  defp locator_covers?(%{locator: from, locator_end: to}, %{locator: w}) do
    from <= w and w <= to
  end

  defp matched_via(hits, rank) do
    hits |> Enum.at(rank - 1) |> Map.get(:matched_via, [])
  end
end
