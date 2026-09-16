defmodule Pramana.RetrievalTest do
  @moduledoc """
  Tests for `Pramana.Retrieval` query dispatching, mode parsing, and telemetry.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Retrieval

  describe "modes/0" do
    test "returns the supported retrieval modes as strings" do
      modes = Retrieval.modes()

      for expected <- ~w(hybrid semantic auto phrase ngram terms) do
        assert expected in modes
      end
    end
  end

  describe "mode/1" do
    test "defaults to :hybrid when nil" do
      assert Retrieval.mode(nil) == :hybrid
    end

    test "maps known strings to their corresponding atoms" do
      assert Retrieval.mode("hybrid") == :hybrid
      assert Retrieval.mode("semantic") == :semantic
      assert Retrieval.mode("auto") == :auto
      assert Retrieval.mode("phrase") == :phrase
      assert Retrieval.mode("ngram") == :ngram
      assert Retrieval.mode("terms") == :terms
    end

    test "falls back to :hybrid for unknown strings" do
      assert Retrieval.mode("unsupported") == :hybrid
      assert Retrieval.mode("") == :hybrid
    end

    test "preserves valid atom modes" do
      assert Retrieval.mode(:hybrid) == :hybrid
      assert Retrieval.mode(:semantic) == :semantic
      assert Retrieval.mode(:auto) == :auto
      assert Retrieval.mode(:phrase) == :phrase
      assert Retrieval.mode(:ngram) == :ngram
      assert Retrieval.mode(:terms) == :terms
    end

    test "falls back to :hybrid for unknown atoms" do
      assert Retrieval.mode(:non_existent_mode) == :hybrid
    end
  end

  describe "search/2" do
    test "dispatches hybrid search by default" do
      assert {:ok, result} = Retrieval.search("如是我聞")
      assert is_list(result.results)
      assert is_list(result.retrievers)
    end

    test "dispatches semantic search when mode is :semantic" do
      assert {:ok, result} = Retrieval.search("如是我聞", mode: :semantic)
      assert is_list(result.results)
      assert is_list(result.retrievers)
    end

    test "dispatches lexical search and prunes non-lexical options" do
      # `:coverage` is a valid Hybrid option but unknown to Lexical (which raises on unknown opts).
      # The dispatcher must prune it via Keyword.take(opts, Lexical.known_opts()).
      assert {:ok, result} = Retrieval.search("如是我聞", mode: :phrase, coverage: false, limit: 5)
      assert result.mode == :phrase
      assert is_list(result.results)
    end

    test "dispatches string mode 'auto' to lexical retriever" do
      assert {:ok, result} = Retrieval.search("如是我聞", mode: "auto", limit: 5)
      assert is_list(result.results)
    end

    test "emits telemetry span events on error" do
      test_pid = self()
      handler_id = "test-retrieval-telemetry-error"

      :telemetry.attach(
        handler_id,
        [:pramana, :retrieval, :search],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:error, :empty_query} = Retrieval.search("   ")

      assert_receive {:telemetry_event, %{results: 0, duration: _},
                      %{outcome: :error, reason: :empty_query}}
    end

    test "emits telemetry span events on success" do
      test_pid = self()
      handler_id = "test-retrieval-telemetry-success"

      :telemetry.attach(
        handler_id,
        [:pramana, :retrieval, :search],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, _} = Retrieval.search("如是我聞", mode: :phrase)

      assert_receive {:telemetry_event, %{results: _count, duration: _},
                      %{mode: :phrase, outcome: :ok, retrievers: _}}
    end
  end
end
