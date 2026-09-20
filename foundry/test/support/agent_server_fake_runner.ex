defmodule PramanaFoundry.AgentServerTest.FakeRunner do
  @moduledoc """
  A Herdr runner that reads its script from an ETS table, making it safe for
  cross-process use (e.g. when an AgentServer GenServer calls Herdr from its own
  process). Each test creates its own ETS table so tests run in parallel.
  """

  @behaviour PramanaFoundry.Herdr.Runner

  @impl true
  def subscription_route_capability(opts) do
    table_name = opts[:ets_table] || :agent_server_test_default

    case :ets.whereis(table_name) do
      :undefined ->
        :enforced

      _table ->
        case :ets.lookup(table_name, :subscription_route_capability) do
          [{:subscription_route_capability, capability}] -> capability
          [] -> :enforced
        end
    end
  end

  @doc "Explicit subscription policy for model-free coordinator fixtures."
  def launch_policy do
    profile_name = "test-subscription"

    profile = %{
      "provider" => "test-provider",
      "account" => "test-account",
      "billing_class" => "subscription",
      "subscription_authorized" => true,
      "premium_authorized" => false,
      "automatic_roles" => ["developer", "reviewer", "pm"],
      "quota_status" => "available",
      "exhausted" => false,
      "model" => "subscription/test-model",
      "allowed_models" => ["subscription/test-model"],
      "approval_mode" => "write",
      "reasoning" => "medium"
    }

    %{
      profiles: %{profile_name => profile},
      role_profiles: %{
        "developer" => profile_name,
        "reviewer" => profile_name,
        "pm" => profile_name
      }
    }
  end

  @doc "Create a named ETS table for this test's scripts."
  def create_table(name) do
    :ets.new(name, [:set, :public, :named_table, write_concurrency: false])
    :ok
  end

  @doc "Install a script function for the given table."
  def install(table_name, script) when is_function(script, 1) do
    :ets.insert(table_name, {:script, script})
    :ok
  end

  @doc "Return the argv list recorded for this table."
  def calls(table_name) do
    :ets.lookup(table_name, :calls)
    |> case do
      [{:calls, list} | _] -> Enum.reverse(list)
      [] -> []
    end
  end

  @doc "Record a call for this table."
  def record_call(table_name, argv) do
    :ets.update_counter(table_name, :call_count, {2, 1}, {:call_count, 0})
    :ets.insert(table_name, {:calls, [argv | calls(table_name)]})
    :ok
  end

  def json(value) do
    {:ok, %{stdout: IO.iodata_to_binary(:json.encode(value)), stderr: "", exit_status: 0}}
  end

  @impl true
  def run(argv, opts) do
    table_name = opts[:ets_table] || :agent_server_test_default
    record_call(table_name, argv)

    case :ets.lookup(table_name, :script) do
      [{:script, script} | _] -> script.(argv)
      [] -> {:error, :no_script_installed}
    end
  end
end
