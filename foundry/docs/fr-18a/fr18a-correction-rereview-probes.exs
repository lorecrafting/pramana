alias Exqlite.Sqlite3

alias PramanaFoundry.DurableStore.Gateway
alias PramanaFoundry.Observations
alias PramanaFoundry.Observations.Query

defmodule FR18ACorrectionRereviewProbe do
  defmodule FakeSource do
    @behaviour PramanaFoundry.Observations.Source

    @impl true
    def snapshot(source), do: {:ok, source.snapshot, source.observed_at}

    @impl true
    def fact(source, %{"type" => type} = query) do
      id = query[identity_key(type)]

      case Map.fetch(source.facts, {type, id}) do
        {:ok, fact} -> {:ok, fact, source.observed_at}
        :error -> {:error, :not_found}
      end
    end

    defp identity_key("effect"), do: "effect_id"
    defp identity_key("control"), do: "control_id"
    defp identity_key("inbox"), do: "execution_id"
  end

  def run do
    root =
      Path.join(
        if(File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()),
        "fr18a-correction-rereview-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)

    try do
      corrupt_and_unavailable_boundaries!(root)
      terminal_outcomes!(root)
      whole_envelope_redaction!(root)
      malformed_versions_and_pointer_vocabulary!()
      IO.puts("FR-18A correction rereview: B2-B4/pointers pass; physical-corruption B1 remains")
    after
      File.rm_rf!(root)
    end
  end

  defp corrupt_and_unavailable_boundaries!(root) do
    logical_path = Path.join(root, "logical-corrupt.sqlite3")
    capability = make_ref()
    initialize!(logical_path)

    {:ok, conn} = Sqlite3.open(logical_path, mode: :readwrite)

    :ok =
      Sqlite3.execute(conn, "UPDATE metadata SET value = '2' WHERE key = 'projection_version'")

    :ok = Sqlite3.close(conn)

    logical = start_gateway!(logical_path, capability, "logical-corrupt")

    %{mode: :recovery, reason: {:authority_corrupt, "metadata", "versions", :unsupported_version}} =
      Gateway.status(logical)

    %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
      Observations.query(%Query{include_pointers: false}, logical, capability)

    :ok = GenServer.stop(logical)

    physical_path = Path.join(root, "physical-corrupt.sqlite3")
    initialize!(physical_path)
    {:ok, file} = :file.open(String.to_charlist(physical_path), [:read, :write, :binary, :raw])
    :ok = :file.pwrite(file, 100, :binary.copy(<<0>>, 256))
    :ok = :file.sync(file)
    :ok = :file.close(file)

    physical = start_gateway!(physical_path, capability, "physical-corrupt")
    %{mode: :recovery, reason: reason} = Gateway.status(physical)
    true = is_binary(reason)

    %{status: :unavailable, quality: :unavailable, error_code: :source_unavailable} =
      Observations.query(%Query{include_pointers: false}, physical, capability)

    :ok = GenServer.stop(physical)

    missing = start_gateway!(Path.join(root, "missing.sqlite3"), capability, "missing")

    %{status: :unavailable, quality: :unavailable, error_code: :source_unavailable} =
      Observations.query(%Query{include_pointers: false}, missing, capability)

    :ok = GenServer.stop(missing)
  end

  defp terminal_outcomes!(root) do
    for terminal <- ["succeeded", "failed"] do
      label = "terminal-#{terminal}"
      {gateway, capability} = live_effect!(root, label, "ticket-#{terminal}")

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

      %{status: :ok, quality: :canonical, items: [item]} =
        Observations.query(
          %Query{include_pointers: false, effect_ids: ["effect-1"]},
          gateway,
          capability
        )

      ^terminal = item.fact["status"]

      %{"status" => ^terminal, "receipt_history" => ["unknown", ^terminal]} =
        item.fact["outcome"]

      :ok = GenServer.stop(gateway)
    end

    {gateway, capability} = live_effect!(root, "conflict", "ticket-conflict")

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

    {:ok, %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"}, :committed} =
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

    %{status: :ok, quality: :canonical, items: [item]} =
      Observations.query(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        gateway,
        capability
      )

    "reconciliation_required" = item.fact["status"]

    %{
      "status" => "unknown",
      "reason" => "reconciliation_required",
      "receipt_history" => ["succeeded"]
    } = item.fact["outcome"]

    :ok = GenServer.stop(gateway)
  end

  defp whole_envelope_redaction!(root) do
    secret_ticket = "sk-review-ticket-abcdef12"
    secret_installation = "Bearer review-installation"
    secret_repository = "api_key=review-repository"
    secret_writer = "sk-review-writer-abcdef12"
    path = Path.join(root, "redaction.sqlite3")
    capability = make_ref()

    :ok =
      Gateway.initialize(path,
        installation_id: secret_installation,
        repository_id: secret_repository
      )

    gateway = start_gateway!(path, capability, secret_writer)
    seed_effect!(gateway, capability, secret_ticket, "sol")

    page =
      Observations.query(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        gateway,
        capability
      )

    %{status: :ok, source: source, items: [item]} = page
    "[REDACTED]" = source["installation_id"]
    "[REDACTED]" = source["repository_id"]
    "[REDACTED]" = source["writer_epoch"]
    "[REDACTED]" = item.identity["ticket_id"]
    "[REDACTED]" = item.fact["ticket_id"]
    serialized = inspect(page)
    false = serialized =~ secret_ticket
    false = serialized =~ secret_installation
    false = serialized =~ secret_repository
    false = serialized =~ secret_writer
    :ok = GenServer.stop(gateway)

    observed_at = ~U[2026-09-20 12:00:00Z]
    nested_key = "sk-review-nested-key-abcdef12"
    nested_value = "Bearer review-nested-value"

    facts =
      fake_effect_facts()
      |> put_in(
        [{"effect", "effect-1"}, "profile"],
        %{"outer" => %{nested_key => nested_value}}
      )

    nested_page =
      Observations.query_source(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        {FakeSource, %{source(observed_at) | facts: facts}},
        now: observed_at
      )

    %{status: :ok, items: [nested_item]} = nested_page

    %{"outer" => %{"[REDACTED_KEY]" => "[REDACTED]"}} =
      nested_item.fact["profile"]

    false = inspect(nested_page) =~ nested_key
    false = inspect(nested_page) =~ nested_value
  end

  defp malformed_versions_and_pointer_vocabulary! do
    observed_at = ~U[2026-09-20 12:00:00Z]

    for field <-
          ~w(sql_schema_version protected_schema_version protocol_version event_version projection_version) do
      malformed = put_in(source(observed_at).snapshot[field], nil)

      %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
        Observations.query_source(
          %Query{include_pointers: false},
          {FakeSource, malformed},
          now: observed_at
        )
    end

    for {producer_status, observation_status} <-
          [{"absent", :absent}, {"unavailable", :unavailable}, {"present", :present}] do
      changed =
        put_in(
          source(observed_at).snapshot["pointers"]["accepted_source"]["producer_status"],
          producer_status
        )

      %{status: :ok, quality: :canonical, items: [item | _]} =
        Observations.query_source(%Query{}, {FakeSource, changed}, now: observed_at)

      ^observation_status = item.status
      ^producer_status = item.fact["producer_status"]
    end

    invalid =
      put_in(
        source(observed_at).snapshot["pointers"]["accepted_source"]["producer_status"],
        "available"
      )

    %{status: :corrupt, quality: :corrupt, error_code: :source_corrupt} =
      Observations.query_source(%Query{}, {FakeSource, invalid}, now: observed_at)
  end

  defp live_effect!(root, label, ticket_id) do
    path = Path.join(root, "#{label}.sqlite3")
    capability = make_ref()
    initialize!(path)
    gateway = start_gateway!(path, capability, "writer-epoch-#{label}")
    seed_effect!(gateway, capability, ticket_id, "sol")

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
        "writer_epoch" => "writer-epoch-#{label}"
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
        "writer_epoch" => "writer-epoch-#{label}"
      }
    )

    {gateway, capability}
  end

  defp seed_effect!(gateway, capability, ticket_id, profile) do
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
          "profile" => profile
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
    Gateway.protected_command(gateway, capability, "operator", %{
      "schema_version" => 1,
      "command_id" => command_id,
      "expected_revisions" => expected_revisions,
      "operation" => operation
    })
  end

  defp accept!(gateway, capability, command_id, expected_revisions, operation) do
    {:ok, %{"disposition" => "accepted"}, :committed} =
      protected(gateway, capability, command_id, expected_revisions, operation)
  end

  defp initialize!(path) do
    :ok = Gateway.initialize(path, installation_id: "installation", repository_id: "repository")
  end

  defp start_gateway!(path, capability, writer_epoch) do
    {:ok, gateway} =
      Gateway.start_link(
        path: path,
        protected_capability: capability,
        writer_epoch: writer_epoch
      )

    Process.unlink(gateway)
    gateway
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
        "protected_schema_version" => "1",
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
end

FR18ACorrectionRereviewProbe.run()
