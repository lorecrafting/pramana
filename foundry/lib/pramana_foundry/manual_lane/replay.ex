defmodule PramanaFoundry.ManualLane.Replay do
  @moduledoc """
  The manual lane's adapter plumbing, moved from `decide_e2e_test.exs` into `lib`
  (`docs/batch-d/THIN-LANE-DESIGN-2026-09-23.md` §3): kernel state rebuilt from the
  committed durable events alone, the prestate reads each staged operation must state,
  and submission. Reads open the store read-only over SQLite (Q2). Nothing here decides.

  `ctx` is `%{gateway, capability, path, writer_epoch}`.
  """

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Database, Gateway, ProtectedPrimitives}
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.{Event, Plan, State}

  @doc """
  Kernel state from the committed durable events: entity kind from the event type, id and
  revision from the projection the event carries, sequence from the store. A committed
  event the kernel refuses means log and kernel disagree, so it raises.
  """
  def state(ctx) do
    {:ok, rows} = read(ctx, "SELECT seq, event FROM events ORDER BY seq", [])
    namespaces = Map.values(Plan.namespaces())

    Enum.reduce(rows, State.new(), fn [seq, bytes], state ->
      event = JSON.decode!(bytes)
      projection = event["payload"]["projection"]

      if event["type"] in Event.types() and projection["namespace"] in namespaces do
        {:ok, kind} = Event.entity_kind(event["type"])

        {:ok, next} =
          WorkflowKernel.apply(state, %{
            "schema_version" => 1,
            "event_id" => event["event_id"],
            "type" => event["type"],
            "sequence" => seq,
            "entity_kind" => kind,
            "entity_id" => projection["entity_id"],
            "entity_revision" => projection["revision"],
            "payload" => Map.delete(event["payload"], "projection")
          })

        next
      else
        state
      end
    end)
  end

  @doc "Whether `command_id` is committed and accepted, as a bundle or a root command."
  def committed?(ctx, command_id) do
    {:ok, rows} =
      read(
        ctx,
        "SELECT disposition FROM atomic_bundles WHERE command_id = ?1 " <>
          "UNION ALL SELECT disposition FROM root_commands WHERE command_id = ?1",
        [command_id]
      )

    ["accepted"] in rows
  end

  @doc "A `decide/3` or `Plan.decision/2` result, submitted as one atomic bundle under `actor`."
  def submit(ctx, %{"command" => command, "plan" => plan}, actor) do
    with {:ok, operations} <-
           prestate(ctx, Enum.map(plan["protected_operations"], & &1["input"])) do
      Gateway.atomic_bundle(ctx.gateway, ctx.capability, actor, %{
        "schema_version" => 2,
        "actor_id" => actor,
        "inputs" => %{
          "recorded_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "transition_id" => command["command_id"]
        },
        "command" => command,
        "operations" => operations,
        "plan" => plan
      })
    end
  end

  @doc "One root protected command under `actor`, stating the prestate reads it requires."
  def root(ctx, actor, command_id, operation) do
    with {:ok, [%{"expected_revisions" => reads}]} <- prestate(ctx, [operation]) do
      Gateway.protected_command(ctx.gateway, ctx.capability, actor, %{
        "schema_version" => 1,
        "command_id" => command_id,
        "expected_revisions" => reads,
        "operation" => operation
      })
    end
  end

  @doc "The protected facts a launch decision reads, with `writer_epoch` from `ctx`."
  def launch_facts(ctx, policy_id, control_id, ledger_id, predecessor) do
    with {:ok, policy} <- query(ctx, %{"type" => "policy", "policy_id" => policy_id}),
         {:ok, control} <- query(ctx, %{"type" => "control", "control_id" => control_id}),
         {:ok, ledger} <-
           query(ctx, %{"type" => "ledger", "ledger_id" => ledger_id, "generation" => 0}) do
      {:ok,
       %{
         "policy" => policy,
         "control" => control,
         "allocation" => ledger,
         "writer_epoch" => ctx.writer_epoch,
         "predecessor_effect_id" => predecessor
       }}
    end
  end

  def query(ctx, query),
    do: Gateway.protected_query(ctx.gateway, ctx.capability, Map.put(query, "schema_version", 1))

  # Each staged operation with the prestate reads Gateway requires, given those before it.
  defp prestate(ctx, operations) do
    with_conn(ctx, fn conn ->
      Enum.reduce_while(operations, {:ok, [], []}, fn op, {:ok, acc, prior} ->
        case ProtectedPrimitives.required_bundle_prestate_revisions(conn, op, Enum.reverse(prior)) do
          {:ok, reads} ->
            entry = %{"schema_version" => 1, "expected_revisions" => reads, "operation" => op}
            {:cont, {:ok, [entry | acc], [op | prior]}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, acc, _prior} -> {:ok, Enum.reverse(acc)}
        error -> error
      end
    end)
  end

  defp read(ctx, sql, params), do: with_conn(ctx, &Database.query(&1, sql, params))

  defp with_conn(ctx, fun) do
    {:ok, conn} = Sqlite3.open(ctx.path, mode: :readonly)

    try do
      fun.(conn)
    after
      Sqlite3.close(conn)
    end
  end
end
