defmodule Pramana.CharCountTest do
  @moduledoc """
  `texts.char_count`, and the two ways a stored derived value goes wrong.

  It exists because summing `length(body)` over the corpus detoasts every text — 9.8 s, paid
  by the reader's `/inventory` page on every load. A stored count is only worth having if it
  cannot drift from the body and if it counts the right unit, so both are pinned here.
  """
  use Pramana.DataCase, async: true

  import Ecto.Query

  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

  defp load!(work_id, line) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title>
    <author>唐 某撰</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>#{line}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: %{})

    Repo.one!(from(t in Text, where: t.work_id == ^work_id))
  end

  test "counts CHARACTERS, not bytes" do
    # A Chinese character is three bytes in UTF-8. `byte_size/1` would report roughly three
    # times as many and be wrong in a way nobody would notice, because both numbers look
    # like plausible corpus sizes.
    text = load!("T0001", "如是我聞")

    assert text.char_count == String.length(text.body)
    assert text.char_count < byte_size(text.body)
  end

  test "a re-load updates it rather than leaving the old value" do
    # `on_conflict: {:replace, …}` must list it. A body that changed under a stale count is
    # exactly the drift a stored derived value is supposed to be immune to.
    load!("T0003", "短")
    reloaded = load!("T0003", "e\u0301e\u0301")

    assert reloaded.char_count == String.length(reloaded.body)
    assert reloaded.char_count > 1
  end

  test "the actual backfill agrees with the loader for combining characters without rewriting bytes" do
    for {id, body} <- [{"T0004", "e\u0301"}, {"T0005", "ཀི་ཀྲ"}, {"T0006", "如是我聞"}] do
      text = load!(id, body)
      expected = text.char_count
      Repo.update_all(from(t in Text, where: t.id == ^text.id), set: [char_count: nil])

      run_backfill()
      filled = Repo.get!(Text, text.id)
      assert filled.char_count == expected
      assert filled.char_count == String.length(filled.body)
      assert filled.body == text.body
      assert filled.body_sha256 == text.body_sha256
    end
  end

  test "backfill crosses a batch boundary, preserves populated counts, and is idempotent" do
    template = load!("T0100", "e\u0301")
    existing = Repo.get!(Text, template.id)
    now = DateTime.utc_now()

    Repo.insert_all(
      Pramana.Corpus.Work,
      for n <- 1..501 do
        %{id: "backfill-#{n}", title: "fixture", inserted_at: now, updated_at: now}
      end
    )

    rows =
      for n <- 1..501 do
        %{
          work_id: "backfill-#{n}",
          source_id: template.source_id,
          witness_id: template.witness_id,
          urn_prefix: "pramana:cbeta.T:backfill-#{n}",
          body: "e\u0301",
          body_sha256: Base.encode16(:crypto.hash(:sha256, "e\u0301"), case: :lower),
          char_count: nil,
          meta: %{},
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Text, rows)
    assert run_backfill() =~ "filled 501"
    assert Repo.aggregate(from(t in Text, where: is_nil(t.char_count)), :count) == 0

    assert Repo.all(from(t in Text, where: t.id != ^template.id, select: t.char_count)) ==
             List.duplicate(1, 501)

    assert Repo.get!(Text, template.id) == existing
    assert run_backfill() =~ "filled 0"
  end

  defp run_backfill do
    ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Pramana.Texts.CountChars.run([]) end)
  end
end
