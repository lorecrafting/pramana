defmodule Strategy.PilotScopeArtifactTest do
  use ExUnit.Case, async: true

  alias Pramana.Pilot.ScopeArtifact

  test "valid synthetic contract artifact round-trips canonically" do
    artifact = valid_artifact()

    assert :ok = ScopeArtifact.validate(artifact)

    encoded = ScopeArtifact.encode(artifact)
    assert artifact == encoded |> ScopeArtifact.decode!()
    assert encoded == ScopeArtifact.encode(ScopeArtifact.decode!(encoded))
  end

  test "content hash detects semantic drift" do
    artifact = valid_artifact()
    changed = put_in(artifact, ["selection", "max_relation_depth"], 3)

    assert {:error, errors} = ScopeArtifact.validate(changed)
    assert "selection.max_relation_depth must be 2" in errors
    assert "scope_content_sha256 does not match canonical artifact content" in errors
  end

  test "frozen relation and seed sets cannot be weakened" do
    artifact = valid_artifact()

    changed = put_in(artifact, ["selection", "relation_types"], ["comments_on"])
    assert {:error, errors} = ScopeArtifact.validate(changed)
    assert "selection.relation_types must match the frozen v1 relation set" in errors

    changed =
      Map.update!(artifact, "seeds", fn seeds ->
        Enum.reject(seeds, &(&1["work_id"] == "T0125"))
      end)

    assert {:error, errors} = ScopeArtifact.validate(changed)
    assert "all four charter Āgamas must be present in seeds" in errors
  end

  test "relation arithmetic and alignment coverage are closed" do
    artifact = valid_artifact()

    changed = put_in(artifact, ["denominators", "relation_edge_count"], 2)
    assert {:error, errors} = ScopeArtifact.validate(changed)
    assert "relation_edge_count is wrong" in errors

    changed =
      put_in(
        artifact,
        ["alignment_coverage", Access.at(0), "has_passage_alignment"],
        false
      )

    assert {:error, errors} = ScopeArtifact.validate(changed)
    assert "has_passage_alignment must match alignment_rows" in errors
  end

  test "standalone checker accepts a valid saved artifact" do
    path =
      Path.join(
        System.tmp_dir!(),
        "pramana-pilot-scope-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, ScopeArtifact.encode(valid_artifact()))
    on_exit(fn -> File.rm(path) end)

    {output, 0} =
      System.cmd("elixir", ["bin/check_pilot_scope.exs", "--validate", path],
        cd: Path.expand("..", __DIR__),
        stderr_to_stdout: true
      )

    assert output =~ "pilot scope artifact valid"
  end

  defp valid_artifact do
    demand_ids = ~w(T0001 T0026 T0099 T0125 T0200 T0201 T0202 T0203 T0204 T0205)

    ranking =
      %{
        "cross_family_pairs" => 10,
        "directed_pairs" => 10,
        "unresolved_pairs" => 0,
        "conflicting_pairs" => 0,
        "direction_method_counts" => %{"role" => 10},
        "top_demand" =>
          demand_ids
          |> Enum.with_index(1)
          |> Enum.map(fn {id, rank} ->
            %{
              "rank" => rank,
              "work_id" => id,
              "family" => id,
              "weight" => 11 - rank,
              "citing_families" => 1,
              "directed_pair_count" => 1,
              "direction_methods" => %{"role" => 1},
              "family_members" => [id]
            }
          end)
      }

    seeds =
      demand_ids
      |> Enum.map(fn id ->
        %{
          "work_id" => id,
          "title" => id,
          "text_role" => "root",
          "division" => if(id in ScopeArtifact.agama_ids(), do: "阿含部", else: "經集部"),
          "seed_sources" =>
            if(id in ScopeArtifact.agama_ids(),
              do: ["agama", "demand_rank"],
              else: ["demand_rank"]
            ),
          "demand_rank" => Enum.find_index(demand_ids, &(&1 == id)) + 1,
          "demand_weight" => 1
        }
      end)
      |> Enum.sort_by(& &1["work_id"])

    works =
      (Enum.map(seeds, fn seed ->
         %{
           "work_id" => seed["work_id"],
           "title" => seed["title"],
           "text_role" => "root",
           "division" => seed["division"],
           "date_start" => 100,
           "date_end" => 200,
           "source" => "cbeta",
           "witness" => "T",
           "min_hop" => 0,
           "seed_ids" => [seed["work_id"]]
         }
       end) ++
         [
           %{
             "work_id" => "T1700",
             "title" => "commentary",
             "text_role" => "commentary",
             "division" => "經疏部",
             "date_start" => 500,
             "date_end" => 600,
             "source" => "cbeta",
             "witness" => "T",
             "min_hop" => 1,
             "seed_ids" => ["T0001"]
           }
         ])
      |> Enum.sort_by(& &1["work_id"])

    relation = %{
      "source_work_id" => "T1700",
      "target_work_id" => "T0001",
      "relation" => "comments_on",
      "hop" => 1,
      "seed_ids" => ["T0001"],
      "assertions" => [
        %{
          "method" => "title_match",
          "confidence" => "certain",
          "scope" => "whole_work",
          "target_urn" => nil,
          "evidence_sha256" => String.duplicate("a", 64)
        }
      ]
    }

    coverage = %{
      "commentary_work_id" => "T1700",
      "target_work_id" => "T0001",
      "relation" => "comments_on",
      "alignment_rows" => 2,
      "distinct_root_urns" => 2,
      "distinct_commentary_urns" => 2,
      "has_passage_alignment" => true
    }

    payload = %{
      "release" => %{
        "release_id" => "release-test",
        "source_bake_id" => "bake-test",
        "translation_set_id" => "v2:translation-test",
        "vector_set_id" => "v2:vector-test",
        "stamped_at" => "2026-09-18T00:00:00Z"
      },
      "selection" => %{
        "demand_seed_count" => 10,
        "demand_ranking_rule" => ScopeArtifact.demand_ranking_rule(),
        "agama_work_ids" => ScopeArtifact.agama_ids(),
        "scope_source" => "cbeta.T",
        "relation_types" => ScopeArtifact.allowed_relations(),
        "relation_methods" => ScopeArtifact.allowed_relation_methods(),
        "max_relation_depth" => 2
      },
      "ranking" =>
        Map.merge(ranking, %{
          "rule" => ScopeArtifact.demand_ranking_rule(),
          "cutoff_weight" => 1,
          "cutoff_tied_families" => ["T0205"]
        }),
      "seeds" => seeds,
      "works" => works,
      "relations" => [relation],
      "alignment_coverage" => [coverage],
      "denominators" => %{
        "combined_seed_count" => 10,
        "demand_seed_count" => 10,
        "agama_required_count" => 4,
        "total_work_count" => 11,
        "expanded_work_count" => 1,
        "relation_edge_count" => 1,
        "relation_assertion_count" => 1,
        "relation_edges_with_alignment" => 1,
        "alignment_rows" => 2,
        "works_by_text_role" => %{"commentary" => 1, "root" => 10},
        "excluded_relation_rows_outside_cbeta" => 0,
        "excluded_model_relation_rows" => 0,
        "excluded_role_incoherent_relation_rows" => 0
      },
      "input_digests" => %{
        "work_metadata" => String.duplicate("1", 64),
        "quotation_graph" => String.duplicate("2", 64),
        "relation_graph" => String.duplicate("3", 64),
        "alignment_graph" => String.duplicate("4", 64)
      }
    }

    ScopeArtifact.finalize(payload)
  end
end
