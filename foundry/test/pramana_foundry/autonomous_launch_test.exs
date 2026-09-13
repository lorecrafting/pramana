Code.require_file("../support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.AutonomousLaunchTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.AgentServer
  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Coordinator.State
  alias PramanaFoundry.Coordinator.Tick
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.Herdr.Runner
  alias PramanaFoundry.LaunchEligibility

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit "2222333344445555666677778888999900001111"
  @check ["sh", "-c", "true"]
  @profile_name "subscription"
  @profiles %{
    @profile_name => %{
      "provider" => "test-provider",
      "account" => "test-account",
      "billing_class" => "subscription",
      "subscription_authorized" => true,
      "premium_authorized" => false,
      "automatic_roles" => ["developer", "reviewer", "pm"],
      "quota_status" => "available",
      "model" => "subscription/exact-model",
      "allowed_models" => ["subscription/exact-model"],
      "approval_mode" => "write",
      "reasoning" => "medium"
    }
  }

  @pane_split_result %{
    "result" => %{
      "pane" => %{
        "pane_id" => "pane-fr01",
        "terminal_id" => "term-fr01",
        "status" => "running"
      }
    }
  }

  @ready_agent %{
    "name" => "fr01-agent",
    "pane_id" => "pane-fr01",
    "terminal_id" => "term-fr01",
    "agent_status" => "idle",
    "agent_session" => "sess-fr01",
    "agent" => "omp"
  }

  setup do
    if is_nil(Process.whereis(PramanaFoundry.AssignmentSupervisor)) do
      start_supervised!(
        {DynamicSupervisor,
         name: PramanaFoundry.AssignmentSupervisor, strategy: :one_for_one, max_children: 10}
      )
    end

    previous_herdr_env = System.get_env("HERDR_ENV")
    System.put_env("HERDR_ENV", "1")

    table = :"fr01_#{System.unique_integer([:positive])}"
    :ets.new(table, [:set, :public, :named_table])
    install_success_script(table)

    tmp_dir = Path.join(System.tmp_dir!(), "pramana-fr01-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      restore_env("HERDR_ENV", previous_herdr_env)

      try do
        :ets.delete(table)
      rescue
        ArgumentError -> :ok
      end

      File.rm_rf!(tmp_dir)
    end)

    %{table: table, tmp_dir: tmp_dir}
  end

  test "eligibility fails closed for every role and each disallowed profile state" do
    for role <- [:developer, :reviewer, :pm],
        {name, profiles, workflow_state, expected_tag} <- disallowed_cases() do
      assert {:error, reason} =
               LaunchEligibility.resolve(profiles, name, role, workflow_state, now: 1_000)

      assert elem(reason, 0) == expected_tag
    end
  end

  test "the explicit subscription profile is eligible for each autonomous role" do
    for role <- [:developer, :reviewer, :pm] do
      assert {:ok, profile} =
               LaunchEligibility.resolve(@profiles, @profile_name, role, %{}, now: 1_000)

      assert profile.name == @profile_name
      assert profile.role == to_string(role)
      assert profile.billing_class == "subscription"
      assert profile.provider == "test-provider"
      assert profile.model == "subscription/exact-model"
    end

    expired = %{
      "provider_cooldowns" => %{@profile_name => %{"until_epoch" => 999}}
    }

    assert {:ok, _profile} =
             LaunchEligibility.resolve(@profiles, @profile_name, :developer, expired, now: 1_000)
  end

  test "malformed nested policy always returns a stable blocked reason" do
    for {_label, profiles, workflow_state} <- malformed_policy_cases(),
        role <- [:developer, :reviewer, :pm] do
      assert {:error, reason} =
               LaunchEligibility.resolve(
                 profiles,
                 @profile_name,
                 role,
                 workflow_state,
                 now: 1_000
               )

      assert LaunchEligibility.reason(reason) =~ ~r/(invalid|missing)/
    end
  end

  test "nil and arbitrary unknown profile keys return an unambiguous denial" do
    for {_label, profiles} <- unknown_profile_key_cases() do
      assert {:error, {:invalid_profile_field, @profile_name, "unknown field"} = reason} =
               LaunchEligibility.resolve(
                 profiles,
                 @profile_name,
                 :developer,
                 %{},
                 now: 1_000
               )

      assert LaunchEligibility.reason(reason) ==
               ~s(profile "subscription" has invalid unknown field configuration)
    end
  end

  test "public policy selectors are total over improper and nested Elixir terms", ctx do
    malformed_terms = [false, :invalid, <<255>>, ["value" | :invalid], %URI{}]

    for term <- malformed_terms do
      assert {:error, _reason} =
               LaunchEligibility.select_profile(nil, term, :developer)

      assert {:error, _reason} =
               LaunchEligibility.resolve(term, @profile_name, :developer, %{}, now: 1_000)

      assert {:error, _reason} =
               LaunchEligibility.resolve(
                 @profiles,
                 @profile_name,
                 :developer,
                 %{"provider_cooldowns" => term},
                 now: 1_000
               )
    end

    assert {:error, _reason} =
             LaunchEligibility.resolve(
               @profiles,
               @profile_name,
               :developer,
               %{},
               [{:now, 1_000} | :invalid]
             )

    assert {:stop, {:launch_blocked, "invalid explicit profile selection for developer"}} =
             AgentServer.init(
               task_id: "T-NEWLINE-PROFILE",
               run_id: "run-newline-profile",
               role: :developer,
               checkout: "/tmp/fr01-checkout",
               adapter: adapter(),
               coordinator_pid: self(),
               profile: "subscription\n",
               launch_profiles: @profiles,
               launch_state: %{},
               launch_now: 1_000,
               herdr_opts: [ets_table: ctx.table]
             )

    assert calls(ctx.table) == []
  end

  test "malformed policy blocks Tick, both reviewer paths, and AgentServer without calls", ctx do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      for {label, profiles, workflow_state} <- malformed_policy_cases() do
        clear_calls(ctx.table)
        task_id = "T-MALFORMED-#{label}"
        queued = Map.merge(queued_state(task_id, @profile_name), workflow_state)
        unknown_key_case? = String.starts_with?(label, "unknown-")
        unknown_reason = ~s(profile "subscription" has invalid unknown field configuration)

        {tick_state, %{}, [{:launch_blocked, ^task_id, tick_reason}]} =
          Tick.process_queue(
            [task_id],
            queued,
            %{},
            adapter(),
            1_000,
            self(),
            Path.join(ctx.tmp_dir, "#{task_id}-tick.jsonl"),
            nil,
            3,
            profiles: profiles,
            now: 1_000,
            herdr_opts: [ets_table: ctx.table]
          )

        assert is_binary(tick_reason)
        assert get_in(tick_state, ["assignments", task_id, "status"]) == "blocked"

        if unknown_key_case? do
          assert tick_reason == unknown_reason

          assert get_in(tick_state, ["assignments", task_id, "blocker"]) ==
                   "automatic developer launch blocked: #{unknown_reason}"
        end

        initial_state = Map.merge(dispatched_state(task_id, @profile_name), workflow_state)

        assert {:reply, {:ok, _assignment}, initial_data} =
                 Coordinator.handle_call(
                   {:receive_handoff, task_id, handoff(task_id), [skip_git_checks: true]},
                   {self(), make_ref()},
                   coordinator_data(initial_state, profiles, ctx)
                 )

        assert get_in(initial_data, [:state, "assignments", task_id, "status"]) == "blocked"

        if unknown_key_case? do
          assert get_in(initial_data, [:state, "assignments", task_id, "blocker"]) ==
                   "automatic reviewer launch blocked: #{unknown_reason}"
        end

        {:ok, _assignment, retry_state} =
          State.receive_handoff(
            dispatched_state(task_id, @profile_name),
            task_id,
            handoff(task_id),
            skip_git_checks: true
          )

        retry_state = Map.merge(retry_state, workflow_state)

        assert {:reply, {:error, _reason}, retry_data} =
                 Coordinator.handle_call(
                   {:receive_review, task_id, invalid_review(task_id), [skip_git_checks: true]},
                   {self(), make_ref()},
                   coordinator_data(retry_state, profiles, ctx)
                 )

        assert get_in(retry_data, [:state, "assignments", task_id, "status"]) == "blocked"

        if unknown_key_case? do
          assert get_in(retry_data, [:state, "assignments", task_id, "blocker"]) ==
                   "automatic reviewer launch blocked: #{unknown_reason}"
        end

        assert {:error, {:launch_blocked, server_reason}} =
                 AgentServer.start_link(
                   task_id: task_id,
                   run_id: "run-malformed",
                   role: :pm,
                   checkout: "/tmp/fr01-checkout",
                   adapter: adapter(),
                   coordinator_pid: self(),
                   profile: @profile_name,
                   launch_profiles: profiles,
                   launch_state: workflow_state,
                   launch_now: 1_000,
                   herdr_opts: [ets_table: ctx.table]
                 )

        assert is_binary(server_reason)
        if unknown_key_case?, do: assert(server_reason == unknown_reason)
        assert calls(ctx.table) == []
      end
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  test "malformed role mappings and explicit false selections never fall back", ctx do
    for mapping <- [false, [], %URI{}, %{"developer" => false}, %{developer: @profile_name}] do
      assert {:error, reason} =
               LaunchEligibility.select_profile(nil, mapping, :developer)

      assert LaunchEligibility.reason(reason) =~ "invalid automatic role profile mapping"
    end

    for selection <- [false, " bad-profile", "bad-profile\n", "default"] do
      assert {:error, explicit_reason} =
               LaunchEligibility.select_profile(
                 selection,
                 %{"developer" => @profile_name},
                 :developer
               )

      assert LaunchEligibility.reason(explicit_reason) ==
               "invalid explicit profile selection for developer"
    end

    state = queued_state("T-BAD-MAPPING", nil)

    {blocked, %{}, [{:launch_blocked, "T-BAD-MAPPING", reason}]} =
      Tick.process_queue(
        ["T-BAD-MAPPING"],
        state,
        %{},
        adapter(),
        1_000,
        self(),
        Path.join(ctx.tmp_dir, "mapping.jsonl"),
        nil,
        3,
        profiles: @profiles,
        role_profiles: [],
        now: 1_000,
        herdr_opts: [ets_table: ctx.table]
      )

    assert reason =~ "invalid automatic role profile mapping"
    assert get_in(blocked, ["assignments", "T-BAD-MAPPING", "status"]) == "blocked"
    assert calls(ctx.table) == []

    struct_task = "T-STRUCT-MAPPING"

    {struct_blocked, %{}, [{:launch_blocked, ^struct_task, struct_reason}]} =
      Tick.process_queue(
        [struct_task],
        queued_state(struct_task, nil),
        %{},
        adapter(),
        1_000,
        self(),
        Path.join(ctx.tmp_dir, "struct-mapping.jsonl"),
        nil,
        3,
        profiles: @profiles,
        role_profiles: %URI{},
        now: 1_000,
        herdr_opts: [ets_table: ctx.table]
      )

    assert struct_reason =~ "expected a string-keyed plain map"
    assert get_in(struct_blocked, ["assignments", struct_task, "status"]) == "blocked"
    assert calls(ctx.table) == []

    for {suffix, selection} <- [
          {"false", false},
          {"whitespace", " bad-profile"},
          {"newline", "bad-profile\n"}
        ] do
      task_id = "T-BAD-PROFILE-#{suffix}"

      selection_state =
        queued_state(task_id, nil)
        |> put_in(["assignments", task_id, "ticket", "profile"], selection)

      {selection_blocked, %{}, [{:launch_blocked, ^task_id, selection_reason}]} =
        Tick.process_queue(
          [task_id],
          selection_state,
          %{},
          adapter(),
          1_000,
          self(),
          Path.join(ctx.tmp_dir, "#{task_id}.jsonl"),
          nil,
          3,
          profiles: @profiles,
          role_profiles: %{"developer" => @profile_name},
          now: 1_000,
          herdr_opts: [ets_table: ctx.table]
        )

      assert selection_reason == "invalid explicit profile selection for developer"
      assert get_in(selection_blocked, ["assignments", task_id, "status"]) == "blocked"
      assert calls(ctx.table) == []
    end

    for {suffix, mapping, explicit} <- [
          {"container", [], nil},
          {"struct", %URI{}, nil},
          {"explicit", %{"reviewer" => @profile_name}, false},
          {"noncanonical", %{"reviewer" => @profile_name}, " bad-profile"},
          {"newline", %{"reviewer" => "bad-profile\n"}, nil}
        ] do
      task_id = "T-BAD-REVIEWER-MAPPING-#{suffix}"
      state = dispatched_state(task_id, explicit)
      data = %{coordinator_data(state, @profiles, ctx) | launch_role_profiles: mapping}

      assert {:reply, {:ok, _assignment}, initial_data} =
               Coordinator.handle_call(
                 {:receive_handoff, task_id, handoff(task_id), [skip_git_checks: true]},
                 {self(), make_ref()},
                 data
               )

      assert get_in(initial_data, [:state, "assignments", task_id, "status"]) == "blocked"

      {:ok, _assignment, retry_state} =
        State.receive_handoff(state, task_id, handoff(task_id), skip_git_checks: true)

      retry_data =
        %{coordinator_data(retry_state, @profiles, ctx) | launch_role_profiles: mapping}

      assert {:reply, {:error, _reason}, returned} =
               Coordinator.handle_call(
                 {:receive_review, task_id, invalid_review(task_id), [skip_git_checks: true]},
                 {self(), make_ref()},
                 retry_data
               )

      assert get_in(returned, [:state, "assignments", task_id, "status"]) == "blocked"
      assert calls(ctx.table) == []
    end
  end

  test "AgentServer independently guards developer, reviewer, and PM roles", ctx do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      for role <- [:developer, :reviewer, :pm],
          {profile, profiles, launch_state, _expected_tag} <- disallowed_cases() do
        assert {:error, {:launch_blocked, reason}} =
                 AgentServer.start_link(
                   task_id: "T-SERVER-GUARD-#{role}",
                   run_id: "run-guard",
                   role: role,
                   checkout: "/tmp/fr01-checkout",
                   adapter: adapter(),
                   coordinator_pid: self(),
                   profile: profile,
                   launch_profiles: profiles,
                   launch_state: launch_state,
                   launch_now: 1_000,
                   herdr_opts: [ets_table: ctx.table]
                 )

        assert is_binary(reason) and reason != ""
        assert calls(ctx.table) == []
      end
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  test "unsupported, missing, and noncanonical backend capabilities fail closed", ctx do
    system_adapter = Adapter.new(Runner.System)
    missing_adapter = Adapter.new(URI)

    refute Adapter.subscription_route_enforced?(system_adapter)
    refute Adapter.subscription_route_enforced?(missing_adapter)

    assert {:error, :subscription_route_not_enforced} =
             Adapter.require_subscription_route(system_adapter)

    :ets.insert(ctx.table, {:subscription_route_capability, true})
    refute Adapter.subscription_route_enforced?(adapter(), ets_table: ctx.table)

    for capability <- [true, :unsupported] do
      :ets.insert(ctx.table, {:subscription_route_capability, capability})
      task_id = "T-CAPABILITY-#{capability}"

      {blocked, %{}, [{:launch_blocked, ^task_id, reason}]} =
        Tick.process_queue(
          [task_id],
          queued_state(task_id, @profile_name),
          %{},
          adapter(),
          1_000,
          self(),
          Path.join(ctx.tmp_dir, "#{task_id}.jsonl"),
          nil,
          3,
          profiles: @profiles,
          now: 1_000,
          herdr_opts: [ets_table: ctx.table]
        )

      assert reason == "launch backend does not enforce a subscription-only route"
      assert get_in(blocked, ["assignments", task_id, "status"]) == "blocked"
      assert calls(ctx.table) == []
    end
  end

  test "real System backend blocks an otherwise eligible AgentServer before launch" do
    previous_herdr_env = System.get_env("HERDR_ENV")
    previous_trap_exit = Process.flag(:trap_exit, true)
    System.put_env("HERDR_ENV", "1")

    try do
      assert {:error, {:launch_blocked, reason}} =
               AgentServer.start_link(
                 task_id: "T-SYSTEM-BLOCK",
                 run_id: "run-system-block",
                 role: :developer,
                 checkout: "/tmp/fr01-checkout",
                 adapter: Adapter.new(Runner.System),
                 coordinator_pid: self(),
                 profile: @profile_name,
                 launch_profiles: @profiles,
                 launch_state: %{},
                 launch_now: 1_000
               )

      assert reason == "launch backend does not enforce a subscription-only route"
    after
      restore_env("HERDR_ENV", previous_herdr_env)
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  test "workflow state structs are rejected by resolver and AgentServer", ctx do
    assert {:error, reason} =
             LaunchEligibility.resolve(@profiles, @profile_name, :developer, %URI{}, now: 1_000)

    assert LaunchEligibility.reason(reason) ==
             "invalid provider cooldown policy: expected workflow state plain map"

    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      assert {:error, {:launch_blocked, server_reason}} =
               AgentServer.start_link(
                 task_id: "T-WORKFLOW-STRUCT",
                 run_id: "run-workflow-struct",
                 role: :developer,
                 checkout: "/tmp/fr01-checkout",
                 adapter: adapter(),
                 coordinator_pid: self(),
                 profile: @profile_name,
                 launch_profiles: @profiles,
                 launch_state: %URI{},
                 launch_now: 1_000,
                 herdr_opts: [ets_table: ctx.table]
               )

      assert server_reason ==
               "invalid provider cooldown policy: expected workflow state plain map"

      assert calls(ctx.table) == []
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  test "unsupported backend blocks initial and retry reviewer boundaries without calls", ctx do
    :ets.insert(ctx.table, {:subscription_route_capability, :unsupported})

    for path <- [:initial, :retry] do
      task_id = "T-REVIEW-CAPABILITY-#{path}"
      dispatched = dispatched_state(task_id, @profile_name)

      data =
        case path do
          :initial ->
            coordinator_data(dispatched, @profiles, ctx)

          :retry ->
            {:ok, _assignment, handoff_state} =
              State.receive_handoff(
                dispatched,
                task_id,
                handoff(task_id),
                skip_git_checks: true
              )

            coordinator_data(handoff_state, @profiles, ctx)
        end

      returned =
        case path do
          :initial ->
            assert {:reply, {:ok, _assignment}, returned} =
                     Coordinator.handle_call(
                       {:receive_handoff, task_id, handoff(task_id), [skip_git_checks: true]},
                       {self(), make_ref()},
                       data
                     )

            returned

          :retry ->
            assert {:reply, {:error, _reason}, returned} =
                     Coordinator.handle_call(
                       {:receive_review, task_id, invalid_review(task_id),
                        [skip_git_checks: true]},
                       {self(), make_ref()},
                       data
                     )

            returned
        end

      assert get_in(returned, [:state, "assignments", task_id, "status"]) == "blocked"

      assert get_in(returned, [:state, "assignments", task_id, "blocker"]) =~
               "does not enforce a subscription-only route"

      assert calls(ctx.table) == []
    end
  end

  test "developer Tick blocks before AgentServer or adapter launch when profile is absent", ctx do
    state = queued_state("T-DEV-BLOCK", nil)

    {new_state, registry, log} =
      Tick.process_queue(
        ["T-DEV-BLOCK"],
        state,
        %{},
        adapter(),
        1_000,
        self(),
        Path.join(ctx.tmp_dir, "events.jsonl"),
        nil,
        3,
        profiles: @profiles,
        now: 1_000,
        herdr_opts: [ets_table: ctx.table]
      )

    assert registry == %{}
    assert [{:launch_blocked, "T-DEV-BLOCK", reason}] = log
    assert reason =~ "no subscription profile configured"
    assert get_in(new_state, ["assignments", "T-DEV-BLOCK", "status"]) == "blocked"
    assert get_in(new_state, ["assignments", "T-DEV-BLOCK", "blocker"]) =~ reason
    assert calls(ctx.table) == []
  end

  test "developer Tick launches with the exact eligible profile argv", ctx do
    state = queued_state("T-DEV-ALLOW", @profile_name)

    {new_state, registry, log} =
      Tick.process_queue(
        ["T-DEV-ALLOW"],
        state,
        %{},
        adapter(),
        1_000,
        self(),
        Path.join(ctx.tmp_dir, "events.jsonl"),
        nil,
        3,
        profiles: @profiles,
        now: 1_000,
        herdr_opts: [ets_table: ctx.table]
      )

    assert [{:launched, "T-DEV-ALLOW"}] = log

    assert get_in(new_state, ["assignments", "T-DEV-ALLOW", "configured_profile"]) ==
             @profile_name

    assert_receive {:agent_launched, "T-DEV-ALLOW", :ok, _info}, 2_000
    assert_profile_argv(ctx.table)
    terminate_registered(registry)
  end

  test "OMP argv binds the configured account and reasoning", ctx do
    routes = [
      {"account-a", "low"},
      {"account-b", "xhigh"}
    ]

    for {account, reasoning} <- routes do
      clear_calls(ctx.table)
      task_id = "T-ROUTE-#{account}"

      profiles =
        @profiles
        |> put_in([@profile_name, "account"], account)
        |> put_in([@profile_name, "reasoning"], reasoning)

      {_state, registry, [{:launched, ^task_id}]} =
        Tick.process_queue(
          [task_id],
          queued_state(task_id, @profile_name),
          %{},
          adapter(),
          1_000,
          self(),
          Path.join(ctx.tmp_dir, "#{task_id}.jsonl"),
          nil,
          3,
          profiles: profiles,
          now: 1_000,
          herdr_opts: [ets_table: ctx.table]
        )

      assert_receive {:agent_launched, ^task_id, :ok, _info}, 2_000
      start_argv = Enum.find(calls(ctx.table), &match?(["herdr", "agent", "start" | _], &1))
      assert argv_value(start_argv, "--profile") == account
      assert argv_value(start_argv, "--provider") == "test-provider"
      assert argv_value(start_argv, "--thinking") == reasoning
      assert argv_value(start_argv, "--model") == "subscription/exact-model"
      terminate_registered(registry)
    end
  end

  test "subscription labels cannot authorize a model outside the explicit allow-list", ctx do
    profiles = put_in(@profiles, [@profile_name, "model"], "openrouter/deepseek-v4")
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      {blocked, %{}, [{:launch_blocked, "T-MODEL-MISMATCH", tick_reason}]} =
        Tick.process_queue(
          ["T-MODEL-MISMATCH"],
          queued_state("T-MODEL-MISMATCH", @profile_name),
          %{},
          adapter(),
          1_000,
          self(),
          Path.join(ctx.tmp_dir, "model-mismatch.jsonl"),
          nil,
          3,
          profiles: profiles,
          now: 1_000,
          herdr_opts: [ets_table: ctx.table]
        )

      assert tick_reason =~ "does not allow configured model"
      assert get_in(blocked, ["assignments", "T-MODEL-MISMATCH", "status"]) == "blocked"

      assert {:error, {:launch_blocked, reason}} =
               AgentServer.start_link(
                 task_id: "T-MODEL-MISMATCH",
                 run_id: "run-model-mismatch",
                 role: :developer,
                 checkout: "/tmp/fr01-checkout",
                 adapter: adapter(),
                 coordinator_pid: self(),
                 profile: @profile_name,
                 launch_profiles: profiles,
                 launch_state: %{},
                 launch_now: 1_000,
                 herdr_opts: [ets_table: ctx.table]
               )

      assert reason =~ "does not allow configured model"
      assert calls(ctx.table) == []
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  test "initial reviewer launch blocks on paid profile and launches on subscription profile",
       ctx do
    paid_profiles =
      put_in(@profiles, [@profile_name, "billing_class"], "paid")
      |> put_in([@profile_name, "premium_authorized"], true)

    for {profiles, expected} <- [{paid_profiles, :blocked}, {@profiles, :launched}] do
      clear_calls(ctx.table)
      task_id = "T-INITIAL-#{expected}"
      state = dispatched_state(task_id, @profile_name)
      data = coordinator_data(state, profiles, ctx)

      assert {:reply, {:ok, _assignment}, returned} =
               Coordinator.handle_call(
                 {:receive_handoff, task_id, handoff(task_id), [skip_git_checks: true]},
                 {self(), make_ref()},
                 data
               )

      case expected do
        :blocked ->
          assert get_in(returned, [:state, "assignments", task_id, "status"]) == "blocked"

          assert get_in(returned, [:state, "assignments", task_id, "blocker"]) =~
                   "not authorized for subscription billing"

          assert calls(ctx.table) == []

        :launched ->
          assert_receive {:agent_launched, ^task_id, :ok, _info}, 2_000
          assert_profile_argv(ctx.table)
          terminate_registered(returned.agent_registry)
      end
    end
  end

  test "reviewer blocks survive retained developer timeout, completion, and crash", ctx do
    paid_profiles = put_in(@profiles, [@profile_name, "billing_class"], "paid")

    messages = [
      {:agent_launched, :ok},
      {:agent_launched, {:error, :agent_start_failed, :late_failure}},
      {:agent_completed, :review_timeout},
      {:agent_completed, {:handoff, :ok}},
      {:agent_crashed, :developer_exit}
    ]

    for {kind, reason} <- messages do
      clear_calls(ctx.table)
      task_id = "T-BLOCK-SURVIVES-#{kind}-#{inspect(reason)}"
      data = coordinator_data(dispatched_state(task_id, @profile_name), paid_profiles, ctx)

      assert {:reply, {:ok, _assignment}, blocked_data} =
               Coordinator.handle_call(
                 {:receive_handoff, task_id, handoff(task_id), [skip_git_checks: true]},
                 {self(), make_ref()},
                 data
               )

      blocked_assignment = get_in(blocked_data, [:state, "assignments", task_id])
      assert blocked_assignment["status"] == "blocked"
      assert blocked_assignment["blocked_role"] == "reviewer"
      assert blocked_assignment["role"] == "developer"
      assert is_map(blocked_assignment["handoff"])
      assert blocked_assignment["blocker"] =~ "subscription billing"

      message =
        case kind do
          :agent_launched when reason == :ok ->
            {kind, task_id, :ok, %{pane_id: "late-pane", agent_name: "late-agent"}}

          :agent_launched ->
            {kind, task_id, reason, %{}}

          :agent_completed ->
            {kind, task_id, "developer-run", reason, %{}}

          :agent_crashed ->
            {kind, task_id, "developer-run", reason, %{pane_id: "pane-fr01"}}
        end

      assert {:noreply, after_message} =
               Coordinator.handle_info(
                 message,
                 %{blocked_data | agent_registry: %{task_id => self()}}
               )

      assert get_in(after_message, [:state, "assignments", task_id]) == blocked_assignment
      assert after_message.agent_registry == %{}

      {after_tick, %{}, [{:skipped, ^task_id, "blocked"}]} =
        Tick.process_queue(
          [task_id],
          after_message.state,
          %{},
          adapter(),
          1_000,
          self(),
          Path.join(ctx.tmp_dir, "#{task_id}-after.jsonl"),
          nil,
          3,
          profiles: @profiles,
          now: 1_000,
          herdr_opts: [ets_table: ctx.table]
        )

      assert get_in(after_tick, ["assignments", task_id]) == blocked_assignment
      assert calls(ctx.table) == []
    end
  end

  test "reviewer retry rechecks cooldown and uses the eligible profile", ctx do
    for expected <- [:blocked, :launched] do
      clear_calls(ctx.table)
      task_id = "T-REVIEW-RETRY-#{expected}"
      dispatched = dispatched_state(task_id, @profile_name)

      {:ok, _assignment, handoff_state} =
        State.receive_handoff(dispatched, task_id, handoff(task_id), skip_git_checks: true)

      launch_state =
        if expected == :blocked do
          put_in(
            handoff_state,
            ["provider_cooldowns", @profile_name],
            %{"until_epoch" => 2_000}
          )
        else
          handoff_state
        end

      data = coordinator_data(launch_state, @profiles, ctx)

      assert {:reply, {:error, _reason}, returned} =
               Coordinator.handle_call(
                 {:receive_review, task_id, invalid_review(task_id), [skip_git_checks: true]},
                 {self(), make_ref()},
                 data
               )

      case expected do
        :blocked ->
          assert get_in(returned, [:state, "assignments", task_id, "status"]) == "blocked"

          assert get_in(returned, [:state, "assignments", task_id, "blocker"]) =~
                   "active cooldown"

          assert calls(ctx.table) == []

        :launched ->
          assert_receive {:agent_launched, ^task_id, :ok, _info}, 2_000
          assert_profile_argv(ctx.table)
          terminate_registered(returned.agent_registry)
      end
    end
  end

  defp queued_state(task_id, profile) do
    ticket = ticket(task_id, profile)
    {:ok, state} = State.enqueue_ticket(State.new(accepted_revision: @base_rev), ticket)
    state
  end

  defp disallowed_cases do
    paid =
      put_in(@profiles, [@profile_name], %{
        @profiles[@profile_name]
        | "billing_class" => "paid",
          "premium_authorized" => false
      })

    manual = put_in(@profiles, [@profile_name, "billing_class"], "manual")
    premium = put_in(@profiles, [@profile_name, "premium_authorized"], true)
    exhausted = put_in(@profiles, [@profile_name, "quota_status"], "exhausted")
    exhausted_flag = put_in(@profiles, [@profile_name, "exhausted"], true)
    unknown_quota = put_in(@profiles, [@profile_name, "quota_status"], "unknown")
    disallowed = put_in(@profiles, [@profile_name, "automatic_roles"], [])

    cooled = %{
      "provider_cooldowns" => %{@profile_name => %{"until_epoch" => 2_000}}
    }

    [
      {nil, %{}, %{}, :profile_required},
      {@profile_name, paid, %{}, :profile_not_subscription_authorized},
      {@profile_name, manual, %{}, :profile_not_subscription_authorized},
      {@profile_name, premium, %{}, :profile_not_subscription_authorized},
      {@profile_name, disallowed, %{}, :profile_not_authorized_for_role},
      {@profile_name, exhausted, %{}, :profile_quota_unavailable},
      {@profile_name, exhausted_flag, %{}, :profile_quota_unavailable},
      {@profile_name, unknown_quota, %{}, :profile_quota_unavailable},
      {@profile_name, @profiles, cooled, :profile_cooldown_active}
    ]
  end

  defp malformed_policy_cases do
    base_cases = [
      {"subscription-boolean",
       put_in(@profiles, [@profile_name, "subscription_authorized"], "true"), %{}},
      {"premium-boolean", put_in(@profiles, [@profile_name, "premium_authorized"], "true"), %{}},
      {"exhausted-boolean", put_in(@profiles, [@profile_name, "exhausted"], "true"), %{}},
      {"roles-shape", put_in(@profiles, [@profile_name, "automatic_roles"], false), %{}},
      {"roles-enum", put_in(@profiles, [@profile_name, "automatic_roles"], ["operator"]), %{}},
      {"roles-improper",
       put_in(@profiles, [@profile_name, "automatic_roles"], ["developer" | :invalid]), %{}},
      {"roles-nested-improper",
       put_in(@profiles, [@profile_name, "automatic_roles"], [["developer" | :invalid]]), %{}},
      {"quota-shape", put_in(@profiles, [@profile_name, "quota_status"], %{}), %{}},
      {"model-list", put_in(@profiles, [@profile_name, "allowed_models"], false), %{}},
      {"model-list-improper",
       put_in(
         @profiles,
         [@profile_name, "allowed_models"],
         ["subscription/exact-model" | :invalid]
       ), %{}},
      {"model-list-nested-improper",
       put_in(
         @profiles,
         [@profile_name, "allowed_models"],
         [["subscription/exact-model" | :invalid]]
       ), %{}},
      {"reasoning-enum", put_in(@profiles, [@profile_name, "reasoning"], "ultra"), %{}},
      {"approval-enum", put_in(@profiles, [@profile_name, "approval_mode"], "explicit"), %{}},
      {"billing-enum", put_in(@profiles, [@profile_name, "billing_class"], "unknown"), %{}},
      {"required-empty", put_in(@profiles, [@profile_name, "account"], ""), %{}},
      {"account-whitespace", put_in(@profiles, [@profile_name, "account"], "   "), %{}},
      {"account-newline", put_in(@profiles, [@profile_name, "account"], "test-account\n"), %{}},
      {"account-invalid-utf8", put_in(@profiles, [@profile_name, "account"], <<255>>), %{}},
      {"account-default", put_in(@profiles, [@profile_name, "account"], "default"), %{}},
      {"provider-whitespace", put_in(@profiles, [@profile_name, "provider"], " test"), %{}},
      {"provider-newline", put_in(@profiles, [@profile_name, "provider"], "test-provider\n"),
       %{}},
      {"provider-invalid-utf8", put_in(@profiles, [@profile_name, "provider"], <<255>>), %{}},
      {"model-newline",
       @profiles
       |> put_in([@profile_name, "model"], "subscription/exact-model\n")
       |> put_in([@profile_name, "allowed_models"], ["subscription/exact-model\n"]), %{}},
      {"model-invalid-utf8",
       @profiles
       |> put_in([@profile_name, "model"], <<255>>)
       |> put_in([@profile_name, "allowed_models"], [<<255>>]), %{}},
      {"fuzzy-model",
       @profiles
       |> put_in([@profile_name, "model"], "claude")
       |> put_in([@profile_name, "allowed_models"], ["claude"]), %{}},
      {"unknown-field", put_in(@profiles, [@profile_name, "credential"], "implicit"), %{}},
      {"profile-shape", %{@profile_name => false}, %{}},
      {"profile-entry-struct", %{@profile_name => %URI{}}, %{}},
      {"profiles-struct", %URI{}, %{}},
      {"profile-key", %{subscription: @profiles[@profile_name]}, %{}},
      {"profile-key-newline", %{"subscription\n" => @profiles[@profile_name]}, %{}},
      {"cooldown-container", @profiles, %{"provider_cooldowns" => []}},
      {"cooldown-container-struct", @profiles, %{"provider_cooldowns" => %URI{}}},
      {"cooldown-entry", @profiles,
       %{"provider_cooldowns" => %{@profile_name => %{"provider" => "test-provider"}}}},
      {"cooldown-entry-struct", @profiles, %{"provider_cooldowns" => %{@profile_name => %URI{}}}},
      {"cooldown-expiry", @profiles,
       %{"provider_cooldowns" => %{@profile_name => %{"until_epoch" => "later"}}}},
      {"cooldown-key-newline", @profiles,
       %{"provider_cooldowns" => %{"subscription\n" => %{"until_epoch" => 2_000}}}},
      {"cooldown-profile-newline", @profiles,
       %{
         "provider_cooldowns" => %{
           @profile_name => %{"until_epoch" => 2_000, "profile" => "subscription\n"}
         }
       }},
      {"cooldown-provider-newline", @profiles,
       %{
         "provider_cooldowns" => %{
           @profile_name => %{"until_epoch" => 2_000, "provider" => "test-provider\n"}
         }
       }},
      {"cooldown-reason-newline", @profiles,
       %{
         "provider_cooldowns" => %{
           @profile_name => %{"until_epoch" => 2_000, "reason" => "quota\n"}
         }
       }}
    ]

    unknown_cases =
      Enum.map(unknown_profile_key_cases(), fn {label, profiles} -> {label, profiles, %{}} end)

    base_cases ++ unknown_cases
  end

  defp unknown_profile_key_cases do
    [
      {"unknown-nil-key", profile_with_unknown_fields([{nil, :invalid}])},
      {"unknown-nil-mask",
       profile_with_unknown_fields([{nil, :invalid}, {"credential", "implicit"}])},
      {"unknown-tuple-key", profile_with_unknown_fields([{{:credential, 1}, :invalid}])},
      {"unknown-struct-key", profile_with_unknown_fields([{URI.parse("invalid"), :invalid}])},
      {"unknown-improper-list-key",
       profile_with_unknown_fields([{["credential" | :invalid], :invalid}])}
    ]
  end

  defp profile_with_unknown_fields(fields) do
    update_in(@profiles, [@profile_name], fn profile ->
      Enum.reduce(fields, profile, fn {field, value}, result -> Map.put(result, field, value) end)
    end)
  end

  defp dispatched_state(task_id, reviewer_profile) do
    state = queued_state(task_id, @profile_name)

    {:ok, _assignment, state} =
      State.admit_assignment(state, task_id, "developer-run", "developer", %{
        "profile" => @profile_name
      })

    put_in(state, ["assignments", task_id, "ticket", "reviewer_profile"], reviewer_profile)
  end

  defp ticket(task_id, profile) do
    %{
      "task_id" => task_id,
      "base_revision" => @base_rev,
      "scope" => ["foundry/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => "/tmp/fr01-checkout",
      "profile" => profile,
      "reviewer_profile" => profile
    }
  end

  defp handoff(task_id) do
    %{
      "schema_version" => 1,
      "task_id" => task_id,
      "run_id" => "developer-run",
      "assigned_base" => @base_rev,
      "commit" => @commit,
      "changed_files" => ["foundry/lib/pramana_foundry/example.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "FR-01 test handoff"
    }
  end

  defp invalid_review(task_id) do
    %{
      "schema_version" => 1,
      "run_id" => "wrong-reviewer-run",
      "task_id" => task_id,
      "commit" => @commit,
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [%{"command" => @check, "exit_code" => 0}]
    }
  end

  defp coordinator_data(state, profiles, ctx) do
    %{
      state: state,
      event_log_path: Path.join(ctx.tmp_dir, "events.jsonl"),
      herdr_adapter: adapter(),
      herdr_timeout: 1_000,
      telemetry_path: nil,
      agent_registry: %{},
      launch_profiles: profiles,
      launch_role_profiles: %{},
      launch_now_fn: fn -> 1_000 end,
      herdr_opts: [ets_table: ctx.table]
    }
  end

  defp adapter, do: Adapter.new(PramanaFoundry.AgentServerTest.FakeRunner)

  defp install_success_script(table) do
    PramanaFoundry.AgentServerTest.FakeRunner.install(table, fn
      ["herdr", "pane", "split" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

      ["herdr", "agent", "start" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{
          "result" => %{"agent" => @ready_agent}
        })

      ["herdr", "agent", "get", "fr01-agent"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

      ["herdr", "agent", "prompt" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})

      ["herdr", "pane", "close", "pane-fr01"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
    end)
  end

  defp assert_profile_argv(table) do
    recorded_calls = calls(table)
    pane_argv = Enum.find(recorded_calls, &match?(["herdr", "pane", "split" | _], &1))
    start_argv = Enum.find(recorded_calls, &match?(["herdr", "agent", "start" | _], &1))

    refute Enum.any?(pane_argv, &String.starts_with?(&1, "PRAMANA_FOUNDRY_"))
    assert argv_value(start_argv, "--profile") == "test-account"
    assert argv_value(start_argv, "--provider") == "test-provider"
    assert argv_value(start_argv, "--model") == "subscription/exact-model"
    assert argv_value(start_argv, "--thinking") == "medium"
    assert argv_value(start_argv, "--approval-mode") == "write"
  end

  defp calls(table), do: PramanaFoundry.AgentServerTest.FakeRunner.calls(table)
  defp clear_calls(table), do: :ets.insert(table, {:calls, []})

  defp argv_value(argv, option) do
    option_index = Enum.find_index(argv, &(&1 == option))
    Enum.at(argv, option_index + 1)
  end

  defp terminate_registered(registry) do
    Enum.each(registry, fn {_key, pid} ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(PramanaFoundry.AssignmentSupervisor, pid)
      end
    end)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
