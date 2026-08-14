defmodule Pramana.PipelineTest do
  @moduledoc """
  The pipeline contracts exist so that a better ingest method later is cheap, and a new
  source is three behaviours plus one registry entry rather than a copy-paste.
  """
  use ExUnit.Case, async: true

  alias Pramana.Pipeline

  describe "for_source/1" do
    test "binds cbeta to its pipeline modules" do
      assert {:ok, config} = Pipeline.for_source("cbeta")

      assert config.acquirer == Pramana.Acquire.CBETA
      assert config.normalizer == Pramana.Normalize.CBETA
      assert config.segmenter == Pramana.Segment.Taisho
      assert config.witness == "T"
    end

    test "rejects an unregistered source rather than guessing" do
      assert {:error, :unsupported_source} = Pipeline.for_source("sat")
      assert {:error, :unsupported_source} = Pipeline.for_source("nonsense")
    end
  end

  describe "behaviour conformance" do
    # Catches a source registered with a module that does not actually implement the
    # contract — the failure mode a registry invites.
    test "every registered pipeline's modules implement their behaviours" do
      for source <- Pipeline.sources() do
        {:ok, c} = Pipeline.for_source(source)

        assert implements?(c.acquirer, Pipeline.Acquirer),
               "#{inspect(c.acquirer)} does not implement Acquirer"

        assert implements?(c.normalizer, Pipeline.Normalizer),
               "#{inspect(c.normalizer)} does not implement Normalizer"

        assert implements?(c.segmenter, Pipeline.Segmenter),
               "#{inspect(c.segmenter)} does not implement Segmenter"
      end
    end

    test "acquirers export the whole callback set" do
      {:ok, c} = Pipeline.for_source("cbeta")
      # function_exported?/3 answers false for a module that simply is not loaded yet,
      # which would make this test pass or fail by load order rather than by fact.
      Code.ensure_loaded!(c.acquirer)

      assert function_exported?(c.acquirer, :pin, 1)
      assert function_exported?(c.acquirer, :fetch, 3)
      assert function_exported?(c.acquirer, :raw_path, 1)
    end
  end

  describe "raw_path/1" do
    test "resolves a CBETA target to its path under raw/" do
      {:ok, c} = Pipeline.for_source("cbeta")

      assert c.acquirer.raw_path(%{canon: "T", volume: 9, number: "0262"}) ==
               "T/T09/T09n0262.xml"
    end
  end

  defp implements?(module, behaviour) do
    Code.ensure_loaded?(module) and
      behaviour in (module.module_info(:attributes)
                    |> Keyword.get_values(:behaviour)
                    |> List.flatten())
  end
end
