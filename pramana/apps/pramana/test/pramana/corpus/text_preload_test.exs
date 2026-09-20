defmodule Pramana.Corpus.TextPreloadTest do
  @moduledoc """
  `texts.body` must never ride along on a query that only needs a text's identity.

  This defect was found and fixed in `Retrieval.Lexical`, written up as a rule, and then
  found again in THREE more places — the two `Corpus` span builders, the context-window
  query, and the semantic ANN select. In the semantic path it was the dominant cost of the
  entire system: one search took 41 s, of which ~38 s was moving bodies, and it fell to
  2.2 s once they were dropped.

  So the guard is here, against the shared helper and its call sites, rather than only
  against the retriever where it was first noticed. Asserted on the emitted SQL, because
  the waste is invisible in the results: the spans are byte-identical either way.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001c18"/>序品第一
  <lb n="0001c19"/>如是我聞：一時，佛住王舍城
  <lb n="0001c20"/>耆闍崛山中，與大比丘眾萬二千人俱
  <lb n="0001c21"/>皆是阿羅漢，諸漏已盡
  </body></text></TEI>
  """

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "translation"}
      )

    %{urn: "pramana:cbeta.T:T0262_001@p0001c19"}
  end

  describe "Text.fields_without_body/0" do
    test "is every schema field, minus body" do
      fields = Text.fields_without_body()

      refute :body in fields
      assert :body_sha256 in fields, "the sha must survive; the guard verifies against it"

      # Derived by subtraction rather than written out, so a column added to `texts`
      # later is included automatically instead of silently reading as nil.
      assert Enum.sort(fields) == Enum.sort(Text.__schema__(:fields) -- [:body])
    end
  end

  describe "the span builders" do
    test "resolving a URN does not fetch the body", %{urn: urn} do
      queries = capture_queries(fn -> {:ok, _} = Corpus.resolve(urn) end)

      refute Enum.any?(queries, &(&1 =~ ~s("body"))),
             "a span resolve shipped texts.body; it needs the sha, not the whole work"
    end

    test "a context window does not fetch the body once per neighbour", %{urn: urn} do
      queries = capture_queries(fn -> {:ok, _} = Corpus.context(urn, before: 2, after: 2) end)

      refute Enum.any?(queries, &(&1 =~ ~s("body")))
    end

    test "a range URN does not fetch the body once per member" do
      # `between/4` is the one that mattered: the semantic path called it once per result,
      # 120 times per search, each dragging a whole work.
      range = "pramana:cbeta.T:T0262_001@p0001c19-p0001c21"
      queries = capture_queries(fn -> {:ok, _} = Corpus.resolve(range) end)

      refute Enum.any?(queries, &(&1 =~ ~s("body")))
    end
  end

  describe "what the span still carries" do
    # Dropping a column is only safe if nothing downstream read it. These matter more
    # than the SQL assertions above: the guard re-resolves and byte-compares.
    test "the span is still byte-verifiable", %{urn: urn} do
      {:ok, span} = Corpus.resolve(urn)

      assert span.content != ""
      assert :crypto.hash(:sha256, span.content) |> Base.encode16(case: :lower) == span.sha256
    end

    test "provenance survives, which is what the preload existed for", %{urn: urn} do
      {:ok, span} = Corpus.resolve(urn)

      assert span.provenance.composition_origin == "indic"
      assert span.provenance.text_role == "translation"
      assert span.provenance.title == "妙法蓮華經"
    end

    test "the body is still reachable when something actually needs it", %{urn: urn} do
      # `Corpus.body/1` is the deliberate path, keyed by urn_prefix. Removing the
      # ride-along must not have made the body unreachable — offsets verify against it.
      {:ok, span} = Corpus.resolve(urn)
      prefix = Pramana.Repo.one!(Ecto.Query.from(t in Text, select: t.urn_prefix, limit: 1))
      {:ok, body} = Corpus.body(prefix)

      assert is_binary(body)
      assert binary_part(body, span.byte_start, span.byte_end - span.byte_start) == span.content
    end
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "capture-text-preload-#{inspect(test_pid)}"

    :telemetry.attach(
      handler,
      [:pramana, :repo, :query],
      fn _event, _measurements, %{query: query}, pid ->
        if self() == pid, do: send(pid, {:captured_query, query})
      end,
      test_pid
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    queries = drain([])
    assert queries != [], "no SQL captured: a broken observation must not pass"

    assert Enum.any?(queries, &String.contains?(&1, ~s(FROM "segments"))),
           "expected a segment query, got: #{inspect(queries)}"

    queries
  end

  defp drain(acc) do
    receive do
      {:captured_query, q} -> drain([q | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
