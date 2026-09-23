defmodule PramanaFoundry.DurableStore.DomainReadCheckTest do
  # decide/3 commit 1: every domain read a plan declares is one Gateway CAS-checks, and
  # expected_domain_revision is the kernel revision of the entity the projections write.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.Workflow.Kernel.Plan

  setup do
    root = Path.join("/private/tmp", "domain-read-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()
    assert :ok = Gateway.initialize(path)

    gateway =
      start_supervised!(
        {Gateway, path: path, protected_capability: capability, writer_epoch: "epoch-A"}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{gateway: gateway, capability: capability}
  end

  @ticket "foundry.ticket.v1"
  @state "foundry.state.v1"

  test "the namespace table matches the kernel's copy" do
    assert Gateway.domain_read_namespaces() == Plan.namespaces()
  end

  test "a plan whose declared reads are all checked commits", ctx do
    assert {:ok, %{"disposition" => "accepted"}, :committed} = submit(ctx, bundle("DR1"))
  end

  test "a declared read missing from expected_revisions is refused", ctx do
    bundle = update_in(bundle("DR2"), ["command", "expected_revisions"], &Map.delete(&1, dep()))
    assert {:error, :domain_read_not_checked} = submit(ctx, bundle)
  end

  test "a declared read whose revision differs from expected_revisions is refused", ctx do
    bundle = put_in(bundle("DR3"), ["command", "expected_revisions", dep()], 4)
    assert {:error, :domain_read_not_checked} = submit(ctx, bundle)
  end

  test "a read-only entity keyed as a projection is refused", ctx do
    bundle =
      update_in(bundle("DR4"), ["command", "expected_revisions"], fn revisions ->
        revisions |> Map.delete(dep()) |> Map.put(key("projection/", @state, "control"), "absent")
      end)

    assert {:error, :domain_read_not_checked} = submit(ctx, bundle)
  end

  test "a read kind with no namespace is refused", ctx do
    bundle =
      update_in(bundle("DR5"), ["plan", "domain_reads"], fn reads ->
        reads ++ [%{"kind" => "pm", "entity_id" => "P1", "revision" => "absent"}]
      end)

    assert {:error, :domain_read_not_checked} = submit(ctx, bundle)
  end

  test "expected_domain_revision must be the written read's revision + 1", ctx do
    bundle = put_in(bundle("DR6"), ["plan", "expected_domain_revision"], 1)
    assert {:error, :expected_domain_revision_mismatch} = submit(ctx, bundle)
  end

  # Two declared reads written leave no single target entity, so no stated
  # expected_domain_revision can match (gateway.ex `expected_domain_revision/1`).
  test "a plan writing two declared reads has no expected_domain_revision", ctx do
    other = "DR7-other"

    bundle =
      bundle("DR7")
      |> put_in(["command", "expected_revisions", key("projection/", @ticket, other)], "absent")
      |> update_in(["plan", "domain_reads"], fn reads ->
        reads ++ [%{"kind" => "ticket", "entity_id" => other, "revision" => "absent"}]
      end)
      |> update_in(["plan", "alternatives", Access.at(0), "proposal"], fn proposal ->
        [event] = proposal["events"]
        [projection] = proposal["projections"]
        event_id = "event-" <> other

        proposal
        |> Map.put("events", [
          event,
          event
          |> Map.put("event_id", event_id)
          |> put_in(["payload", "projection", "entity_id"], other)
        ])
        |> Map.put("projections", [
          projection,
          %{projection | "entity_id" => other, "last_event_id" => event_id}
        ])
      end)

    for revision <- [0, 1] do
      assert {:error, :expected_domain_revision_mismatch} =
               submit(ctx, put_in(bundle, ["plan", "expected_domain_revision"], revision))
    end
  end

  defp submit(ctx, bundle),
    do: Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", bundle)

  defp key(prefix, namespace, id),
    do:
      prefix <>
        Base.url_encode64(namespace, padding: false) <>
        "/" <> Base.url_encode64(id, padding: false)

  defp dep, do: key("dependency/", @state, "control")

  # Writes ticket `id` (absent, so kernel revision 0) and reads the control singleton.
  defp bundle(id) do
    event_id = "event-#{id}"
    value = %{"phase" => "queued"}

    %{
      "schema_version" => 2,
      "actor_id" => "operator",
      "inputs" => %{"recorded_at" => "2026-09-23T00:00:00Z", "transition_id" => id},
      "command" => %{
        "schema_version" => 1,
        "command_id" => id,
        "expected_revisions" => %{key("projection/", @ticket, id) => "absent", dep() => "absent"},
        "type" => "enqueue",
        "target_ids" => %{"ticket_id" => id},
        "payload" => %{}
      },
      "operations" => [],
      "plan" => %{
        "schema_version" => 1,
        "command_id" => id,
        "disposition" => "accepted",
        "reason_code" => nil,
        "expected_domain_revision" => 0,
        "domain_reads" => [
          %{"kind" => "ticket", "entity_id" => id, "revision" => "absent"},
          %{"kind" => "state", "entity_id" => "control", "revision" => "absent"}
        ],
        "protected_operations" => [],
        "bindings" => [],
        "discriminator_kind" => "unconditional_v1",
        "alternatives" => [
          %{
            "discriminator" => "unconditional",
            "proposal" => %{
              "schema_version" => 1,
              "result" => %{"schema_version" => 1, "disposition" => "accepted"},
              "events" => [
                %{
                  "schema_version" => 1,
                  "event_id" => event_id,
                  "type" => "ticket_enqueued",
                  "payload" => %{
                    "projection" => %{
                      "namespace" => @ticket,
                      "entity_id" => id,
                      "revision" => 0,
                      "value" => value
                    }
                  }
                }
              ],
              "projections" => [
                %{
                  "schema_version" => 1,
                  "namespace" => @ticket,
                  "entity_id" => id,
                  "expected_revision" => -1,
                  "revision" => 0,
                  "last_event_id" => event_id,
                  "value" => value
                }
              ],
              "intents" => []
            }
          }
        ]
      }
    }
  end
end
