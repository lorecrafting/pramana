defmodule PramanaFoundry.ObservationsTest do
  use ExUnit.Case, async: true

  alias Exqlite.Sqlite3
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
      stored_type = if(type == "effect_observation_page", do: "effect", else: type)

      case Map.get(source.facts, {stored_type, id}, {:error, :not_found}) do
        {:error, reason} -> {:error, reason}
        fact -> {:ok, fact, source.observed_at}
      end
    end

    defp identity_key("effect"), do: "effect_id"
    defp identity_key("effect_observation_page"), do: "effect_id"
    defp identity_key("control"), do: "control_id"
    defp identity_key("inbox"), do: "execution_id"
  end

  defmodule RecoveryGateway do
    use GenServer

    def start_link(reason), do: GenServer.start_link(__MODULE__, reason)

    @impl true
    def init(reason), do: {:ok, reason}

    @impl true
    def handle_call(_request, _from, reason),
      do: {:reply, {:error, {:recovery_mode, reason}}, reason}
  end

  defmodule MaterializationTap do
    alias PramanaFoundry.Observations.GatewaySource

    def snapshot(state), do: GatewaySource.snapshot(state)

    def fact(state, query) do
      result = GatewaySource.fact(state, query)

      case result do
        {:ok, fact, _at} ->
          send(self(), {:materialized, query["type"], :erlang.external_size(fact)})

        _ ->
          :ok
      end

      result
    end
  end

  defmodule ChangedEffectPage do
    alias PramanaFoundry.Observations.GatewaySource

    def snapshot(state), do: GatewaySource.snapshot(state)

    def fact(state, %{"type" => "effect_observation_page"} = query) do
      with {:ok, fact, at} <- GatewaySource.fact(state, query) do
        {:ok, state.change.(fact), at}
      end
    end

    def fact(state, query), do: GatewaySource.fact(state, query)
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
      "status" => "unknown",
      "revision" => 2,
      "policy_revision" => 1,
      "control_revision" => 3,
      "phase_generation" => 0,
      "operation_ordinal" => 0,
      "predecessor_effect_id" => nil,
      "deadline" => %{"sk-secret-map-key-abcdef12" => "nested"},
      "claims" => [
        %{
          "schema_version" => 1,
          "claim_id" => "claim-1",
          "effect_id" => "effect-1",
          "writer_epoch" => "writer-epoch-1",
          "status" => "unknown",
          "revision" => 1,
          "receipts" => [
            %{
              "schema_version" => 1,
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
        "sequence" => 1,
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
    assert item.fact["deadline"] == nil

    assert item.fact["outcome"] == %{
             "status" => "unknown",
             "reason" => "outcome_unknown",
             "receipt_history" => ["unknown"]
           }

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

    seed_effect!(gateway, capability, "ticket-1")

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

  test "public effect observation materializes only the bounded protected DTO" do
    {root, gateway, capability} = live_effect("bounded-materialization", "ticket-1")
    on_exit(fn -> File.rm_rf!(root) end)
    payload = String.duplicate("x", 262_144)

    accept!(gateway, capability, "large-control", %{"control/control-1" => 0}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active", "diagnostic" => payload}
    })

    for sequence <- 1..8 do
      expected = if(sequence == 1, do: "absent", else: sequence - 2)

      accept!(
        gateway,
        capability,
        "large-inbox-#{sequence}",
        %{"inbox/execution-1" => expected},
        %{
          "type" => "append_inbox",
          "execution_id" => "execution-1",
          "sequence" => sequence,
          "item_kind" => if(sequence == 8, do: "result", else: "observation"),
          "payload" => %{"diagnostic" => payload}
        }
      )
    end

    accept!(gateway, capability, "seal-large-inbox", %{"inbox/execution-1" => 7}, %{
      "type" => "seal_inbox",
      "execution_id" => "execution-1",
      "last_sequence" => 8
    })

    source = %{gateway: gateway, capability: capability}

    assert %{status: :ok, size_bytes: size, items: [item]} =
             Observations.query_source(
               %Query{
                 include_pointers: false,
                 effect_ids: ["effect-1"],
                 max_bytes: 8_192,
                 limit: 1
               },
               {MaterializationTap, source}
             )

    assert size <= 8_192
    assert item.fact["control"]["status"] == "active"
    assert item.fact["execution"]["status"] == "result"
    assert item.fact["execution"]["sealed_sequence"] == 8
    assert_received {:materialized, "effect_observation_page", protected_bytes}
    assert protected_bytes <= 8_192
    refute_received {:materialized, "control", _}
    refute_received {:materialized, "inbox", _}
  end

  test "public canonical quality requires bounded page source and nested schema correlation" do
    {root, gateway, capability} = live_effect("bounded-schema", "ticket-1")
    on_exit(fn -> File.rm_rf!(root) end)

    changes = [
      &Map.delete(&1, "source"),
      &put_in(&1, ["source", "repository_id"], "another-repository"),
      &put_in(&1, ["source", "last_protected_command_sequence"], 999_999),
      &put_in(&1, ["source", "effect_revision"], 999_999),
      &put_in(&1, ["effect", "schema_version"], 999),
      &put_in(&1, ["relations", Access.at(0), "schema_version"], 999),
      &put_in(&1, ["control", "schema_version"], 999),
      &put_in(&1, ["execution", "schema_version"], 999),
      &put_in(&1, ["settlement", "schema_version"], 999)
    ]

    for change <- changes do
      assert %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
               Observations.query_source(
                 %Query{include_pointers: false, effect_ids: ["effect-1"]},
                 {ChangedEffectPage, %{gateway: gateway, capability: capability, change: change}}
               )
    end
  end

  test "live effect continuations are stable, redacted and stale after a protected append" do
    {root, gateway, capability} = live_effect("bounded-continuation", "ticket-1")
    on_exit(fn -> File.rm_rf!(root) end)

    request = %Query{
      include_pointers: false,
      effect_ids: ["effect-1"],
      limit: 1,
      max_bytes: 8_192
    }

    assert %{status: :ok, items: [first_item], next_cursor: cursor} =
             Observations.query(request, gateway, capability)

    assert is_map(cursor)
    assert first_item.fact["relations_truncated"]
    assert Enum.map(first_item.fact["relations"], & &1["kind"]) == ["claim"]
    refute inspect(cursor) =~ "effect-1"
    refute inspect(cursor) =~ "installation-fr18a"

    assert %{status: :ok, items: [second_item], next_cursor: nil} =
             Observations.query(%{request | cursor: cursor}, gateway, capability)

    assert Enum.map(second_item.fact["relations"], & &1["kind"]) == ["reservation"]
    refute second_item.fact["relations_truncated"]

    accept!(gateway, capability, "cursor-staling-command", %{"control/control-1" => 0}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active", "revision_note" => "stale cursor"}
    })

    assert %{
             status: :unavailable,
             quality: :unavailable,
             items: [],
             error_code: :stale_protected_cursor
           } = Observations.query(%{request | cursor: cursor}, gateway, capability)

    assert %{status: :corrupt, error_code: :invalid_query} =
             Observations.query(
               %{request | cursor: Map.put(cursor, "unexpected", true)},
               gateway,
               capability
             )
  end

  test "a missing live store is unavailable, never healthy empty" do
    root = unique_tmp("missing")
    gateway = start_supervised!({Gateway, path: Path.join(root, "missing.sqlite3")})
    on_exit(fn -> File.rm_rf!(root) end)

    assert %{status: :unavailable, items: [], error_code: :source_unavailable} =
             Observations.query(%Query{include_pointers: false}, gateway, make_ref())
  end

  test "live corrupt reopen, unauthorized capability and dead source stay distinct" do
    corrupt_root = unique_tmp("corrupt")
    corrupt_path = Path.join(corrupt_root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(corrupt_path,
               installation_id: "installation-fr18a",
               repository_id: "repository-fr18a"
             )

    {:ok, conn} = Sqlite3.open(corrupt_path, mode: :readwrite)

    :ok =
      Sqlite3.execute(conn, "UPDATE metadata SET value = '2' WHERE key = 'projection_version'")

    :ok = Sqlite3.close(conn)

    corrupt_gateway =
      start_supervised!(
        {Gateway,
         path: corrupt_path, protected_capability: capability, writer_epoch: "writer-epoch-fr18a"},
        id: :corrupt_observation_gateway
      )

    on_exit(fn -> File.rm_rf!(corrupt_root) end)

    assert %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
             Observations.query(%Query{include_pointers: false}, corrupt_gateway, capability)

    live_root = unique_tmp("availability")
    live_path = Path.join(live_root, "authority.sqlite3")
    live_capability = make_ref()

    assert :ok =
             Gateway.initialize(live_path,
               installation_id: "installation-fr18a",
               repository_id: "repository-fr18a"
             )

    live_gateway =
      start_supervised!(
        {Gateway,
         path: live_path,
         protected_capability: live_capability,
         writer_epoch: "writer-epoch-fr18a"},
        id: :availability_observation_gateway
      )

    on_exit(fn -> File.rm_rf!(live_root) end)

    assert %{status: :unavailable, quality: :unavailable, error_code: :source_unavailable} =
             Observations.query(%Query{include_pointers: false}, live_gateway, make_ref())

    stop_supervised!(:availability_observation_gateway)

    assert %{status: :unavailable, quality: :unavailable, error_code: :source_unavailable} =
             Observations.query(%Query{include_pointers: false}, live_gateway, live_capability)
  end

  test "physical SQLite corruption is corrupt while raw availability failures remain unavailable" do
    root = unique_tmp("physical-corrupt")
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation-fr18a",
               repository_id: "repository-fr18a"
             )

    {:ok, file} = :file.open(String.to_charlist(path), [:read, :write, :binary, :raw])
    :ok = :file.pwrite(file, 100, :binary.copy(<<0>>, 256))
    :ok = :file.sync(file)
    :ok = :file.close(file)

    gateway =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr18a"},
        id: :physical_corruption_observation_gateway
      )

    on_exit(fn -> File.rm_rf!(root) end)

    assert %{mode: :recovery, reason: "database disk image is malformed"} =
             Gateway.status(gateway)

    assert %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
             Observations.query(%Query{include_pointers: false}, gateway, capability)

    for {reason, id} <- [
          {"disk I/O error", :raw_io_unavailable_gateway},
          {"database disk image is malformed while remote storage is unavailable",
           :nonexact_corruption_text_gateway}
        ] do
      unavailable = start_supervised!({RecoveryGateway, reason}, id: id)

      assert %{status: :unavailable, quality: :unavailable, error_code: :source_unavailable} =
               Observations.query(%Query{include_pointers: false}, unavailable, make_ref())
    end

    for {reason, id} <- [
          {{:authority_corrupt, "table", "identity", :invalid},
           :structured_authority_corrupt_gateway},
          {{:protected_corrupt, "table", "identity"}, :structured_protected_corrupt_gateway}
        ] do
      corrupt = start_supervised!({RecoveryGateway, reason}, id: id)

      assert %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
               Observations.query(%Query{include_pointers: false}, corrupt, make_ref())
    end
  end

  test "terminal protected state governs reconciled and quarantined outcomes" do
    for {terminal, expected} <- [{"succeeded", "succeeded"}, {"failed", "failed"}] do
      {root, gateway, capability} = live_effect("outcome-#{terminal}", "ticket-1")
      on_exit(fn -> File.rm_rf!(root) end)

      settle!(
        gateway,
        capability,
        "unknown",
        1,
        2,
        "receipt-unknown",
        "unknown",
        "outcome_unknown",
        3,
        1
      )

      settle!(
        gateway,
        capability,
        "terminal",
        2,
        3,
        "receipt-terminal",
        terminal,
        "delivered",
        3,
        1
      )

      assert %{status: :ok, items: [item]} =
               Observations.query(
                 %Query{include_pointers: false, effect_ids: ["effect-1"]},
                 gateway,
                 capability
               )

      assert item.fact["status"] == expected

      assert item.fact["outcome"] == %{
               "status" => expected,
               "receipt_history" => ["unknown", expected]
             }
    end

    {root, gateway, capability} = live_effect("outcome-conflict", "ticket-1")
    on_exit(fn -> File.rm_rf!(root) end)

    settle!(
      gateway,
      capability,
      "success",
      1,
      2,
      "receipt-success",
      "succeeded",
      "delivered",
      3,
      1
    )

    assert {:ok, %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"},
            :committed} =
             protected(
               gateway,
               capability,
               "conflict",
               %{
                 "claim/claim-1" => 2,
                 "effect/effect-1" => 3,
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "reservation/reservation-1" => 4,
                 "ledger/root/0" => 2,
                 "receipt/receipt-conflict" => "absent"
               },
               settle_operation("receipt-conflict", "failed", "delivered")
             )

    assert %{status: :ok, items: [item]} =
             Observations.query(
               %Query{include_pointers: false, effect_ids: ["effect-1"]},
               gateway,
               capability
             )

    assert item.fact["status"] == "reconciliation_required"

    assert item.fact["outcome"] == %{
             "status" => "unknown",
             "reason" => "reconciliation_required",
             "receipt_history" => ["succeeded"]
           }
  end

  test "redaction covers live identities and source provenance" do
    secret_ticket = "sk-live-ticket-abcdef12"
    secret_installation = "sk-live-installation-abcdef12"
    secret_repository = "sk-live-repository-abcdef12"
    secret_writer = "sk-live-writer-abcdef12"
    root = unique_tmp("redaction")
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: secret_installation,
               repository_id: secret_repository
             )

    gateway =
      start_supervised!(
        {Gateway, path: path, protected_capability: capability, writer_epoch: secret_writer},
        id: :redaction_observation_gateway
      )

    on_exit(fn -> File.rm_rf!(root) end)
    seed_effect!(gateway, capability, secret_ticket)

    page =
      Observations.query(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        gateway,
        capability
      )

    assert %{status: :ok, source: source, items: [item]} = page
    assert source["installation_id"] == "[REDACTED]"
    assert source["repository_id"] == "[REDACTED]"
    assert source["writer_epoch"] == "[REDACTED]"
    assert item.identity["ticket_id"] == "[REDACTED]"
    assert item.fact["ticket_id"] == "[REDACTED]"
    refute inspect(page) =~ secret_ticket
    refute inspect(page) =~ secret_installation
    refute inspect(page) =~ secret_repository
    refute inspect(page) =~ secret_writer
  end

  test "redaction covers bounded relation, settlement and continuation envelopes" do
    observed_at = ~U[2026-09-20 12:00:00Z]
    secret = "sk-bounded-secret-abcdef12"

    effect_page = %{
      "schema_version" => 1,
      "type" => "effect_observation_page",
      "source" => %{
        "installation_id" => secret,
        "repository_id" => secret,
        "last_protected_command_sequence" => 4,
        "effect_revision" => 3
      },
      "effect" => %{
        "schema_version" => 1,
        "effect_id" => "effect-1",
        "ticket_id" => secret,
        "attempt_id" => "attempt-1",
        "execution_id" => "execution-1",
        "control_id" => "control-1",
        "policy_id" => "policy-1",
        "operation" => "launch",
        "scope" => "ticket:bounded",
        "status" => "non_started",
        "revision" => 3,
        "policy_revision" => 0,
        "control_revision" => 0
      },
      "control" => %{
        "schema_version" => 1,
        "control_id" => "control-1",
        "revision" => 0,
        "status" => "active"
      },
      "execution" => %{
        "schema_version" => 1,
        "execution_id" => "execution-1",
        "status" => "absent"
      },
      "relations" => [
        %{
          "schema_version" => 1,
          "kind" => "receipt",
          "receipt_id" => secret,
          "claim_id" => "claim-1",
          "request_id" => "request-1",
          "outcome" => "non_started",
          "receipt_digest" => String.duplicate("a", 64)
        }
      ],
      "infrastructure_settlement" => %{
        "schema_version" => 1,
        "effect_id" => "effect-1",
        "claim_id" => "claim-1",
        "receipt_id" => secret,
        "role" => "developer",
        "work_owner" => secret,
        "infrastructure_generation" => 0,
        "predecessor_effect_id" => nil,
        "failure_class" => secret,
        "ordinal" => 1
      },
      "settlement" => %{
        "schema_version" => 1,
        "status" => "non_started",
        "receipt_history" => "unknown"
      },
      "page" => %{
        "item_count" => 1,
        "size_bytes" => 0,
        "truncated" => true,
        "truncated_reason" => "item_limit",
        "next_cursor" => %{
          "schema_version" => 1,
          "query_type" => "effect_observation_page",
          "scope_digest" => String.duplicate("a", 64),
          "source_digest" => String.duplicate("b", 64),
          "protected_sequence" => 4,
          "effect_revision" => 3,
          "section" => "receipts",
          "offset" => 1
        }
      }
    }

    effect_page = protected_page_size(effect_page)

    facts =
      fake_effect_facts()
      |> Map.put({"effect", "effect-1"}, effect_page)

    page =
      Observations.query_source(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        {FakeSource,
         source(observed_at)
         |> put_in([:snapshot, "installation_id"], secret)
         |> put_in([:snapshot, "repository_id"], secret)
         |> Map.put(:facts, facts)},
        now: observed_at
      )

    assert %{status: :ok, items: [item], next_cursor: cursor} = page
    assert item.identity["ticket_id"] == "[REDACTED]"
    assert item.fact["infrastructure_settlement"]["work_owner"] == "[REDACTED]"
    assert is_map(cursor)
    refute inspect(page) =~ secret
  end

  defp protected_page_size(page) do
    size = :erlang.external_size(page)
    updated = put_in(page, ["page", "size_bytes"], size)

    if :erlang.external_size(updated) == size,
      do: updated,
      else: protected_page_size(updated)
  end

  test "malformed versions and execution fields cannot be canonical" do
    observed_at = ~U[2026-09-20 12:00:00Z]

    for field <-
          ~w(sql_schema_version protected_schema_version protocol_version event_version projection_version) do
      malformed = put_in(source(observed_at).snapshot[field], nil)

      assert %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
               Observations.query_source(
                 %Query{include_pointers: false},
                 {FakeSource, malformed},
                 now: observed_at
               )
    end

    base_facts = fake_effect_facts()

    malformed_inboxes = [
      Map.put(base_facts[{"inbox", "execution-1"}], "revision", "bad"),
      Map.put(base_facts[{"inbox", "execution-1"}], "last_sequence", -1),
      Map.put(base_facts[{"inbox", "execution-1"}], "sealed_sequence", 2),
      put_in(base_facts[{"inbox", "execution-1"}]["resolution"]["status"], "pending")
    ]

    for inbox <- malformed_inboxes do
      facts = Map.put(base_facts, {"inbox", "execution-1"}, inbox)

      assert %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
               Observations.query_source(
                 %Query{include_pointers: false, effect_ids: ["effect-1"]},
                 {FakeSource, %{source(observed_at) | facts: facts}},
                 now: observed_at
               )
    end
  end

  test "pointer vocabulary matches absent, unavailable and present protected states" do
    observed_at = ~U[2026-09-20 12:00:00Z]

    for {producer_status, observation_status} <-
          [{"absent", :absent}, {"unavailable", :unavailable}, {"present", :present}] do
      source = source(observed_at)

      changed_source =
        put_in(
          source.snapshot["pointers"]["accepted_source"]["producer_status"],
          producer_status
        )

      assert %{status: :ok, items: [item | _]} =
               Observations.query_source(
                 %Query{},
                 {FakeSource, changed_source},
                 now: observed_at
               )

      assert item.status == observation_status
      assert item.fact["producer_status"] == producer_status
    end
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
        "sql_schema_version" => "1",
        "protected_schema_version" => "2",
        "protocol_version" => "1",
        "event_version" => "1",
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

  defp fake_effect_facts do
    %{
      {"effect", "effect-1"} => %{
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
        "channel" => "protected-gateway",
        "status" => "pending",
        "revision" => 0,
        "policy_revision" => 0,
        "control_revision" => 0,
        "phase_generation" => 0,
        "operation_ordinal" => 0,
        "predecessor_effect_id" => nil,
        "claims" => [],
        "reservations" => []
      },
      {"control", "control-1"} => %{
        "schema_version" => 1,
        "control_id" => "control-1",
        "revision" => 0,
        "value" => %{"status" => "active"}
      },
      {"inbox", "execution-1"} => %{
        "schema_version" => 1,
        "execution_id" => "execution-1",
        "revision" => 0,
        "last_sequence" => 0,
        "sealed_sequence" => nil,
        "resolution" => %{"status" => "open"}
      }
    }
  end

  defp live_effect(label, ticket_id) do
    root = unique_tmp(label)
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
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr18a"},
        id: {:live_effect_gateway, label}
      )

    seed_effect!(gateway, capability, ticket_id)

    accept!(
      gateway,
      capability,
      "claim-command",
      %{
        "effect/effect-1" => 0,
        "claim/claim-1" => "absent",
        "reservation/reservation-1" => 1,
        "ledger/root/0" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0
      },
      %{
        "type" => "claim_effect",
        "effect_id" => "effect-1",
        "claim_id" => "claim-1",
        "writer_epoch" => "writer-epoch-fr18a"
      }
    )

    accept!(
      gateway,
      capability,
      "issue-command",
      %{
        "claim/claim-1" => 0,
        "effect/effect-1" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 2,
        "ledger/root/0" => 1
      },
      %{
        "type" => "issue_claim",
        "claim_id" => "claim-1",
        "writer_epoch" => "writer-epoch-fr18a"
      }
    )

    {root, gateway, capability}
  end

  defp seed_effect!(gateway, capability, ticket_id) do
    accept!(gateway, capability, "policy-command", %{"policy/policy-1" => "absent"}, %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:#{ticket_id}"]
      }
    })

    accept!(gateway, capability, "control-command", %{"control/control-1" => "absent"}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active", "sk-secret-key-abcdef12" => "private"}
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
        "scope" => "ticket:#{ticket_id}",
        "ticket_id" => ticket_id,
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
  end

  defp settle!(
         gateway,
         capability,
         command_id,
         claim_revision,
         effect_revision,
         receipt_id,
         outcome,
         proof,
         reservation_revision,
         ledger_revision
       ) do
    accept!(
      gateway,
      capability,
      command_id,
      %{
        "claim/claim-1" => claim_revision,
        "effect/effect-1" => effect_revision,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => reservation_revision,
        "ledger/root/0" => ledger_revision,
        "receipt/#{receipt_id}" => "absent"
      },
      settle_operation(receipt_id, outcome, proof)
    )
  end

  defp settle_operation(receipt_id, outcome, proof) do
    %{
      "type" => "settle_claim",
      "claim_id" => "claim-1",
      "receipt_id" => receipt_id,
      "request_id" => "request-1",
      "outcome" => outcome,
      "proof" => proof,
      "payload" => %{"representative" => true}
    }
  end

  defp protected(gateway, capability, command_id, expected_revisions, operation) do
    request = %{
      "schema_version" => 1,
      "command_id" => command_id,
      "expected_revisions" => expected_revisions,
      "operation" => operation
    }

    Gateway.protected_command(gateway, capability, "operator", request)
  end

  defp accept!(gateway, capability, command_id, expected_revisions, operation) do
    assert {:ok, %{"disposition" => "accepted"}, :committed} =
             protected(gateway, capability, command_id, expected_revisions, operation)
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
