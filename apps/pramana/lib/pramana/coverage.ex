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
  """

  import Ecto.Query

  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @taisho_volumes 1..85
  @japanese_delta 56..84

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
      note: note(missing)
    }
  end

  @doc """
  A one-line warning for callers that must not mistake absence for silence, or `nil`.

  Returned as its own field rather than folded into prose so a tool response can carry
  it verbatim and a model cannot skim past it.
  """
  @spec caveat() :: String.t() | nil
  def caveat do
    case taisho() do
      %{japanese_delta_missing: true} -> japanese_caveat()
      _ -> nil
    end
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
    "Taishō volumes 56–84 are NOT loaded. Those volumes are the Japanese-composed " <>
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
