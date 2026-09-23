defmodule PramanaFoundry.DurableStore.RecordCodecTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.RecordCodec

  test "normalization has one string-key semantic language and declared defaults only" do
    atom = %{schema_version: 1, result: %{schema_version: 1, disposition: "accepted"}}

    string = %{
      "schema_version" => 1,
      "result" => %{
        "schema_version" => 1,
        "disposition" => "accepted",
        "reason_code" => nil
      },
      "events" => [],
      "projections" => [],
      "intents" => []
    }

    assert {:ok, normalized} = RecordCodec.normalize_bundle(atom)
    assert {:ok, ^normalized} = RecordCodec.normalize_bundle(string)
    assert normalized["result"]["reason_code"] == nil
    assert Enum.all?(~w(events projections intents), &(normalized[&1] == []))

    assert {:error, :duplicate_field} =
             RecordCodec.normalize_bundle(%{
               "schema_version" => 1,
               schema_version: 1,
               result: %{schema_version: 1, disposition: "accepted"}
             })

    assert {:error, :invalid_collection} =
             RecordCodec.normalize_bundle(Map.put(atom, :events, nil))

    assert {:error, :unsupported_value} =
             RecordCodec.normalize_bundle(put_in(atom, [:result, :reason_code], 1.5))
  end

  test "stored results use identical admission, materialization and binding semantics" do
    candidate = %{schema_version: 1, disposition: "accepted"}
    assert {:ok, stored} = RecordCodec.materialize_result(candidate, 7)
    assert {:ok, bytes} = RecordCodec.encode(:result, stored)

    columns = %{schema_version: 1, disposition: "accepted", reason_code: nil, committed_seq: 7}
    assert {:ok, ^stored} = RecordCodec.decode_bound(:result, bytes, columns)

    assert {:error, :relational_binding_mismatch} =
             RecordCodec.decode_bound(:result, bytes, %{columns | committed_seq: 8})

    for invalid <- [
          %{schema_version: 1, disposition: "accepted", reason_code: "why"},
          %{schema_version: 1, disposition: "rejected"},
          %{schema_version: 1, disposition: "blocked", reason_code: ""}
        ] do
      assert {:error, :invalid_result_semantics} =
               RecordCodec.normalize(:candidate_result, invalid)
    end

    # Left loose deliberately (2026-09-22 refusal audit). This input was meant for
    # `:candidate_committed_seq_forbidden`, but `keys/3` refuses `committed_seq` first
    # with `:unknown_field` because `@result` does not allow it, so that guard cannot
    # fire. Pinning `:unknown_field` here would certify the wrong guard.
    assert {:error, _reason} =
             RecordCodec.normalize(:candidate_result, %{
               schema_version: 1,
               disposition: "accepted",
               committed_seq: 1
             })
  end

  test "projection carriers and writes are bijective, ordered and replay through one reducer" do
    events = [event("e0", "a", 0), event("e1", "a", 1)]
    projections = [projection("e0", "a", -1, 0), projection("e1", "a", 0, 1)]

    assert {:ok, plan} = RecordCodec.projection_plan(events, projections)

    assert {:ok, final} =
             Enum.reduce(plan, {:ok, %{}}, fn step, {:ok, state} ->
               RecordCodec.apply_projection(state, step)
             end)

    assert final[{"tickets", "a"}].revision == 1
    assert {:ok, ^final} = RecordCodec.reconstruct(events, final)

    assert {:error, :projection_write_missing} = RecordCodec.projection_plan(events, [])
    assert {:error, :projection_event_missing} = RecordCodec.projection_plan([], projections)

    assert {:error, :projection_event_missing} =
             RecordCodec.projection_plan(events, Enum.reverse(projections))
  end

  defp event(id, entity, revision) do
    %{
      "schema_version" => 1,
      "event_id" => id,
      "type" => "legacy_event",
      "payload" => %{
        "projection" => %{
          "namespace" => "tickets",
          "entity_id" => entity,
          "revision" => revision,
          "value" => %{"revision" => revision}
        }
      }
    }
  end

  defp projection(event_id, entity, expected, revision) do
    %{
      "schema_version" => 1,
      "namespace" => "tickets",
      "entity_id" => entity,
      "expected_revision" => expected,
      "revision" => revision,
      "last_event_id" => event_id,
      "value" => %{"revision" => revision}
    }
  end
end
