defmodule PramanaFoundry.Board.InspectionTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Board.Inspection
  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Status.Report

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"

  setup do
    revision_key = :pramana_runtime_implementation_revision
    previous_revision = Application.fetch_env(:pramana_foundry, revision_key)
    previous_env = Map.new(~w(SECRET_API_KEY OPENAI_API_KEY), &{&1, System.get_env(&1)})

    on_exit(fn ->
      case previous_revision do
        {:ok, value} -> Application.put_env(:pramana_foundry, revision_key, value)
        :error -> Application.delete_env(:pramana_foundry, revision_key)
      end

      for {key, value} <- previous_env do
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end
    end)

    Report.set_runtime_implementation_revision(@base_rev)
    :ok = Coordinator.reset(accepted_revision: @base_rev)
    :ok
  end

  test "inspection status returns sanitized BEAM and coordinator metrics" do
    st = Inspection.status()

    assert st["sanitized"] == true
    assert is_binary(st["node"])
    assert is_binary(st["otp_release"])
    assert is_binary(st["elixir_version"])
    assert is_integer(st["process_count"]) and st["process_count"] > 0
    assert is_integer(st["process_limit"]) and st["process_limit"] > 0
    assert is_integer(st["uptime_seconds"])

    mem = st["memory"]
    assert is_integer(mem["total_bytes"]) and mem["total_bytes"] > 0
    assert is_integer(mem["processes_bytes"]) and mem["processes_bytes"] > 0

    coord = st["coordinator"]
    assert coord["alive?"] == true
    assert coord["accepted_revision"] == @base_rev
    assert coord["runtime_implementation_revision"] == @base_rev
    assert coord["revisions_match?"] == true
    assert coord["active_workers_count"] == 0
    assert coord["queue_length"] == 0
  end

  test "inspection status does not expose secrets, credentials, or environment variables" do
    System.put_env("SECRET_API_KEY", "super-secret-token-12345")
    System.put_env("OPENAI_API_KEY", "sk-secret-credentials")

    st = Inspection.status()
    raw_str = inspect(st)

    refute String.contains?(raw_str, "super-secret-token-12345")
    refute String.contains?(raw_str, "sk-secret-credentials")
    refute Map.has_key?(st, "env")
    refute Map.has_key?(st, "environment")
  end

  test "attach instructions document strictly local access without public ports" do
    inst = Inspection.attach_instructions()

    assert is_binary(inst["local_remsh"])
    assert String.contains?(inst["local_remsh"], "127.0.0.1")
    assert is_binary(inst["local_socket"])
    assert is_list(inst["security_guarantees"])
    assert length(inst["security_guarantees"]) == 3

    # Security guarantees explicitly verified
    assert Enum.any?(inst["security_guarantees"], &String.contains?(&1, "127.0.0.1"))

    assert Enum.any?(
             inst["security_guarantees"],
             &String.contains?(&1, "No insecure network listeners")
           )

    assert Enum.any?(inst["security_guarantees"], &String.contains?(&1, "No environment secrets"))
  end

  test "formatted status text presents system summary clearly" do
    text = Inspection.formatted_status()

    assert String.contains?(text, "=== PramanaFoundry BEAM System Status ===")
    assert String.contains?(text, "Memory Total:")
    assert String.contains?(text, "Coordinator:")
    assert String.contains?(text, "Accepted Rev:")
    assert String.contains?(text, "Runtime Rev:")
    assert String.contains?(text, "Revisions Match: yes (in sync)")
    assert String.contains?(text, "=== Local Attach Instructions ===")
    assert String.contains?(text, "=== Security Guarantees ===")
  end

  test "inspection detects revision mismatch" do
    other_rev = "1111222233334444555566667777888899990000"
    Report.set_runtime_implementation_revision(other_rev)

    st = Inspection.status()
    assert st["coordinator"]["revisions_match?"] == false

    text = Inspection.format()
    assert String.contains?(text, "MISMATCH")
  end
end
