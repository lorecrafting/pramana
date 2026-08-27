defmodule Pramana.Coverage do
  @moduledoc """
  What the corpus does **not** contain, stated explicitly.

  An empty result has two completely different meanings — *"the canon does not say
  this"* and *"that part of the canon is not loaded"* — and they are indistinguishable
  from the result alone. Everywhere else in this project that ambiguity is resolved by
  reporting coverage; this module does it for the one gap that matters most.

  ## The Taishō 56–84 gap

  CBETA covers Taishō volumes 1–55 and 85. Volumes **56–84 are exactly the
  Japanese-composed sectarian corpus** — Shingon, Tendai, Nichiren, Zen — which CBETA
  deliberately excludes and which only SAT publishes. Verified against the bake: the 56
  volumes present are precisely 1–55 and 85, and the 29 missing are precisely 56–84.

  So a reader who searches for a Japanese sectarian position today gets nothing, and
  nothing is a *lie by omission* unless the gap is stated. That is the exact inverse of
  the failure this project was built to prevent: instead of presenting a Japanese
  commentary as an Indian sūtra, it would present the Japanese tradition as silent.

  `Pramana.URN.Taisho.provenance_for_volume/1` already implements the 56–84 rule, so
  when SAT is acquired the material lands with correct provenance automatically. The
  blocker is acquisition, not classification — see `docs/SOURCES.md`.

  ## The CBETA collections gap

  The same failure, one level up. CBETA publishes **26 collections** and this holds two:
  the Taishō and the 卍續藏. While the Taishō was the only one loaded, "the Chinese canon"
  and "what we have" were close enough to the same sentence that nobody wrote the
  difference down. They are not the same sentence — 1,304 works across 24 further
  collections are not here, and a reader searching for a 嘉興藏 text gets an empty result
  with nothing to distinguish *not in the canon* from *not in this bake*.

  See `cbeta/0` and `Pramana.Cbeta.Collections`.
  """

  import Ecto.Query

  alias Pramana.Cbeta.Collections
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.Taisho.Divisions

  @taisho_volumes 1..85
  @japanese_delta 56..84

  # The Tōhoku catalogue numbers the Degé Kangyur 1–1108 and the Degé Tengyur 1109–4569.
  # The division is not editorial: the Kangyur is what the tradition holds to be the
  # Buddha's word, the Tengyur is the Indian commentarial literature on it, and a corpus
  # holding one and not the other is silent about a whole genre rather than about a text.
  @kangyur_toh 1..1108
  @tengyur_toh 1109..4569

  @doc """
  Which Taishō volumes are in the bake and which are missing.

  Computed from the data rather than asserted, so it stays true when SAT lands.
  """
  @spec taisho() :: map()
  def taisho do
    present =
      Repo.all(from t in Text, where: t.witness_id == "T", select: t.volume, distinct: true)
      |> Enum.flat_map(&parse_volume/1)
      |> MapSet.new()

    missing = Enum.reject(@taisho_volumes, &MapSet.member?(present, &1))

    %{
      present: MapSet.size(present),
      expected: Enum.count(@taisho_volumes),
      # A bare list here inspects as a CHARLIST — 56..84 are all printable ASCII, so
      # `missing` renders as ~c"89:;<..." in any IO.inspect and reads as corruption.
      # The list is still what JSON needs; `missing_ranges` is what a human or a model
      # should be shown.
      missing: missing,
      missing_ranges: format_ranges(missing),
      japanese_delta_missing: japanese_delta_missing?(missing),
      # What is missing stated in WORK NUMBERS, not only volumes. A reader asking "do you
      # have Nichiren's writings" is asking about texts, and "volumes 56–84" requires them
      # to already know which volumes those are. The division table settles this without
      # any new acquisition: it records which Taishō number ranges fall in the Japanese
      # sections and how each is classified.
      missing_divisions: missing_divisions(missing),
      note: note(missing)
    }
  end

  # The divisions whose entire work-number range sits in volumes we do not hold.
  #
  # This is the honest half of what a catalogue would give us. We can say *which
  # divisions* are absent, their number ranges, and how the edition classifies them —
  # because the Taishō's own division table is data we already have. What we cannot say
  # is which individual works exist, or their titles and authors: that needs a catalogue
  # of volumes 56–84, and no openly-licensed machine-readable one exists (checked at the
  # #20 gate — CBETA's own catalogue stops at 55, and SAT publishes no bulk metadata).
  #
  # Stating the range without the works is not a half-measure; it is the difference
  # between "something is missing" and "T2185–T2731, the Japanese sub-commentaries, are
  # missing", which is a question a reader can act on.
  defp missing_divisions(missing_volumes) do
    volumes = MapSet.new(missing_volumes)

    Divisions.all()
    |> Enum.filter(fn division ->
      division.volumes
      |> volume_numbers()
      |> case do
        [] -> false
        vols -> Enum.all?(vols, &MapSet.member?(volumes, &1))
      end
    end)
    |> Enum.map(fn division ->
      %{
        division: division.name,
        division_en: division.name_en,
        volumes: division.volumes,
        work_numbers: "T#{pad(division.first)}–T#{pad(division.last)}",
        work_number_count: division.last - division.first + 1,
        composition_origin: division.composition_origin,
        text_role: division.text_role
      }
    end)
  end

  # "56-83" or "84" -> the integers it covers.
  defp volume_numbers(spec) when is_binary(spec) do
    case String.split(spec, "-") do
      [one] ->
        one |> Integer.parse() |> then(fn {n, _} -> [n] end)

      [from, to] ->
        with {a, _} <- Integer.parse(from), {b, _} <- Integer.parse(to), do: Enum.to_list(a..b)
    end
  rescue
    _ -> []
  end

  defp volume_numbers(_), do: []

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 4, "0")

  @doc """
  Which CBETA collections are in the bake, and which are not.

  Computed from the witnesses actually loaded against the pinned catalogue, so it stops
  saying this as collections land. A collection with no name here has not been acquired:
  each CBETA file states its own collection in `<sourceDesc>`, and rather than guess what
  a two-letter code expands to, the name arrives with the files. See
  `Pramana.Cbeta.Collections`.
  """
  @spec cbeta() :: map()
  def cbeta do
    held =
      Repo.all(
        from t in Text, where: t.source_id == "cbeta", select: t.witness_id, distinct: true
      )
      |> MapSet.new()

    {present, missing} = Enum.split_with(Collections.all(), &MapSet.member?(held, &1.id))

    %{
      collections_held: length(present),
      collections_published: length(Collections.all()),
      held: Enum.map(present, & &1.id),
      missing: Enum.map(missing, &Map.take(&1, [:id, :works, :name])),
      works_held: Enum.sum(Enum.map(present, & &1.works)),
      works_published: Collections.total_works(),
      catalogue_pin: Collections.pin(),
      note: cbeta_note(present, missing)
    }
  end

  defp cbeta_note(_present, []), do: "Every CBETA collection is loaded."

  defp cbeta_note(present, missing) do
    absent_works = Enum.sum(Enum.map(missing, & &1.works))

    top =
      missing
      |> Enum.take(5)
      |> Enum.map_join(", ", fn c -> "#{c.id} (#{c.works})" end)

    "CBETA publishes #{length(present) + length(missing)} collections and this bake holds " <>
      "#{length(present)}: #{Enum.map_join(present, ", ", & &1.id)}. " <>
      "#{length(missing)} collections and #{absent_works} works are NOT loaded — largest first: " <>
      "#{top}. An absence of results from those collections means they are not in this " <>
      "bake; it does NOT mean the canon is silent. Acquire one with " <>
      "`mix pramana.acquire_all --source cbeta --canon <ID>`."
  end

  @doc """
  A one-line warning for callers that must not mistake absence for silence, or `nil`.

  Returned as its own field rather than folded into prose so a tool response can carry
  it verbatim and a model cannot skim past it.
  """
  @spec caveat() :: String.t() | nil
  def caveat do
    [taisho_caveat(), cbeta_caveat(), tibetan_caveat()]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      caveats -> Enum.join(caveats, " ")
    end
  end

  defp taisho_caveat do
    case taisho() do
      %{japanese_delta_missing: true} -> japanese_caveat()
      _ -> nil
    end
  end

  defp cbeta_caveat do
    case cbeta() do
      %{missing: [], collections_held: n} when n > 0 -> nil
      %{collections_held: 0} -> nil
      %{note: note} -> note
    end
  end

  @doc """
  Which part of the Tibetan canon is in the bake.

  The Tōhoku numbers say which: 1–1108 is the Kangyur, 1109–4569 the Tengyur. Holding
  one and not the other is the same failure the Taishō 56–84 gap is — an absence that
  reads as the tradition being silent — except that here the missing half is the entire
  Indian commentarial literature. A caller asking what Vasubandhu says about a sūtra gets
  nothing, and nothing is not an answer to that question.

  Computed from the works actually loaded, so it stops saying this when the Tengyur lands.
  """
  @spec tibetan() :: map()
  def tibetan do
    # Both halves of the edition, because the question is about the canon rather than
    # about a source id: the Kangyur and Tengyur are published separately and are one
    # print.
    numbers =
      Repo.all(
        from t in Text,
          where:
            t.source_id in ["derge", "derge-tengyur"] and
              fragment("? ~ '^toh[0-9]+'", t.work_id),
          select: fragment("(regexp_replace(?, '^toh([0-9]+).*$', '\\1'))::int", t.work_id)
      )

    kangyur = Enum.count(numbers, &(&1 in @kangyur_toh))
    tengyur = Enum.count(numbers, &(&1 in @tengyur_toh))

    %{
      kangyur_works: kangyur,
      tengyur_works: tengyur,
      tengyur_missing: kangyur > 0 and tengyur == 0,
      note: tibetan_note(kangyur, tengyur)
    }
  end

  defp tibetan_note(0, _tengyur), do: "No Tibetan material is loaded."

  defp tibetan_note(_kangyur, 0), do: tengyur_caveat()

  defp tibetan_note(kangyur, tengyur),
    do: "#{kangyur} Kangyur and #{tengyur} Tengyur work(s) are loaded."

  defp tibetan_caveat do
    case tibetan() do
      %{tengyur_missing: true} -> tengyur_caveat()
      _ -> nil
    end
  end

  defp tengyur_caveat do
    "The Degé Tengyur (Tōhoku 1109–4569) is NOT loaded — only the Kangyur. The Tengyur " <>
      "is the Indian commentarial literature, so an absence of Tibetan commentary means " <>
      "that half of the canon is not in this bake; it does NOT mean the commentators " <>
      "are silent."
  end

  defp japanese_delta_missing?(missing) do
    Enum.any?(@japanese_delta, &(&1 in missing))
  end

  defp note([]), do: "All 85 Taishō volumes are loaded."

  defp note(missing) do
    if japanese_delta_missing?(missing) do
      japanese_caveat()
    else
      "Missing Taishō volumes: #{format_ranges(missing)}."
    end
  end

  defp japanese_caveat do
    "Taishō volumes 56–84 (work numbers T2185–T2731, 547 of them) are NOT loaded. " <>
      "Those volumes are the Japanese-composed " <>
      "sectarian corpus (Shingon, Tendai, Nichiren, Zen); CBETA excludes them and only " <>
      "SAT publishes them. An absence of Japanese-composed results therefore means the " <>
      "material is not in this bake — it does NOT mean the tradition is silent."
  end

  # 56–84 reads better than 29 comma-separated integers, and the gap is contiguous.
  defp format_ranges(volumes) do
    volumes
    |> Enum.sort()
    |> Enum.chunk_while(
      [],
      fn v, acc ->
        case acc do
          [prev | _] when v == prev + 1 -> {:cont, [v | acc]}
          [] -> {:cont, [v]}
          _ -> {:cont, Enum.reverse(acc), [v]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.map_join(", ", fn
      [single] -> Integer.to_string(single)
      run -> "#{List.first(run)}–#{List.last(run)}"
    end)
  end

  # Volumes are stored as strings; anything non-numeric is a data problem elsewhere and
  # must not crash a coverage report.
  defp parse_volume(nil), do: []

  defp parse_volume(volume) do
    case Integer.parse(volume) do
      {n, ""} -> [n]
      _ -> []
    end
  end
end
