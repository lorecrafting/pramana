defmodule Docs.SyncTest do
  @moduledoc """
  The mechanism that stops a documented figure going stale.

  `CLAUDE.md` says never write down a number the code computes, and a file whose job is
  *what is true now* is made of numbers, so the rule kept losing. Five figures drifted in
  one week and every one was caught by a person reading carefully — `docs/PLAN.md` said 17
  MCP tools while `docs/STATUS.md` said 18 and the directory settled it.

  Blocks are generated and the gate fails when regenerating would change one. These tests
  are about the two ways that promise breaks: a block that silently does not update, and a
  block that claims a figure nothing produces.
  """
  use ExUnit.Case, async: true

  alias Pramana.Docs.Sync

  @blocks %{"corpus" => [{"texts", "17,281"}, {"segments", "12,586,964"}]}

  defp doc(inner),
    do: "before\n\n<!-- figures:corpus -->\n#{inner}<!-- /figures -->\n\nafter\n"

  describe "rewrite/2" do
    test "fills an empty block and reports it changed" do
      assert {:ok, updated, ["corpus"]} = Sync.rewrite(doc(""), @blocks)

      assert updated =~ "| texts | **17,281** |"
      assert updated =~ "| segments | **12,586,964** |"
    end

    test "leaves prose outside the markers exactly as it was" do
      {:ok, updated, _} = Sync.rewrite(doc(""), @blocks)

      assert String.starts_with?(updated, "before\n\n")
      assert String.ends_with?(updated, "\n\nafter\n")
    end

    # The whole point: a second run must be a no-op, or the gate would fail forever on a
    # document nobody had edited.
    test "is idempotent, and the second pass reports no change" do
      {:ok, once, ["corpus"]} = Sync.rewrite(doc(""), @blocks)

      assert {:ok, ^once, []} = Sync.rewrite(once, @blocks)
    end

    test "reports a stale figure as changed" do
      {:ok, current, _} = Sync.rewrite(doc(""), @blocks)
      stale = String.replace(current, "17,281", "99,999")

      assert {:ok, fixed, ["corpus"]} = Sync.rewrite(stale, @blocks)
      assert fixed == current
    end

    # A block nothing generates is a promise the file makes and the code does not keep,
    # which is worse than no block: it renders as an empty table and reads as "none".
    test "refuses a block name nothing generates" do
      unknown = doc("") |> String.replace("figures:corpus", "figures:nonesuch")

      assert {:error, {:unknown_block, "nonesuch"}} = Sync.rewrite(unknown, @blocks)
    end

    # The mechanism has to survive being explained. Unanchored, the marker quoted inside
    # `docs/CHECKS.md`'s own description of it was read as a real block, and the gate
    # failed with `{:unknown_block, "key"}` on a sentence.
    test "ignores the marker syntax quoted inside a sentence" do
      prose = "Corpus counts live in <!-- figures:key --> blocks, and are generated.\n"

      assert {:ok, ^prose, []} = Sync.rewrite(prose, @blocks)
    end

    test "refuses an unterminated block rather than swallowing the rest of the file" do
      unterminated = "a\n<!-- figures:corpus -->\nno closing marker\n"

      assert {:error, {:unterminated_block, "corpus"}} = Sync.rewrite(unterminated, @blocks)
    end

    test "a document with no markers is returned untouched" do
      plain = "nothing generated here\n"

      assert {:ok, ^plain, []} = Sync.rewrite(plain, @blocks)
    end

    test "handles several blocks in one document independently" do
      two = doc("") <> "\n<!-- figures:other -->\n<!-- /figures -->\n"
      blocks = Map.put(@blocks, "other", [{"tools", "18"}])

      assert {:ok, updated, changed} = Sync.rewrite(two, blocks)
      assert Enum.sort(changed) == ["corpus", "other"]
      assert updated =~ "| tools | **18** |"
    end
  end

  describe "documents/1" do
    test "finds only the documents that actually carry a block" do
      root = Path.expand("../../../..", __DIR__)
      docs = Sync.documents(root)

      assert Enum.all?(docs, &(File.read!(&1) =~ "<!-- figures:"))
      assert Enum.any?(docs, &String.ends_with?(&1, "STATUS.md"))
    end
  end
end
