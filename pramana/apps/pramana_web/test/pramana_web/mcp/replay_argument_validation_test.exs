defmodule PramanaWeb.MCP.ReplayArgumentValidationTest do
  @moduledoc """
  A replay may not verify a different query by discarding a misspelled scope or
  accepting a value the tool's declared input contract would reject.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.QueryCapture
  alias Pramana.Report
  alias PramanaWeb.MCP.ReplayExecutor
  alias PramanaWeb.MCP.Tools.VerifyReport

  @query "一切眾生"
  @xml """
  <TEI><text><body><milestone n="1" unit="juan"/>
  <lb n="0001a01"/>一切眾生
  </body></text></TEI>
  """

  setup do
    for {work, origin} <- [{"T0262", "indic"}, {"T0263", "chinese"}] do
      {:ok, ir} =
        CBETA.normalize(@xml,
          work_id: work,
          canon: "T",
          volume: 9,
          number: String.slice(work, 1..-1//1)
        )

      {:ok, _} =
        Loader.load(ir,
          source: "cbeta",
          witness: "T",
          provenance: %{composition_origin: origin, text_role: "root"}
        )
    end

    :ok
  end

  test "valid scope changes the answer; unknown scope cannot produce a pass or a false failure" do
    assert {:ok, scoped} = execute("survey_corpus", %{"query" => @query, "origin" => "indic"})
    assert {:ok, all} = execute("survey_corpus", %{"query" => @query})
    assert scoped["total_segments"] == 1
    assert all["total_segments"] == 2

    for asserted <- [1, 2] do
      report = document(%{"query" => @query, "originn" => "indic"}, asserted)
      result = Report.verify(report, executor: ReplayExecutor.executor())

      assert result.status == :incomplete
      refute result.ok?
      assert result.counts.replay_errors == 1
      assert result.counts.replay_failures == 0
      assert result.counts.verified_replays == 0
      assert [%{status: :error, detail: detail, arguments: original}] = result.replays
      assert detail =~ "invalid_arguments"
      assert original["originn"] == "indic"
    end
  end

  test "the real MCP response carries a refusal rather than a verified altered query" do
    report = document(%{"query" => @query, "originn" => "indic"}, 2)
    {:reply, response, %{}} = VerifyReport.execute(%{report: report}, %{})
    assert {:ok, payload} = ReplayExecutor.decode(response)

    assert payload["status"] == "incomplete"
    refute payload["ok?"]
    assert [%{"status" => "error", "detail" => detail}] = payload["replays"]
    assert detail =~ "unknown_field"
    assert payload["resolved_text"] == report
  end

  test "a rejected replay cannot hide another replay's genuine assertion failure" do
    report =
      document(%{"query" => @query, "originn" => "indic"}, 2) <>
        "\n\n" <> document(%{"query" => @query, "origin" => "indic"}, 9)

    result = Report.verify(report, executor: ReplayExecutor.executor())
    assert result.status == :failed
    refute result.ok?
    assert result.counts.replay_errors == 1
    assert result.counts.replay_failures == 1
    assert result.counts.verified_replays == 0
  end

  test "valid asserted replay still verifies with its supplied scope" do
    result =
      Report.verify(document(%{"query" => @query, "origin" => "indic"}, 1),
        executor: ReplayExecutor.executor()
      )

    assert result.status == :verified
    assert result.ok?
    assert result.counts.verified_replays == 1
  end

  test "a field declared by another tool is not accepted just because its atom exists" do
    assert Atom.to_string(:work_id) == "work_id"

    for args <- [
          %{"query" => @query, "work_id" => "T0262"},
          %{query: @query, work_id: "T0262"}
        ] do
      assert {:error, {:invalid_arguments, :unknown_field}} = execute("survey_corpus", args)
    end
  end

  test "every allowlisted tool rejects unknown fields before any query" do
    # Positive control: the shared helper really sees synchronous executor queries.
    {{:ok, %{"total_segments" => 2}}, observed} =
      QueryCapture.capture(fn -> execute("survey_corpus", %{"query" => @query}) end)

    assert observed != []

    {_, queries} =
      QueryCapture.capture(fn ->
        for tool <- ReplayExecutor.tools() do
          assert {:error, {:invalid_arguments, :unknown_field}} =
                   execute(tool, %{unknown_replay_argument: "must not be discarded"})
        end

        assert {:error, {:invalid_arguments, :schema_mismatch}} =
                 execute("search", %{"query" => @query, "normalize_variants" => "false"})
      end)

    assert queries == []
  end

  test "missing and wrongly typed required values are not delegated to the tool" do
    for value <- [nil, 12, false, [], %{}] do
      assert {:error, {:invalid_arguments, :schema_mismatch}} =
               execute("survey_corpus", %{"query" => value})
    end

    assert {:error, {:invalid_arguments, :schema_mismatch}} = execute("survey_corpus", %{})
  end

  test "optional scalar and collection types use the declared schema, not truthiness or fallback" do
    cases = [
      {"search", %{"query" => @query, "limit" => "20"}},
      {"search", %{"query" => @query, "limit" => 20.0}},
      {"search", %{"query" => @query, "normalize_variants" => "false"}},
      {"survey_corpus", %{"query" => @query, "origin" => ["indic"]}},
      {"compare_versions", %{"urn" => "pramana:cbeta.T:T0262", "relations" => "parallel"}},
      {"compare_versions", %{"urn" => "pramana:cbeta.T:T0262", "relations" => [1]}},
      {"search_translations", %{"query" => @query, "redistributable_only" => "false"}}
    ]

    for {tool, arguments} <- cases do
      assert {:error, {:invalid_arguments, :schema_mismatch}} = execute(tool, arguments)
    end
  end

  test "optional null and false preserve existing component semantics" do
    assert {:ok, payload} =
             execute("survey_corpus", %{"query" => @query, "origin" => nil})

    assert payload["total_segments"] == 2
    assert payload["replay"]["arguments"] == %{"query" => @query}

    assert {:ok, payload} =
             execute("search", %{
               "query" => @query,
               "mode" => "phrase",
               "normalize_variants" => false
             })

    assert payload["replay"]["arguments"]["normalize_variants"] == false
    assert payload["total"] == 2
  end

  test "valid collection options and capped limits retain their original receipts" do
    urn = "pramana:cbeta.T:T0262_001@p0001a01"

    arguments = %{
      "urn" => urn,
      "relations" => ["full", "resembling"],
      "include_text" => false,
      "limit" => 2
    }

    assert {:ok, compared} = execute("compare_versions", arguments)
    assert compared["passage"]["urn"] == urn
    assert compared["replay"]["arguments"] == arguments

    # The tool caps execution; validation must not reject a valid integer or
    # replace the originally supplied value in its receipt with the cap.
    arguments = %{"query" => @query, "mode" => "phrase", "limit" => 10_000}
    assert {:ok, searched} = execute("search", arguments)
    assert searched["total"] == 2
    assert searched["replay"]["arguments"] == arguments
  end

  test "conflicting or equal atom/string aliases are ambiguous, not last-write-wins" do
    for second <- [@query, "another query"] do
      arguments = Map.put(%{"query" => @query}, :query, second)

      assert {:error, {:invalid_arguments, :duplicate_field}} =
               execute("survey_corpus", arguments)
    end
  end

  test "non-object arguments and non-name keys are explicit refusals" do
    for arguments <- [nil, [], "query", 1, %URI{}] do
      assert {:error, {:invalid_arguments, :expected_object}} =
               execute("survey_corpus", arguments)
    end

    for key <- [123, {"query"}, ["query"]] do
      assert {:error, {:invalid_arguments, :unknown_field}} =
               execute("survey_corpus", %{key => @query})
    end
  end

  test "schema refusals do not echo supplied values from validator errors" do
    secret = %{"report_text" => "PRIVATE INPUT SENTINEL"}
    result = execute("survey_corpus", %{"query" => secret})
    assert {:error, {:invalid_arguments, :schema_mismatch}} = result
    refute inspect(result) =~ "PRIVATE INPUT SENTINEL"
  end

  defp execute(tool, arguments), do: ReplayExecutor.executor().(tool, arguments)

  defp document(arguments, total) do
    "```pramana-replay\n" <>
      Jason.encode!(%{
        tool: "survey_corpus",
        arguments: arguments,
        assert: %{total_segments: total}
      }) <>
      "\n```"
  end
end
