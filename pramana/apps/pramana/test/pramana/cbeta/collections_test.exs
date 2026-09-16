defmodule Pramana.Cbeta.CollectionsTest do
  @moduledoc """
  The volume-token width is the only part of this table a citation is built from, so it
  is the only part that can silently produce a wrong answer. The rest — names, counts —
  is descriptive; a wrong width yields `A91n1057_p0311b01`, which looks exactly like a
  citation and resolves nowhere.

  So it is checked against `sources.lock.json`, the record of what was actually acquired.
  Both must agree, because a bake reads its files by one and a reader cites them by the
  other, and nothing else connects the two.
  """
  use ExUnit.Case, async: true

  alias Pramana.Cbeta.Collections

  # T/T09/T09n0262.xml -> {"T", 9, "T09"}
  @path ~r{^(?<canon>[A-Z]+)/\k<canon>(?<vol>\d+)/}

  defp acquired_volume_tokens do
    "sources.lock.json"
    |> Path.expand(Path.join(__DIR__, "../../../../.."))
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("sources")
    |> Enum.find(&(&1["id"] == "cbeta"))
    |> Map.fetch!("files")
    |> Enum.flat_map(fn %{"path" => path} ->
      case Regex.named_captures(@path, path) do
        nil -> []
        %{"canon" => canon, "vol" => vol} -> [{canon, String.to_integer(vol), canon <> vol}]
      end
    end)
    |> Enum.uniq()
  end

  describe "volume_token/2" do
    # The ground truth is the directory CBETA published the file in — the same string its
    # website puts on the line. If the two ever disagree, this fails on the real corpus
    # rather than on a fixture, and it fails in CI because the lockfile is committed.
    test "reproduces every volume token in the lockfile" do
      tokens = acquired_volume_tokens()

      assert length(tokens) > 200, "expected the acquired lockfile, got #{length(tokens)} volumes"

      for {canon, volume, expected} <- tokens do
        assert Collections.volume_token(canon, volume) == expected
      end
    end

    test "covers every collection the corpus actually holds" do
      held = tokens_by_canon()
      known = MapSet.new(Collections.volume_token_known())

      for canon <- held do
        assert MapSet.member?(known, canon),
               "#{canon} is acquired but has no verified volume width, so its lineheads " <>
                 "will be nil — add it after checking a real CBETA page"
      end
    end

    # We hold none of these and have no page to check a guess against. `N` used to be one
    # of them and is now held — which is the whole point of naming unheld collections here
    # rather than a fixed list: this test tracks the boundary, and moving a collection
    # across it is a deliberate edit with a checked page behind it.
    test "is nil for a collection whose width has not been checked" do
      # `Y` is 印順法師佛學著作集 and `TX` 太虛大師全書 — 20th-century authors' collected
      # works, which PLAN B2 puts deliberately last because loading a living author's essay
      # without a `text_role` that says so files it beside a sūtra.
      assert Collections.volume_token("ZW", 12) == nil
      assert Collections.volume_token("Y", 3) == nil
      assert Collections.volume_token("TX", 1) == nil
    end

    test "is nil for anything that is not one volume" do
      # "130-133" is what a volume-spanning work records: a description, not a coordinate.
      assert Collections.volume_token("L", "130-133") == nil
      assert Collections.volume_token("T", nil) == nil
      assert Collections.volume_token("T", "") == nil
      assert Collections.volume_token("T", -1) == nil
    end

    # VOLUME ZERO IS REAL. This test asserted `volume_token("T", 0) == nil`, on the
    # assumption that a volume is at least 1 — and three collections acquired on 2026-08-28
    # number their first volume zero: `I00`, `GA000`, `GB000`. The assumption was never
    # checked against an edition, which is how the two-digit width got in as well.
    test "accepts volume zero, which three collections use" do
      assert Collections.volume_token("I", 0) == "I00"
      assert Collections.volume_token("GA", 0) == "GA000"
      assert Collections.volume_token("GB", 0) == "GB000"
    end

    test "accepts the string form provenance carries" do
      assert Collections.volume_token("T", "9") == "T09"
      assert Collections.volume_token("A", "91") == "A091"
    end
  end

  defp tokens_by_canon, do: acquired_volume_tokens() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
end
