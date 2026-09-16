defmodule Pramana.QuotationsTest do
  @moduledoc """
  The quotation graph — where one work reproduces another's words verbatim.

  Two properties carry the weight. **Neither end is the source**: identical characters
  say nothing about who quoted whom, and a shape that named one end the origin would be
  asserting a conclusion about transmission that the evidence cannot support. And **a
  match must resolve to a citation**: a reuse that cannot be quoted back is not something
  this project can serve, so it is dropped and counted rather than stored with a null
  anchor.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Quotations
  alias Pramana.Repo

  # Two works sharing a passage: a root sūtra and a commentary quoting it.
  @shared "色無常受想行識亦復無常如是觀者名為正觀"

  defp seed_text!(work_id, lines) do
    Repo.insert!(%Work{id: work_id, title: work_id})
    body = Enum.join(lines, "")

    text =
      Repo.insert!(%Text{
        work_id: work_id,
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:#{work_id}",
        body: body,
        body_sha256: "x",
        meta: %{}
      })

    _ =
      Enum.reduce(lines, {0, 1}, fn line, {offset, n} ->
        Repo.insert!(%Segment{
          text_id: text.id,
          urn: "pramana:cbeta.T:#{work_id}_001@p000#{n}a01",
          ordinal: n - 1,
          content: line,
          content_sha256: "y",
          char_start: offset,
          char_end: offset + String.length(line),
          byte_start: 0,
          byte_end: 0,
          meta: %{}
        })

        {offset + String.length(line), n + 1}
      end)

    text
  end

  defp match(a_text, a_start, b_text, b_start, text \\ @shared) do
    %{
      "text" => text,
      "length" => String.length(text),
      "occurrences" => [
        %{
          "work" => Integer.to_string(a_text.id),
          "start" => a_start,
          "end" => a_start + String.length(text)
        },
        %{
          "work" => Integer.to_string(b_text.id),
          "start" => b_start,
          "end" => b_start + String.length(text)
        }
      ]
    }
  end

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})

    root = seed_text!("T0099", ["爾時世尊告諸比丘", @shared, "如是說已諸比丘歡喜"])
    commentary = seed_text!("T1579", ["論曰經云", @shared, "此明五陰皆悉無常"])

    {:ok, root: root, commentary: commentary}
  end

  describe "storing a match" do
    test "resolves each end to a citable URN", %{root: root, commentary: commentary} do
      {:ok, result} = Quotations.store([match(root, 8, commentary, 4)])

      assert result.written == 1
      [q] = Repo.all(Quotation)

      assert q.a_urn =~ "T0099"
      assert q.b_urn =~ "T1579"
      assert q.text == @shared
    end

    test "hashes the matched text, so a stale row is detectable", %{
      root: root,
      commentary: commentary
    } do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])
      [q] = Repo.all(Quotation)

      # Offsets alone become meaningless after a re-bake; the hash makes a stale row
      # visible rather than silently wrong.
      assert q.text_sha256 == :crypto.hash(:sha256, @shared) |> Base.encode16(case: :lower)
    end

    test "a match spanning several printed lines becomes a range URN", %{
      root: root,
      commentary: commentary
    } do
      # Reuse crosses line breaks constantly — the break is typographic, not syntactic.
      long = "爾時世尊告諸比丘" <> @shared
      {:ok, _} = Quotations.store([match(root, 0, commentary, 0, long)])

      [q] = Repo.all(Quotation)
      assert q.a_urn =~ "-"
    end

    test "an unresolvable end is dropped and counted, never stored with a null anchor", %{
      root: root
    } do
      unknown = %{
        "text" => @shared,
        "length" => String.length(@shared),
        "occurrences" => [
          %{"work" => Integer.to_string(root.id), "start" => 8, "end" => 27},
          %{"work" => "999999", "start" => 0, "end" => 19}
        ]
      }

      {:ok, result} = Quotations.store([unknown])

      assert result.written == 0
      assert result.unresolved == 1
      assert Repo.aggregate(Quotation, :count) == 0
    end

    test "is idempotent — the same reuse found twice is one fact", %{
      root: root,
      commentary: commentary
    } do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])
      {:ok, second} = Quotations.store([match(root, 8, commentary, 4)])

      assert second.written == 0
      assert Repo.aggregate(Quotation, :count) == 1
    end
  end

  describe "querying" do
    test "finds every work reproducing a passage", %{root: root, commentary: commentary} do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])

      {:ok, result} = Quotations.quoting("pramana:cbeta.T:T0099_001@p0002a01")

      assert result.total == 1
      assert hd(result.quotations).other_work_id == "T1579"
    end

    test "orients the result so `here` is the passage asked about", %{
      root: root,
      commentary: commentary
    } do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])

      {:ok, from_commentary} = Quotations.quoting("pramana:cbeta.T:T1579_001@p0002a01")

      # The match is stored once, arbitrarily oriented. Asking from either end must give
      # the same answer with the ends the right way round.
      assert hd(from_commentary.quotations).other_work_id == "T0099"
      assert hd(from_commentary.quotations).here =~ "T1579"
    end

    test "says plainly that direction is not established", %{
      root: root,
      commentary: commentary
    } do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])
      {:ok, result} = Quotations.quoting("pramana:cbeta.T:T0099_001@p0002a01")

      assert result.note =~ "Neither end is marked as the origin"
    end

    test "an overlapping quotation counts, not only a contained one", %{
      root: root,
      commentary: commentary
    } do
      # A commentary lifting a clause is the commonest case; requiring containment would
      # hide it.
      {:ok, _} = Quotations.store([match(root, 4, commentary, 0, "諸比丘色無常受想行識亦復無常")])

      {:ok, result} = Quotations.quoting("pramana:cbeta.T:T0099_001@p0001a01")
      assert result.total == 1
    end

    test "for_work reads both ends of the graph", %{root: root, commentary: commentary} do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])

      # Stored once with T0099 arbitrarily as the `a` end — querying the other work must
      # still find it.
      assert length(Quotations.for_work("T1579")) == 1
      assert length(Quotations.for_work("T0099")) == 1
    end

    test "min_length filters short reuse", %{root: root, commentary: commentary} do
      {:ok, _} = Quotations.store([match(root, 8, commentary, 4)])

      assert Quotations.for_work("T0099", min_length: 100) == []
      assert length(Quotations.for_work("T0099", min_length: 10)) == 1
    end

    test "a URN addressing nothing is not found" do
      assert {:error, :not_found} = Quotations.quoting("pramana:cbeta.T:T9999_001@p0001a01")
    end
  end

  describe "the database refuses an incoherent row" do
    test "a work cannot quote itself", %{root: root} do
      # Self-repetition is a refrain, not a citation, and mixing the two would swamp the
      # graph. Enforced in the database because remembering it at every write site is
      # how it stops being enforced.
      assert_raise Postgrex.Error, ~r/quotation_spans_two_texts/, fn ->
        Repo.insert_all(Quotation, [
          %{
            text: @shared,
            text_sha256: "x",
            length: 19,
            a_text_id: root.id,
            a_work_id: "T0099",
            a_urn: "pramana:cbeta.T:T0099_001@p0002a01",
            a_char_start: 8,
            a_char_end: 27,
            b_text_id: root.id,
            b_work_id: "T0099",
            b_urn: "pramana:cbeta.T:T0099_001@p0002a01",
            b_char_start: 8,
            b_char_end: 27,
            meta: %{},
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ])
      end
    end
  end
end
