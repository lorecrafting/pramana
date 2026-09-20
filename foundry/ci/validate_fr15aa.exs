defmodule PramanaFoundry.CI.FR15aAProcedure do
  @moduledoc false

  @type observation :: {:ok, :present | :absent} | {:error, :observer_unknown}

  @spec process_observation(binary(), non_neg_integer()) :: observation()
  def process_observation(output, 0) when is_binary(output),
    do: if(String.trim(output) == "", do: {:error, :observer_unknown}, else: {:ok, :present})

  def process_observation(output, 1) when is_binary(output),
    do: if(String.trim(output) == "", do: {:ok, :absent}, else: {:error, :observer_unknown})

  def process_observation(_output, _exit_code), do: {:error, :observer_unknown}

  @spec socket_observation(binary(), non_neg_integer()) :: observation()
  def socket_observation(output, 0) when is_binary(output),
    do: if(String.trim(output) == "", do: {:ok, :absent}, else: {:ok, :present})

  def socket_observation(_output, _exit_code), do: {:error, :observer_unknown}

  @spec require_all_absent([observation()]) :: :ok | {:error, atom()}
  def require_all_absent(observations) when is_list(observations) do
    cond do
      Enum.any?(observations, &match?({:error, _}, &1)) -> {:error, :observer_unknown}
      Enum.any?(observations, &(&1 == {:ok, :present})) -> {:error, :resource_present}
      Enum.all?(observations, &(&1 == {:ok, :absent})) -> :ok
      true -> {:error, :invalid_observation}
    end
  end

  @spec directory_record_observation(binary(), non_neg_integer()) :: observation()
  def directory_record_observation(_output, 0), do: {:ok, :present}

  def directory_record_observation(output, 56) when is_binary(output),
    do:
      if(String.contains?(output, "eDSRecordNotFound"),
        do: {:ok, :absent},
        else: {:error, :observer_unknown}
      )

  def directory_record_observation(_output, _exit_code), do: {:error, :observer_unknown}

  @spec rollback_targets([map()]) :: {:ok, [map()]} | {:error, atom()}
  def rollback_targets(entries) when is_list(entries) do
    if Enum.all?(entries, &valid_ledger_entry?/1) do
      {:ok, Enum.filter(entries, &(&1.preexisting == false and &1.created_by_attempt == true))}
    else
      {:error, :ownership_unknown}
    end
  end

  def rollback_targets(_entries), do: {:error, :ownership_unknown}

  defp valid_ledger_entry?(%{resource_id: id, preexisting: old, created_by_attempt: new})
       when is_binary(id) and id != "" and is_boolean(old) and is_boolean(new),
       do: not (old and new)

  defp valid_ledger_entry?(_entry), do: false
end

defmodule PramanaFoundry.CI.FR15aAValidator do
  @moduledoc false

  @schema "pramana-foundry-fr15aa-provisioning/v1"
  @source %{
    base_commit: "f5067d96d67a9ec3193a9b8bbadfa54c16525aa3",
    base_tree: "f19af86efd775fa0debd75868f571b13feaa748d",
    checkpoint_f_candidate: "148476c93497653abbbc52fb040cf76927478d3f",
    checkpoint_f_review: "ca8c6d0b5edc9a5cfb9c265e710b29f3210f5cbe",
    specification_profile: "fr15aa-provisioning-v2",
    validator_path: "foundry/ci/validate_fr15aa.exs"
  }
  @host_profile %{
    id: "macos-dedicated-local-principals-v1",
    os: "macOS",
    version: "26.6.2",
    build: "25G83",
    architecture: "arm64"
  }
  @principals %{
    "root" => {"root", "protected_verifier_store", false},
    "workflow_kernel" => {"_pramana_kernel", "restricted_candidate_workflow_kernel", false},
    "launcher" => {"_pramana_launcher", "trusted_fixed_launcher", false},
    "auth_gateway" => {"_pramana_auth", "trusted_credential_gateway", false},
    "harness" => {"_pramana_harness", "trusted_pinned_harness", false},
    "presentation" => {"_pramana_present", "sanitized_presentation", false},
    "fetch" => {"_pramana_fetch", "controlled_acquisition", false},
    "slot_developer" => {"_pramana_slot01", "untrusted_ephemeral_tool", false},
    "slot_reviewer" => {"_pramana_slot02", "untrusted_ephemeral_tool", false},
    "slot_pm" => {"_pramana_slot03", "untrusted_ephemeral_tool", false},
    "build" => {"_pramana_build", "untrusted_build", false},
    "runtime" => {"_pramana_runtime", "restricted_accepted_runtime", false}
  }
  @channels %{
    "root-command" =>
      {"unix_socket_peer_credential_plus_scoped_capability", "/var/run/pramana-foundry/root.sock",
       "root", ["launcher"]},
    "launch" =>
      {"unix_socket_peer_credential_plus_single_operation",
       "/var/run/pramana-foundry/launch.sock", "launcher", ["root"]},
    "model-request" =>
      {"unix_socket_peer_credential_plus_request_capability",
       "/var/run/pramana-foundry/auth.sock", "auth_gateway", ["harness"]},
    "effect" =>
      {"unix_socket_peer_credential_plus_invocation_capability",
       "/var/run/pramana-foundry/effect.sock", "launcher", ["harness"]},
    "fetch" =>
      {"unix_socket_peer_credential_plus_digest_request", "/var/run/pramana-foundry/fetch.sock",
       "fetch", ["root"]},
    "presentation" =>
      {"sanitized_one_way_event_feed", "/var/run/pramana-foundry/presentation.sock",
       "presentation", ["root"]},
    "kernel-bundle" =>
      {"unix_socket_peer_credential_plus_versioned_bundle_capability",
       "/var/run/pramana-foundry/kernel.sock", "root", ["workflow_kernel"]},
    "owned-pipe" =>
      {"close_on_exec_pipe", "per-execution", "launcher",
       ["slot_developer", "slot_reviewer", "slot_pm", "build", "runtime"]},
    "none" => {"denied_no_channel", "none", "root", []}
  }
  @kernel_allowed MapSet.new(
                    ~w(domain_event.append_supported domain_projection.cas effect.propose schedule.propose recovery.propose query.canonical_inputs)
                  )
  @kernel_forbidden MapSet.new(
                      ~w(accepted_ref activation_pointer budget_authorized budget_available budget_consumed budget_held claim_state deployed_release integrated_ref mandatory_check_valid policy_revision receipt_valid review_valid writer_epoch)
                    )
  @kernel_checks MapSet.new(
                   ~w(authenticated_original_command_retained bundle_schema_supported complete_revision_cas current_writer_epoch protected_fields_absent raw_receipts_retained role_profile_operation_scope_allowed)
                 )
  @routes %{
    "workflow-kernel-bundle" =>
      {"workflow_kernel", "workflow_kernel", "kernel-bundle", "blocked", ["workflow-kernel"]},
    "governing-omp" =>
      {"harness", "harness", "launch", "blocked",
       ~w(omp protected-launcher current-coordinator current-tick current-agent-server current-herdr-adapter current-herdr-argv current-herdr-runner current-launch-effect current-prompt-effect herdr host-env)},
    "pi-evaluation" =>
      {"replacement_harness", "harness", "launch", "blocked",
       ~w(pi pi-package pi-production-tree node protected-launcher checkpoint-f-probe host-env)},
    "provider-request" =>
      {"model_request", "auth_gateway", "model-request", "blocked", ["request-gateway"]},
    "shell" =>
      {"shell", "slot_developer", "effect", "blocked",
       ~w(effect-bridge current-check-runner current-process-group host-python3 host-ps host-kill)},
    "file-read" => {"file_read", "slot_developer", "effect", "blocked", ["effect-bridge"]},
    "file-write" => {"file_write", "slot_developer", "effect", "blocked", ["effect-bridge"]},
    "custom-tools" => {"custom_tools", "slot_developer", "effect", "blocked", ["effect-bridge"]},
    "explicit-extension" =>
      {"explicit_extensions", "harness", "none", "blocked", ~w(omp pi protected-launcher)},
    "discovered-extension" =>
      {"discovered_extensions", "harness", "none", "blocked", ~w(omp pi protected-launcher)},
    "startup-code" => {"startup_code", "launcher", "launch", "blocked", ["protected-launcher"]},
    "build-hooks" => {"build_hooks", "build", "effect", "blocked", ["effect-bridge"]},
    "language-service" =>
      {"language_services", "slot_developer", "effect", "unavailable", ["effect-bridge"]},
    "subprocess" =>
      {"subprocesses", "slot_developer", "owned-pipe", "blocked", ["effect-bridge"]},
    "environment" =>
      {"inherited_environment", "launcher", "launch", "blocked",
       ~w(protected-launcher effect-bridge)},
    "descriptors" =>
      {"inherited_file_descriptors", "launcher", "owned-pipe", "blocked",
       ~w(protected-launcher effect-bridge)},
    "direct-network" => {"network", "slot_developer", "none", "blocked", ["effect-bridge"]},
    "proxy-network" => {"network_proxy", "slot_developer", "none", "blocked", ["effect-bridge"]},
    "ipc" => {"ipc", "slot_developer", "effect", "blocked", ["effect-bridge"]},
    "process-memory" =>
      {"process_memory", "slot_developer", "none", "blocked", ["effect-bridge"]},
    "git-custody" =>
      {"git_metadata", "slot_developer", "effect", "blocked",
       ~w(effect-bridge current-git-evidence host-git)},
    "shared-state" =>
      {"shared_state", "slot_developer", "effect", "blocked",
       ~w(protected-launcher effect-bridge host-pgrep host-lsof host-launchctl)},
    "presentation" =>
      {"herdr_presentation", "presentation", "presentation", "blocked", ["herdr"]},
    "slot-reuse" =>
      {"role_slot_reuse", "launcher", "root-command", "blocked", ["protected-launcher"]},
    "cleanup" =>
      {"cleanup", "launcher", "root-command", "blocked",
       ~w(protected-launcher effect-bridge host-pgrep host-lsof host-launchctl)},
    "acquisition" => {"controlled_acquisition", "fetch", "fetch", "blocked", ["fetch-service"]},
    "accepted-build" =>
      {"build", "build", "effect", "blocked",
       ~w(effect-bridge elixir-ci otp-ci foundry-lock current-check-runner current-process-group current-cli-rpc host-python3 host-ps host-kill host-elixir host-mix)},
    "accepted-runtime" => {"runtime", "runtime", "launch", "blocked", ["protected-launcher"]}
  }
  @blocked_pins MapSet.new(
                  ~w(npm workflow-kernel protected-launcher request-gateway effect-bridge fetch-service)
                )
  @pin_digests %{
    "omp" => "e0302a99643efefb62bf3d0601d5d84ebab6ed1f3ad105cc2874c8274af448a9",
    "pi" => "e6d7fcf36a239cf3746e67ddf4222081ac01a601b85a3ee688bdfe9c161d754c",
    "pi-package" => "f1738e4b42203e5f22bcb513f13fb2fb224f1e98d1f129ff042f87048665a94c",
    "pi-production-tree" => "661ce1b6472d947977928059d6c6ae155dbd2941eee3affad2d922c29313f816",
    "node" => "902b6a6984d5d825829ea9064ab73b734548df37bc0683990dca31c8dc2a9253",
    "npm" => "unimplemented",
    "herdr" => "7257396b19a082193cbf39b4805341eaddabb489d4dbbecaccbba00164339b87",
    "elixir-ci" => "06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1",
    "otp-ci" => "06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1",
    "foundry-lock" => "bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954",
    "foundry-config" => "d38fca63c3463b4bbbb5c56afcd66a900d4f6e4d5c5434bf3ec0157f372a7b16",
    "assignment-schema" => "3042a56aa668c2852a4fdcf21c35eb70bd36d350e210e05f151177b60449ba8f",
    "current-coordinator" => "925c54dba022a06213f0d33eb26c6b352fbde53c713796e3587d96640e9db7e6",
    "current-tick" => "8df097027896c88bb55f03f50a6cb6f5592c64a8c201f41aa1bf186754143ee0",
    "current-agent-server" => "ec7e1ea88b26afc0f5b6ef3912479828334c32b16030ba6113aec1639aa360de",
    "current-herdr-adapter" => "404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189",
    "current-herdr-argv" => "e58e0d7c6f9701388ed1ce3c7d78e7984836677a027883f181a717bbbf303bfc",
    "current-herdr-runner" => "1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650",
    "current-launch-effect" => "b76aa1650acdfac03b35e2e498f5260c1f23081c682007f7a80b26fa89c9da22",
    "current-prompt-effect" => "f4e4c49c24498141495e02ce0d696788f276701151e6e1a22df686ffbd6961e9",
    "current-check-runner" => "22610624df6102f59579808048581e7e947eab19dfcc34cbaf3661d7255af8fc",
    "current-process-group" => "1250c2bee6d43751ac5f483224c0506e3670bf25a8c7f85cd0848d106d8dce17",
    "current-cli-rpc" => "617fb1dc018a70abb9ffd7f97bc7e886db6d217c16ae06ea15ef233d5829b11d",
    "current-git-evidence" => "4f044446b3559e8635da488e2d9f9f1047c1b665f56f4c84cb8fad43394fc7ce",
    "checkpoint-f-probe" => "c9a91bad8417314ce3ba0080562de4574425211d4fe25d3e68447a535cd83eea",
    "workflow-kernel" => "unimplemented",
    "host-sh" => "c0eaf44f9242d5bbc2e14f4e8b7dccc1eff7f2976d64dc18914d5ef9f373e100",
    "host-env" => "75690864f0e7397db05bcc0f4439915559ce24c2d834d530e4e619c14b938556",
    "host-python3" => "b8763cf250e607a778bb4603cecb5b90338814d0a3dfcba0d57b1de242f610e9",
    "host-git" => "b8763cf250e607a778bb4603cecb5b90338814d0a3dfcba0d57b1de242f610e9",
    "host-pgrep" => "0d1ffd0bb78cb9e9cba51bb013d67ec48f75bb21eefeec99c7321053fe23fd19",
    "host-lsof" => "b1b9151bbc56f4749890dbe4e533af9a4f8700240ad431a6c9ddf70fe137c165",
    "host-pfctl" => "675449d18fdca83c4e892b719215832092f8362d193fe9c72cd230918b5d150b",
    "host-launchctl" => "b4dbf509754d8e1117f7851baa93ede75bc75218c48d6ddf19fbb1505d261be7",
    "host-dscl" => "7870543dca5d253c509d2cb6c16893e53b688537b33f81d47d533d8693eb67f4",
    "host-ps" => "3bbba882e30d91fc4ff6e6844ca7c59fef4351b9a3fea35dca55708d6d487d1c",
    "host-kill" => "9354b1505290ffea73ddf52ca46fd9333466569a921f228df41b0346a1c8d592",
    "host-elixir" => "5cb23d89a78f75589b06fade3097e217b77e63416d61c1800f674579748c4307",
    "host-mix" => "0a48d65a9980f2b923bba597e0ebdde3049e3271089ffffb9265d5cf7954b659",
    "protected-launcher" => "unimplemented",
    "request-gateway" => "unimplemented",
    "effect-bridge" => "unimplemented",
    "fetch-service" => "unimplemented"
  }
  @mapped_fields ~w(principal channel credential_policy network_policy acceptance_probe)a

  @spec validate(term()) :: :ok | {:error, [String.t()]}
  def validate(spec) when is_map(spec) do
    errors =
      []
      |> check(spec[:schema] == @schema, "unexpected or missing schema")
      |> check(spec[:source] == @source, "source/specification provenance profile mismatch")
      |> check(spec[:authority][:host_profile] == @host_profile, "host profile mismatch")
      |> check(spec[:authority][:governing_harness] == "omp", "OMP must remain governing")
      |> check(
        spec[:authority][:replacement_disposition] == "evaluated_blocked_not_selected",
        "Pi must remain an unselected blocked candidate"
      )
      |> check(
        spec[:authority][:production_disposition] == "blocked_pending_fr15ab_and_fr09",
        "production must remain blocked behind FR-15aB and FR-09"
      )
      |> validate_principals(spec[:principals])
      |> validate_channels(spec[:channels])
      |> validate_kernel(spec[:kernel_protocol])
      |> validate_pins(spec[:pins])
      |> validate_routes(spec)

    case Enum.reverse(errors) do
      [] -> :ok
      failures -> {:error, failures}
    end
  rescue
    _error -> {:error, ["manifest structure is invalid"]}
  end

  def validate(_spec), do: {:error, ["manifest must be a map"]}

  defp validate_principals(errors, principals) when is_list(principals) do
    actual =
      Map.new(principals, fn principal ->
        {principal[:id], {principal[:account], principal[:trust], principal[:login]}}
      end)

    accounts = Enum.map(principals, & &1[:account])

    errors
    |> check(actual == @principals, "principal identities/trust/login differ from profile")
    |> check(
      length(accounts) == length(Enum.uniq(accounts)),
      "principal accounts must be distinct"
    )
  end

  defp validate_principals(errors, _), do: ["principal inventory must be a list" | errors]

  defp validate_channels(errors, channels) when is_list(channels) do
    actual =
      Map.new(channels, fn channel ->
        {channel[:id], {channel[:transport], channel[:path], channel[:server], channel[:callers]}}
      end)

    check(
      errors,
      actual == @channels,
      "channel transport/path/server/callers differ from profile"
    )
  end

  defp validate_channels(errors, _), do: ["channel inventory must be a list" | errors]

  defp validate_kernel(errors, p) when is_map(p) do
    errors
    |> check(p[:version] == "fr06-r3-bundle/v1", "kernel protocol version mismatch")
    |> check(
      p[:caller] == "workflow_kernel" and p[:verifier] == "root" and
        p[:channel] == "kernel-bundle",
      "kernel principal/channel mapping mismatch"
    )
    |> check(
      MapSet.new(p[:allowed_operations] || []) == @kernel_allowed,
      "kernel allowed operations mismatch"
    )
    |> check(
      MapSet.new(p[:forbidden_fields] || []) == @kernel_forbidden,
      "kernel protected fields mismatch"
    )
    |> check(
      MapSet.new(p[:root_checks] || []) == @kernel_checks,
      "kernel verifier checks mismatch"
    )
  end

  defp validate_kernel(errors, _), do: ["kernel protocol missing" | errors]

  defp validate_pins(errors, pins) when is_list(pins) do
    actual = Map.new(pins, &{&1.id, &1})

    errors =
      check(
        errors,
        MapSet.new(Map.keys(actual)) == MapSet.new(Map.keys(@pin_digests)),
        "pin inventory differs from frozen profile"
      )

    Enum.reduce(@pin_digests, errors, fn {id, expected}, acc ->
      pin = actual[id]
      blocked? = MapSet.member?(@blocked_pins, id)
      digest = pin && pin[:sha256]

      acc
      |> check(not is_nil(pin), "missing pin #{id}")
      |> check(digest == expected, "pin #{id} digest differs from frozen profile")
      |> check(
        blocked? == (pin && pin[:status] == "blocked"),
        "pin #{id} blocked/implemented disposition mismatch"
      )
      |> check(blocked? or valid_digest?(digest), "pin #{id} needs a nonzero exact SHA-256")
      |> validate_repository_pin(pin)
    end)
  end

  defp validate_pins(errors, _), do: ["pin inventory must be a list" | errors]

  defp validate_repository_pin(errors, %{path: "foundry/" <> _ = path, sha256: expected}) do
    case File.read(Path.expand("../../#{path}", __DIR__)) do
      {:ok, bytes} ->
        check(
          errors,
          sha256(bytes) == expected,
          "repository pin #{path} does not match file bytes"
        )

      {:error, _} ->
        ["repository pin #{path} is unavailable" | errors]
    end
  end

  defp validate_repository_pin(errors, _), do: errors

  defp validate_routes(errors, spec) do
    routes = Map.new(spec.routes, &{&1.id, &1})
    pins = Map.new(spec.pins, &{&1.id, &1})

    errors =
      check(
        errors,
        MapSet.new(Map.keys(routes)) == MapSet.new(Map.keys(@routes)),
        "route inventory differs from frozen profile"
      )

    Enum.reduce(@routes, errors, fn {id, {category, principal, channel, status, dependencies}},
                                    acc ->
      route = routes[id]
      deps = route && route[:executable_ids]
      supported? = route && route[:production_status] == "supported"

      implemented? =
        is_list(deps) and deps != [] and
          Enum.all?(deps, &(pins[&1] && pins[&1][:status] != "blocked"))

      if is_nil(route) do
        ["missing route #{id}" | acc]
      else
        acc
        |> check(
          {route.category, route.principal, route.channel, route.production_status} ==
            {category, principal, channel, status},
          "route #{id} principal/channel/status contract mismatch"
        )
        |> check(
          route.executable_ids == dependencies,
          "route #{id} executable provenance mismatch"
        )
        |> check(
          Enum.all?(@mapped_fields, &non_empty?(route[&1])),
          "route #{id} lacks principal/channel/credential/network/probe mapping"
        )
        |> check(
          route.fail_closed == true and non_empty?(route.blocker),
          "route #{id} must remain explicitly blocked/fail-closed"
        )
        |> check(
          not supported? or implemented?,
          "supported route #{id} references an unimplemented adapter"
        )
        |> check(
          route.category != "shell" or
            (route.principal not in ["root", "auth_gateway"] and
               route.channel not in ["root-command", "model-request", "kernel-bundle"]),
          "shell route cannot use root/auth/kernel authority channel"
        )
      end
    end)
  end

  defp valid_digest?(digest) when is_binary(digest),
    do: Regex.match?(~r/\A[0-9a-f]{64}\z/, digest) and digest != String.duplicate("0", 64)

  defp valid_digest?(_), do: false
  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""
  defp check(errors, true, _), do: errors
  defp check(errors, false, message), do: [message | errors]
end

unless System.get_env("MIX_ENV") == "test" do
  {manifest, _binding} =
    Code.eval_file(Path.expand("../docs/fr-15a/provisioning-manifest.exs", __DIR__))

  case PramanaFoundry.CI.FR15aAValidator.validate(manifest) do
    :ok ->
      IO.puts("FR-15aA provisioning manifest: valid")

    {:error, errors} ->
      Enum.each(errors, &IO.puts(:stderr, "FR-15aA validation error: #{&1}"))
      System.halt(1)
  end
end
