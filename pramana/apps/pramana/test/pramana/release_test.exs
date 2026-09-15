defmodule Pramana.ReleaseTest do
  @moduledoc """
  What answered, as distinct from what was baked.

  **The defect this fixes has already happened.** 27,751 renderings and 27,751 vectors were
  imported under an unchanged `bake_id`, while `PramanaWeb.MCP.Reply` stamped that id on
  every response of nineteen tools and promised it was enough to reproduce an answer. These
  tests pin the property that makes `release_id` worth having: **it moves when retrieval
  moves, and `bake_id` does not.**
  """
  use Pramana.DataCase, async: true

  alias Pramana.Release
  alias Pramana.Translations

  defp rendering!(id) do
    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: "pramana:sc.ms:mn1@#{id}",
          work_id: "mn1",
          lang: "en",
          translator_id: "sujato",
          tier: "t0",
          method: "human",
          text: "So I have heard, rendering number #{id}.",
          redistributable: true,
          license_class: "cc0"
        }
      ])
  end

  describe "stamp/0" do
    test "is idempotent while nothing changes" do
      {:ok, first} = Release.stamp()
      {:ok, second} = Release.stamp()

      # A release list where most rows are identical is a list nobody reads.
      assert first.id == second.id
      assert first.release_id == second.release_id
    end

    test "the id MOVES when the English layer does — the whole point" do
      {:ok, before} = Release.stamp()
      rendering!("1.1")
      {:ok, after_import} = Release.stamp()

      refute before.release_id == after_import.release_id,
             """
             A rendering was imported and `release_id` did not move, which is exactly the
             `bake_id` defect this module exists to fix: two holders of one id answering
             the same query differently.
             """

      refute before.translation_set_id == after_import.translation_set_id
    end

    test "the SOURCE id does not move when only the English layer does" do
      # The division of labour: a citation stays reproducible from `source_bake_id` alone,
      # and that claim never depended on the index. Importing English must not disturb it.
      {:ok, before} = Release.stamp()
      rendering!("2.1")
      {:ok, after_import} = Release.stamp()

      assert before.source_bake_id == after_import.source_bake_id
      assert before.vector_set_id == after_import.vector_set_id
    end
  end

  describe "drift/0" do
    test "reports `:unstamped` before anything is recorded" do
      assert Release.drift() == :unstamped
    end

    test "reports `:current` immediately after a stamp" do
      {:ok, _} = Release.stamp()
      assert Release.drift() == :current
    end

    test "names what moved, so a stale stamp cannot be silent" do
      # A RECORDED id can go stale where a computed one cannot, which would reproduce the
      # original defect in a new place. Drift is the check that keeps it visible.
      {:ok, _} = Release.stamp()
      rendering!("3.1")

      drift = Release.drift()

      assert is_map(drift)
      assert %{translations_count: %{stamped: stamped, live: live}} = drift
      assert live == stamped + 1
    end
  end

  describe "ids/0" do
    test "computes what the current corpus would stamp" do
      {:ok, stamped} = Release.stamp()
      ids = Release.ids()

      # One definition of what the ids are made of. It was briefly two — a private digest
      # for stamping and a public one for reporting — and that is how a stamped id stops
      # matching the id a check computes. Rule 41.
      assert ids.release_id == stamped.release_id
      assert ids.translation_set_id == stamped.translation_set_id
      assert ids.vector_set_id == stamped.vector_set_id
    end
  end
end
