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
      # No `witness`: it is a property of the WORK, not of the source. See the registry.
      refute Map.has_key?(config, :witness)
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
      sources = Pipeline.sources()
      assert sources != []

      for source <- sources do
        {:ok, c} = Pipeline.for_source(source)

        assert implements?(c.acquirer, Pipeline.Acquirer),
               "#{inspect(c.acquirer)} does not implement Acquirer"

        assert implements?(c.normalizer, Pipeline.Normalizer),
               "#{inspect(c.normalizer)} does not implement Normalizer"

        assert implements?(c.segmenter, Pipeline.Segmenter),
               "#{inspect(c.segmenter)} does not implement Segmenter"
      end
    end

    test "all registered pipeline modules export their complete required callback sets" do
      assert Pipeline.sources() != []

      for source <- Pipeline.sources() do
        {:ok, config} = Pipeline.for_source(source)

        for {module, behaviour} <- [
              {config.acquirer, Pipeline.Acquirer},
              {config.normalizer, Pipeline.Normalizer},
              {config.segmenter, Pipeline.Segmenter}
            ] do
          Code.ensure_loaded!(module)

          required =
            behaviour.behaviour_info(:callbacks) -- behaviour.behaviour_info(:optional_callbacks)

          assert required != []

          for {name, arity} <- required do
            assert function_exported?(module, name, arity),
                   "#{inspect(module)} lacks #{name}/#{arity}"
          end
        end
      end
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
