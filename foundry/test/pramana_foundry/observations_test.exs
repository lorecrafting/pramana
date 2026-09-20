defmodule PramanaFoundry.ObservationsTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.Observations
  alias PramanaFoundry.Observations.Query

  defmodule FakeSource do
    @behaviour PramanaFoundry.Observations.Source

    @impl true
    def snapshot(%{snapshot: {:error, reason}}), do: {:error, reason}

    def snapshot(%{snapshot: snapshot, observed_at: observed_at}),
      do: {:ok, snapshot, observed_at}

    @impl true
    def fact(source, %{"type" => type} = query) do
      id = query[identity_key(type)]

      case Map.get(source.facts, {type, id}, {:error, :not_found}) do
        {:error, reason} -> {:error, reason}
        fact -> {:ok, fact, source.observed_at}
      end
    end

    defp identity_key("effect"), do: "effect_id"
    defp identity_key("control"), do: "control_id"
    defp identity_key("inbox"), do: "execution_id"
  end

  test "healthy empty, unavailable and corrupt sources are distinct" do
    observed_at = ~U[2026-09-20 12:00:00Z]
    healthy = source(observed_at)
    query = %Query{include_pointers: false}

    assert %{status: :ok, quality: :canonical, items: [], error_code: nil} =
             Observations.query_source(query, {FakeSource, healthy}, now: observed_at)

    unavailable = %{healthy | snapshot: {:error, :unavailable}}

    assert %{status: :unavailable, quality: :unavailable, items: [], error_code: code} =
             Observations.query_source(query, {FakeSource, unavailable}, now: observed_at)

    assert code == :source_unavailable

    corrupt = put_in(healthy.snapshot["pointers"]["healthy_build"]["revision"], "bad")

    assert %{status: :corrupt, quality: :corrupt, items: [], error_code: :source_corrupt} =
             Observations.query_source(query, {FakeSource, corrupt}, now: observed_at)
  end

  test "freshness is explicit and deterministic" do
    observed_at = ~U[2026-09-20 12:00:00Z]
    request = %Query{include_pointers: false, max_age_ms: 1_000}

    assert %{freshness: :fresh} =
             Observations.query_source(request, {FakeSource, source(observed_at)},
               now: ~U[2026-09-20 12:00:01Z]
             )

    assert %{freshness: :stale, quality: :canonical} =
             Observations.query_source(request, {FakeSource, source(observed_at)},
               now: ~U[2026-09-20 12:00:01.001Z]
             )
  end

  test "identity correlation is canonical and secret-bearing payloads are not exposed" do
    observed_at = ~U[2026-09-20 12:00:00Z]

    effect = %{
      "schema_version" => 1,
      "effect_id" => "effect-1",
      "ticket_id" => "ticket-1",
      "attempt_id" => "attempt-1",
      "execution_id" => "execution-1",
      "control_id" => "control-1",
      "policy_id" => "policy-1",
      "request_id" => "request-1",
      "assignment_id" => "assignment-1",
      "role" => "developer",
      "operation" => "launch",
      "scope" => "ticket:ticket-1",
      "profile" => "sol",
      "channel" => "local",
      "status" => "issued",
      "revision" => 2,
      "policy_revision" => 1,
      "control_revision" => 3,
      "phase_generation" => 0,
      "operation_ordinal" => 0,
      "predecessor_effect_id" => nil,
      "claims" => [
        %{
          "claim_id" => "claim-1",
          "receipts" => [
            %{
              "outcome" => "unknown",
              "payload" => %{"api_key" => "sk-do-not-expose"}
            }
          ]
        }
      ],
      "reservations" => [%{"reservation_id" => "reservation-1"}],
      "request" => %{"authorization" => "Bearer do-not-expose"}
    }

    control = %{
      "schema_version" => 1,
      "control_id" => "control-1",
      "revision" => 3,
      "value" => %{"status" => "active", "password" => "do-not-expose"}
    }

    inbox = %{
      "schema_version" => 1,
      "execution_id" => "execution-1",
      "revision" => 4,
      "last_sequence" => 2,
      "sealed_sequence" => 2,
      "resolution" => %{
        "status" => "result",
        "payload" => %{"token" => "do-not-expose"}
      }
    }

    facts = %{
      {"effect", "effect-1"} => effect,
      {"control", "control-1"} => control,
      {"inbox", "execution-1"} => inbox
    }

    page =
      Observations.query_source(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        {FakeSource, %{source(observed_at) | facts: facts}},
        now: observed_at
      )

    assert %{status: :ok, items: [item]} = page

    assert item.identity == %{
             "effect_id" => "effect-1",
             "ticket_id" => "ticket-1",
             "attempt_id" => "attempt-1",
             "execution_id" => "execution-1",
             "control_id" => "control-1"
           }

    assert item.fact["control"] == %{
             "control_id" => "control-1",
             "revision" => 3,
             "status" => "active"
           }

    assert item.fact["execution"]["status"] == "result"
    assert item.fact["outcome"] == %{"status" => "unknown"}
    assert item.fact["usage"] == %{"status" => "unknown", "reason" => "not_produced"}
    refute inspect(page) =~ "do-not-expose"
    refute inspect(page) =~ "sk-"
    refute inspect(page) =~ "Bearer"
  end

  test "pagination and serialized page size are bounded" do
    observed_at = ~U[2026-09-20 12:00:00Z]
    request = %Query{limit: 2, max_bytes: 8_192}

    first =
      Observations.query_source(request, {FakeSource, source(observed_at)}, now: observed_at)

    assert length(first.items) == 2
    assert first.next_cursor == 2
    assert first.size_bytes <= request.max_bytes

    second =
      Observations.query_source(
        %{request | cursor: first.next_cursor},
        {FakeSource, source(observed_at)},
        now: observed_at
      )

    assert length(second.items) == 1
    assert second.next_cursor == nil
    assert second.size_bytes <= request.max_bytes

    assert %{status: :corrupt, error_code: :invalid_query} =
             Observations.query_source(
               %{request | limit: 51},
               {FakeSource, source(observed_at)},
               now: observed_at
             )
  end

  test "the live FR-08A source reports three distinct absent pointers" do
    root = unique_tmp("live")
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation-fr18a",
               repository_id: "repository-fr18a"
             )

    gateway =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr18a"}
      )

    on_exit(fn -> File.rm_rf!(root) end)

    assert %{status: :ok, freshness: :fresh, items: items} =
             Observations.query(%Query{}, gateway, capability)

    assert Enum.map(items, & &1.identity["pointer_kind"]) ==
             ~w(accepted_source selected_deployment healthy_build)

    assert Enum.all?(items, &(&1.status == :absent))
    assert Enum.all?(items, &(&1.fact["producer_status"] == "absent"))
  end

  test "live protected effect facts preserve ticket through control identity" do
    root = unique_tmp("identity")
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation-fr18a",
               repository_id: "repository-fr18a"
             )

    gateway =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr18a"}
      )

    on_exit(fn -> File.rm_rf!(root) end)

    accept!(gateway, capability, "policy-command", %{"policy/policy-1" => "absent"}, %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:ticket-1"]
      }
    })

    accept!(gateway, capability, "control-command", %{"control/control-1" => "absent"}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active"}
    })

    accept!(gateway, capability, "ledger-command", %{"ledger/root/0" => "absent"}, %{
      "type" => "grant_ledger",
      "ledger_id" => "root",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 1
    })

    accept!(
      gateway,
      capability,
      "reservation-command",
      %{"ledger/root/0" => 0, "reservation/reservation-1" => "absent"},
      %{
        "type" => "reserve",
        "reservation_id" => "reservation-1",
        "ledger_id" => "root",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => "effect-1",
        "units" => 1
      }
    )

    accept!(
      gateway,
      capability,
      "effect-command",
      %{
        "effect/effect-1" => "absent",
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 0,
        "ledger/root/0" => 0
      },
      %{
        "type" => "create_effect",
        "effect_id" => "effect-1",
        "request" => %{
          "request_id" => "request-1",
          "role" => "developer",
          "profile" => "sol"
        },
        "operation" => "launch",
        "scope" => "ticket:ticket-1",
        "ticket_id" => "ticket-1",
        "attempt_id" => "attempt-1",
        "execution_id" => "execution-1",
        "policy_id" => "policy-1",
        "policy_revision" => 0,
        "control_id" => "control-1",
        "control_revision" => 0,
        "reservation_ids" => ["reservation-1"],
        "leases" => []
      }
    )

    assert %{status: :ok, items: [item]} =
             Observations.query(
               %Query{include_pointers: false, effect_ids: ["effect-1"]},
               gateway,
               capability
             )

    assert item.identity == %{
             "effect_id" => "effect-1",
             "ticket_id" => "ticket-1",
             "attempt_id" => "attempt-1",
             "execution_id" => "execution-1",
             "control_id" => "control-1"
           }

    assert item.fact["control"] == %{
             "control_id" => "control-1",
             "revision" => 0,
             "status" => "active"
           }

    assert item.fact["execution"] == %{
             "execution_id" => "execution-1",
             "status" => "absent"
           }
  end

  test "a missing live store is unavailable, never healthy empty" do
    root = unique_tmp("missing")
    gateway = start_supervised!({Gateway, path: Path.join(root, "missing.sqlite3")})
    on_exit(fn -> File.rm_rf!(root) end)

    assert %{status: :unavailable, items: [], error_code: :source_unavailable} =
             Observations.query(%Query{include_pointers: false}, gateway, make_ref())
  end

  defp source(observed_at) do
    %{
      observed_at: observed_at,
      facts: %{},
      snapshot: %{
        "schema_version" => 1,
        "installation_id" => "installation-1",
        "repository_id" => "repository-1",
        "writer_epoch" => "writer-epoch-1",
        "last_protected_command_sequence" => 4,
        "last_domain_event_sequence" => 7,
        "protected_schema_version" => "1",
        "projection_version" => "1",
        "pointers" => %{
          "accepted_source" => pointer("accepted_source"),
          "selected_deployment" => pointer("selected_deployment"),
          "healthy_build" => pointer("healthy_build")
        }
      }
    }
  end

  defp pointer(kind) do
    %{
      "schema_version" => 1,
      "pointer_kind" => kind,
      "producer_status" => "absent",
      "revision" => 0
    }
  end

  defp accept!(gateway, capability, command_id, expected_revisions, operation) do
    request = %{
      "schema_version" => 1,
      "command_id" => command_id,
      "expected_revisions" => expected_revisions,
      "operation" => operation
    }

    assert {:ok, %{"disposition" => "accepted"}, :committed} =
             Gateway.protected_command(gateway, capability, "operator", request)
  end

  defp unique_tmp(label) do
    root =
      Path.join(
        if(File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()),
        "fr18a-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)
    root
  end
end
