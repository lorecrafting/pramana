defmodule PramanaNative do
  @moduledoc """
  Rust NIFs for CPU-bound work with no viable BEAM implementation.

  See `docs/ELIXIR.md`, exception #1. Keep this module small: every addition should be
  justified by a measurement, not a hunch. Orchestration, retries, and domain rules
  belong in Elixir.

  ## Why CJK segmentation lives here

  Classical Chinese has no whitespace. `String.split/1` on a passage is always a bug,
  and lexical search under-recalls badly without dictionary-based segmentation. It is
  needed at both bake time and query time, so it must be in-process.
  """

  use Rustler, otp_app: :pramana_native, crate: "pramana_native"

  @doc """
  Segments Chinese text into words.

      iex> PramanaNative.segment("如是我聞")
      ["如是", "我", "聞"]
  """
  @spec segment(String.t()) :: [String.t()]
  def segment(_text), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Segments in search mode, also emitting shorter sub-words.

  Higher recall, lower precision — for building a lexical index, not for display.
  """
  @spec segment_for_search(String.t()) :: [String.t()]
  def segment_for_search(_text), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Round-trips a string through Rust. Proves the FFI boundary preserves bytes."
  @spec echo(String.t()) :: String.t()
  def echo(_text), do: :erlang.nif_error(:nif_not_loaded)
end
