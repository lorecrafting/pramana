defmodule Pramana.Elapsed do
  @moduledoc """
  Formats how long something took, for tasks that report it.

  ## Why this exists

  None of the gate tasks used to time themselves, and the cost was not theoretical:
  `docs/CHECKS.md` carried **two wrong runtimes in one day**. One was 45 minutes,
  extrapolated from a case-count ratio and never measured. The other was 8h20m, read off
  a wall clock across a laptop that had been asleep for part of the run. Both were
  published as measurements.

  A task that prints its own elapsed time makes both mistakes impossible, and turns every
  gate run into a profile — so a regression shows up as a number that moved rather than as
  something rediscovered months later.

  Rates matter more than totals here. "45 minutes" ages the moment the corpus grows;
  "212 texts/s" stays comparable across a corpus that doubled, which this one did.
  """

  @doc """
  A duration in milliseconds, rendered for a human.

      iex> Pramana.Elapsed.human(950)
      "0.9s"

      iex> Pramana.Elapsed.human(75_000)
      "1m15s"

      iex> Pramana.Elapsed.human(3_930_000)
      "1h05m"
  """
  @spec human(non_neg_integer()) :: String.t()
  def human(ms) when ms < 10_000, do: "#{Float.round(ms / 1000, 1)}s"

  def human(ms) when ms < 60_000, do: "#{div(ms, 1000)}s"

  def human(ms) when ms < 3_600_000 do
    "#{div(ms, 60_000)}m#{pad(div(rem(ms, 60_000), 1000))}s"
  end

  def human(ms), do: "#{div(ms, 3_600_000)}h#{pad(div(rem(ms, 3_600_000), 60_000))}m"

  @doc """
  Items per second, as a string.

  The number that survives a corpus doubling — a total does not.

      iex> Pramana.Elapsed.rate(1000, 4000)
      "250.0"
  """
  @spec rate(non_neg_integer(), non_neg_integer()) :: String.t()
  def rate(_count, 0), do: "—"

  def rate(count, ms), do: :erlang.float_to_binary(count * 1000 / ms, decimals: 1)

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
