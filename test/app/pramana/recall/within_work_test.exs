defmodule Pramana.Recall.WithinWorkTest do
  @moduledoc """
  The within-work diagnostic, and the rule-68 regression that made its first version
  report a confident zero.

  **`on the line` reports three different situations identically** — no translation exists
  for the covering chunk, one exists and ranks too low, or it never becomes a candidate —
  and they call for three different responses. This separates them, and on 2026-09-04 it
  decided `docs/PLAN.md` § E1 item 8 by returning `never generated: 0` for every generated
  arm, which is what established that more coverage could not be the answer.

  **The test that matters most here is the range-anchored one.** The first version of this
  probe located the covering chunk with `segments.urn = $anchor`, which drops every
  rendering anchored to a range — 2,080 of patton's 3,354, because most renderings cross a
  printed line break. It reported 167 of 205 cases as "never generated" and 0 at every
  rank, which reads exactly like a finding. Rule 68: a URN comparison is a parser.
  """
  use Pramana.DataCase, async: true

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Recall
  alias Pramana.Repo
  alias Pramana.Translations

  # Built through the real normalizer and loader rather than by hand, so the URNs are the
  # ones this corpus actually mints — which is the whole subject of the test.
  defp corpus! do
    body =
      ["如是我聞一時佛住", "王舍城耆闍崛山中"]
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{text})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">雜阿含經</title>
    <author>x</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: "T0099", canon: "T", volume: 1, number: "0099")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", title: "雜阿含經")

    text_id = Repo.one!(from t in Text, where: t.work_id == "T0099", select: t.id)
    {:ok, _} = Builder.build_for_text(text_id, max_chars: 200)

    Repo.all(
      from s in Pramana.Corpus.Segment,
        where: s.text_id == ^text_id,
        order_by: s.ordinal,
        select: s.urn
    )
  end

  # `prefix@a-b` is the range grammar this corpus prints. Built explicitly here because a
  # fixture is the one place the shape should be written out rather than derived.
  defp range_urn([first, second]) do
    [prefix, first_locator] = String.split(first, "@")
    [_, second_locator] = String.split(second, "@")
    "#{prefix}@#{first_locator}-#{second_locator}"
  end

  defp rendering!(anchor_urn) do
    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: anchor_urn,
          work_id: "T0099",
          lang: "en",
          translator_id: "patton",
          tier: "t0",
          method: "human",
          text:
            "Thus have I heard. At one time the Buddha was staying near Rājagṛha " <>
              "on Vulture Peak with a great assembly of monks.",
          redistributable: true,
          license_class: "cc0"
        }
      ])
  end

  describe "locating the covering chunk" do
    test "a RANGE-anchored rendering is located, not counted as missing" do
      urns = corpus!()
      rendering!(range_urn(urns))

      result = Recall.within_work(sample: 10, seed: 0.42, to: "cbeta.T")

      assert result.sampled == 1

      assert result.unlocated == 0,
             """
             A range-anchored rendering resolved to no chunk. That is rule 68: the join
             must go through `Corpus.resolve/1`, which accepts both anchor forms, and match
             on character offsets — columns that cannot be ranges. An equality test on
             `segments.urn` drops 2,080 of patton's 3,354 renderings and reports them as
             absent translations.
             """

      assert result.located == 1
    end

    test "a point-anchored rendering is located too" do
      [first, _] = corpus!()
      rendering!(first)

      assert %{located: 1, unlocated: 0} =
               Recall.within_work(sample: 10, seed: 0.42, to: "cbeta.T")
    end
  end

  describe "the three situations `on the line` cannot tell apart" do
    test "an arm with no vector on the covering chunk is `never_generated`, not a low rank" do
      # THE DISTINCTION THAT DECIDED ITEM 8. Reported as a miss this looks like a ranking
      # problem and the response is to rerank; reported as `never_generated` it is a
      # coverage problem and the response is to translate more. Opposite spends.
      urns = corpus!()
      rendering!(range_urn(urns))

      result =
        Recall.within_work(
          sample: 10,
          seed: 0.42,
          to: "cbeta.T",
          translators: ["model:mitra"]
        )

      assert result.buckets == %{never_generated: 1}
    end

    test "the no-English control is not reported as `never_generated`" do
      # `[]` is the control arm and its absence of English is the point. Asking whether it
      # has a translation vector answers "no" for every case, short-circuits the search and
      # returns a floor row of 189/0/0/0 that measures nothing. This probe did that on its
      # first real use. `nil` and `[]` differ, and here they must behave the same.
      urns = corpus!()
      rendering!(range_urn(urns))

      result = Recall.within_work(sample: 10, seed: 0.42, to: "cbeta.T", translators: [])

      refute Map.has_key?(result.buckets, :never_generated),
             "the no-English control short-circuited instead of measuring a rank"
    end

    test "the report always carries its denominator" do
      urns = corpus!()
      rendering!(range_urn(urns))

      result = Recall.within_work(sample: 10, seed: 0.42, to: "cbeta.T")

      # Rules 22, 44 and 54, inside the instrument those rules are measured with: a bucket
      # count with nothing to divide it by is the failure this project is most prone to.
      assert result.sampled == result.located + result.unlocated
      assert is_integer(result.limit)
    end
  end
end
