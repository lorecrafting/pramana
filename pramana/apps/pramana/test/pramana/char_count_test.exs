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

    Repo.one!(from t in Text, where: t.work_id == ^work_id)
  end

  test "counts CHARACTERS, not bytes" do
    # A Chinese character is three bytes in UTF-8. `byte_size/1` would report roughly three
    # times as many and be wrong in a way nobody would notice, because both numbers look
    # like plausible corpus sizes.
    text = load!("T0001", "如是我聞")

    assert text.char_count == String.length(text.body)
    assert text.char_count < byte_size(text.body)
  end

  test "is written with the body, so it cannot drift" do
    # Not a cache: there is no moment at which the body exists and the count does not, which
    # is the whole reason this is a column rather than something with invalidation.
    text = load!("T0002", "如是我聞一時佛住")

    assert text.char_count == String.length(text.body)
  end

  test "a re-load updates it rather than leaving the old value" do
    # `on_conflict: {:replace, …}` must list it. A body that changed under a stale count is
    # exactly the drift a stored derived value is supposed to be immune to.
    load!("T0003", "短")
    reloaded = load!("T0003", "長長長長長長長長")

    assert reloaded.char_count == String.length(reloaded.body)
    assert reloaded.char_count > 1
  end

  test "the backfill agrees with what the loader would have written" do
    # Postgres `char_length` and Elixir `String.length/1` must return the same number, or a
    # backfilled row and a freshly loaded one disagree about the same text.
    text = load!("T0004", "如是我聞，一時佛住王舍城")
    Repo.update_all(from(t in Text, where: t.id == ^text.id), set: [char_count: nil])

    Repo.update_all(
      from(t in Text,
        where: t.id == ^text.id,
        update: [set: [char_count: fragment("char_length(body)")]]
      ),
      []
    )

    assert Repo.one!(from t in Text, where: t.id == ^text.id, select: t.char_count) ==
             String.length(text.body)
  end
end
