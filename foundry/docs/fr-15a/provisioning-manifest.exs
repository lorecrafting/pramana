%{
  schema: "pramana-foundry-fr15aa-provisioning/v1",
  source: %{
    base_commit: "f5067d96d67a9ec3193a9b8bbadfa54c16525aa3",
    base_tree: "f19af86efd775fa0debd75868f571b13feaa748d",
    checkpoint_f_candidate: "148476c93497653abbbc52fb040cf76927478d3f",
    checkpoint_f_review: "ca8c6d0b5edc9a5cfb9c265e710b29f3210f5cbe",
    specification_profile: "fr15aa-provisioning-v2",
    validator_path: "foundry/ci/validate_fr15aa.exs"
  },
  authority: %{
    governing_harness: "omp",
    replacement_candidate: "pi",
    replacement_disposition: "evaluated_blocked_not_selected",
    production_disposition: "blocked_pending_fr15ab_and_fr09",
    host_profile: %{
      id: "macos-dedicated-local-principals-v1",
      os: "macOS",
      version: "26.6.2",
      build: "25G83",
      architecture: "arm64"
    }
  },
  pins: [
    %{
      id: "omp",
      kind: "executable",
      version: "18.2.2",
      path: "/Users/raymondluong/.local/bin/omp",
      sha256: "e0302a99643efefb62bf3d0601d5d84ebab6ed1f3ad105cc2874c8274af448a9",
      status: "governing_unproved"
    },
    %{
      id: "pi",
      kind: "executable",
      version: "0.85.1",
      path: "/opt/homebrew/bin/pi",
      sha256: "e6d7fcf36a239cf3746e67ddf4222081ac01a601b85a3ee688bdfe9c161d754c",
      status: "candidate_blocked"
    },
    %{
      id: "pi-package",
      kind: "package_manifest",
      version: "0.85.1",
      path: "installed:@earendil-works/pi-coding-agent/package.json",
      sha256: "f1738e4b42203e5f22bcb513f13fb2fb224f1e98d1f129ff042f87048665a94c",
      status: "inventory_only"
    },
    %{
      id: "pi-production-tree",
      kind: "package_inventory",
      version: "186-manifest-offline-npm-ls",
      path: "installed:@earendil-works/pi-coding-agent",
      sha256: "661ce1b6472d947977928059d6c6ae155dbd2941eee3affad2d922c29313f816",
      status: "inventory_only"
    },
    %{
      id: "node",
      kind: "executable",
      version: "26.8.2",
      path: "/opt/homebrew/bin/node",
      sha256: "902b6a6984d5d825829ea9064ab73b734548df37bc0683990dca31c8dc2a9253",
      status: "candidate_runtime"
    },
    %{
      id: "npm",
      kind: "executable",
      version: "11.19.1",
      path: "resolved-with-node-installation",
      sha256: "unimplemented",
      status: "blocked"
    },
    %{
      id: "herdr",
      kind: "executable",
      version: "0.9.0",
      path: "/opt/homebrew/bin/herdr",
      sha256: "7257396b19a082193cbf39b4805341eaddabb489d4dbbecaccbba00164339b87",
      status: "presentation_unproved"
    },
    %{
      id: "elixir-ci",
      kind: "toolchain",
      version: "1.20.3",
      path: "foundry/ci/toolchain.exs",
      sha256: "06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1",
      status: "policy_pin"
    },
    %{
      id: "otp-ci",
      kind: "toolchain",
      version: "29.0.5/ERTS-17.0.5",
      path: "foundry/ci/toolchain.exs",
      sha256: "06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1",
      status: "policy_pin"
    },
    %{
      id: "foundry-lock",
      kind: "package_lock",
      version: "base-f5067d9",
      path: "foundry/mix.lock",
      sha256: "bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954",
      status: "repository_pin"
    },
    %{
      id: "foundry-config",
      kind: "config",
      version: "base-f5067d9",
      path: "foundry/config/config.exs",
      sha256: "d38fca63c3463b4bbbb5c56afcd66a900d4f6e4d5c5434bf3ec0157f372a7b16",
      status: "legacy_not_provisioning"
    },
    %{
      id: "assignment-schema",
      kind: "config",
      version: "v1-base-f5067d9",
      path: "foundry/config/schemas/assignment-v1.json",
      sha256: "3042a56aa668c2852a4fdcf21c35eb70bd36d350e210e05f151177b60449ba8f",
      status: "repository_pin"
    },
    %{
      id: "current-coordinator",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/coordinator.ex",
      sha256: "925c54dba022a06213f0d33eb26c6b352fbde53c713796e3587d96640e9db7e6",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-tick",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/coordinator/tick.ex",
      sha256: "8df097027896c88bb55f03f50a6cb6f5592c64a8c201f41aa1bf186754143ee0",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-agent-server",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/agent_server.ex",
      sha256: "ec7e1ea88b26afc0f5b6ef3912479828334c32b16030ba6113aec1639aa360de",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-herdr-adapter",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/herdr/adapter.ex",
      sha256: "404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-herdr-argv",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/herdr/argv.ex",
      sha256: "e58e0d7c6f9701388ed1ce3c7d78e7984836677a027883f181a717bbbf303bfc",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-herdr-runner",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/herdr/runner.ex",
      sha256: "1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-launch-effect",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/effects/launch.ex",
      sha256: "b76aa1650acdfac03b35e2e498f5260c1f23081c682007f7a80b26fa89c9da22",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-prompt-effect",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/effects/prompt_delivery.ex",
      sha256: "f4e4c49c24498141495e02ce0d696788f276701151e6e1a22df686ffbd6961e9",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-check-runner",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/checks/runner.ex",
      sha256: "22610624df6102f59579808048581e7e947eab19dfcc34cbaf3661d7255af8fc",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-process-group",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/effects/process_group.ex",
      sha256: "0c198191bbff8e31121086075782e458db6b4c52b0ddc8eede42247fa45c65ff",
      status: "legacy_blocked_route"
    },
    %{
      id: "current-cli-rpc",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/cli/rpc.ex",
      # Re-pinned 2026-09-23: Batch D W4 added routing of `lane …` argv to the manual-lane
      # CLI (ManualLane.CLI). Routing only; the transport stays inert and grants no authority.
      sha256: "5062c5e59a9e01415764edf61837b251609abd4bdd53fedf2bd25fa3a940e1a1",
      status: "temporary_inert_transport_not_authority"
    },
    %{
      id: "current-git-evidence",
      kind: "source_route",
      version: "base-f5067d9",
      path: "foundry/lib/pramana_foundry/git_evidence.ex",
      sha256: "4f044446b3559e8635da488e2d9f9f1047c1b665f56f4c84cb8fad43394fc7ce",
      status: "legacy_blocked_route"
    },
    %{
      id: "checkpoint-f-probe",
      kind: "evidence_fixture",
      version: "candidate-148476c",
      path: "foundry/docs/fr-09/pi_rpc_probe.exs",
      sha256: "c9a91bad8417314ce3ba0080562de4574425211d4fe25d3e68447a535cd83eea",
      status: "accepted_provider_free_evidence"
    },
    %{
      id: "workflow-kernel",
      kind: "required_adapter",
      version: "fr06-r3-bundle-v1",
      path: "/Library/PramanaFoundry/releases/kernel/CANDIDATE_SHA/bin/pramana-kernel",
      sha256: "unimplemented",
      status: "blocked"
    },
    %{
      id: "host-sh",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/bin/sh",
      sha256: "c0eaf44f9242d5bbc2e14f4e8b7dccc1eff7f2976d64dc18914d5ef9f373e100",
      status: "host_profile_pin"
    },
    %{
      id: "host-env",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/usr/bin/env",
      sha256: "75690864f0e7397db05bcc0f4439915559ce24c2d834d530e4e619c14b938556",
      status: "host_profile_pin"
    },
    %{
      id: "host-python3",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/usr/bin/python3",
      sha256: "b8763cf250e607a778bb4603cecb5b90338814d0a3dfcba0d57b1de242f610e9",
      status: "host_profile_pin"
    },
    %{
      id: "host-git",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/usr/bin/git",
      sha256: "b8763cf250e607a778bb4603cecb5b90338814d0a3dfcba0d57b1de242f610e9",
      status: "host_profile_pin"
    },
    %{
      id: "host-pgrep",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/usr/bin/pgrep",
      sha256: "0d1ffd0bb78cb9e9cba51bb013d67ec48f75bb21eefeec99c7321053fe23fd19",
      status: "host_profile_pin"
    },
    %{
      id: "host-lsof",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/usr/sbin/lsof",
      sha256: "b1b9151bbc56f4749890dbe4e533af9a4f8700240ad431a6c9ddf70fe137c165",
      status: "host_profile_pin"
    },
    %{
      id: "host-pfctl",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/sbin/pfctl",
      sha256: "675449d18fdca83c4e892b719215832092f8362d193fe9c72cd230918b5d150b",
      status: "host_profile_pin"
    },
    %{
      id: "host-launchctl",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/bin/launchctl",
      sha256: "b4dbf509754d8e1117f7851baa93ede75bc75218c48d6ddf19fbb1505d261be7",
      status: "host_profile_pin"
    },
    %{
      id: "host-dscl",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/usr/bin/dscl",
      sha256: "7870543dca5d253c509d2cb6c16893e53b688537b33f81d47d533d8693eb67f4",
      status: "host_profile_pin"
    },
    %{
      id: "host-ps",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/bin/ps",
      sha256: "3bbba882e30d91fc4ff6e6844ca7c59fef4351b9a3fea35dca55708d6d487d1c",
      status: "host_profile_pin"
    },
    %{
      id: "host-kill",
      kind: "host_executable",
      version: "macos-26.6.2-25G83-arm64",
      path: "/bin/kill",
      sha256: "9354b1505290ffea73ddf52ca46fd9333466569a921f228df41b0346a1c8d592",
      status: "host_profile_pin"
    },
    %{
      id: "host-elixir",
      kind: "host_executable",
      version: "1.20.4-otp-29",
      path: "/opt/homebrew/bin/elixir",
      sha256: "5cb23d89a78f75589b06fade3097e217b77e63416d61c1800f674579748c4307",
      status: "host_profile_inventory_only"
    },
    %{
      id: "host-mix",
      kind: "host_executable",
      version: "1.20.4-otp-29",
      path: "/opt/homebrew/bin/mix",
      sha256: "0a48d65a9980f2b923bba597e0ebdde3049e3271089ffffb9265d5cf7954b659",
      status: "host_profile_inventory_only"
    },
    %{
      id: "protected-launcher",
      kind: "required_adapter",
      version: "fr15aa-v1",
      path: "/Library/PramanaFoundry/bin/pf-launch",
      sha256: "unimplemented",
      status: "blocked"
    },
    %{
      id: "request-gateway",
      kind: "required_adapter",
      version: "fr15aa-v1",
      path: "/Library/PramanaFoundry/bin/pf-auth-gateway",
      sha256: "unimplemented",
      status: "blocked"
    },
    %{
      id: "effect-bridge",
      kind: "required_adapter",
      version: "fr15aa-v1",
      path: "/Library/PramanaFoundry/bin/pf-effect-bridge",
      sha256: "unimplemented",
      status: "blocked"
    },
    %{
      id: "fetch-service",
      kind: "required_adapter",
      version: "fr15aa-v1",
      path: "/Library/PramanaFoundry/bin/pf-fetch",
      sha256: "unimplemented",
      status: "blocked"
    }
  ],
  principals: [
    %{id: "root", account: "root", trust: "protected_verifier_store", login: false},
    %{
      id: "workflow_kernel",
      account: "_pramana_kernel",
      trust: "restricted_candidate_workflow_kernel",
      login: false
    },
    %{
      id: "launcher",
      account: "_pramana_launcher",
      trust: "trusted_fixed_launcher",
      login: false
    },
    %{
      id: "auth_gateway",
      account: "_pramana_auth",
      trust: "trusted_credential_gateway",
      login: false
    },
    %{id: "harness", account: "_pramana_harness", trust: "trusted_pinned_harness", login: false},
    %{
      id: "presentation",
      account: "_pramana_present",
      trust: "sanitized_presentation",
      login: false
    },
    %{id: "fetch", account: "_pramana_fetch", trust: "controlled_acquisition", login: false},
    %{
      id: "slot_developer",
      account: "_pramana_slot01",
      trust: "untrusted_ephemeral_tool",
      login: false
    },
    %{
      id: "slot_reviewer",
      account: "_pramana_slot02",
      trust: "untrusted_ephemeral_tool",
      login: false
    },
    %{id: "slot_pm", account: "_pramana_slot03", trust: "untrusted_ephemeral_tool", login: false},
    %{id: "build", account: "_pramana_build", trust: "untrusted_build", login: false},
    %{
      id: "runtime",
      account: "_pramana_runtime",
      trust: "restricted_accepted_runtime",
      login: false
    }
  ],
  channels: [
    %{
      id: "root-command",
      transport: "unix_socket_peer_credential_plus_scoped_capability",
      path: "/var/run/pramana-foundry/root.sock",
      server: "root",
      callers: ["launcher"]
    },
    %{
      id: "launch",
      transport: "unix_socket_peer_credential_plus_single_operation",
      path: "/var/run/pramana-foundry/launch.sock",
      server: "launcher",
      callers: ["root"]
    },
    %{
      id: "model-request",
      transport: "unix_socket_peer_credential_plus_request_capability",
      path: "/var/run/pramana-foundry/auth.sock",
      server: "auth_gateway",
      callers: ["harness"]
    },
    %{
      id: "effect",
      transport: "unix_socket_peer_credential_plus_invocation_capability",
      path: "/var/run/pramana-foundry/effect.sock",
      server: "launcher",
      callers: ["harness"]
    },
    %{
      id: "fetch",
      transport: "unix_socket_peer_credential_plus_digest_request",
      path: "/var/run/pramana-foundry/fetch.sock",
      server: "fetch",
      callers: ["root"]
    },
    %{
      id: "presentation",
      transport: "sanitized_one_way_event_feed",
      path: "/var/run/pramana-foundry/presentation.sock",
      server: "presentation",
      callers: ["root"]
    },
    %{
      id: "kernel-bundle",
      transport: "unix_socket_peer_credential_plus_versioned_bundle_capability",
      path: "/var/run/pramana-foundry/kernel.sock",
      server: "root",
      callers: ["workflow_kernel"]
    },
    %{
      id: "owned-pipe",
      transport: "close_on_exec_pipe",
      path: "per-execution",
      server: "launcher",
      callers: ["slot_developer", "slot_reviewer", "slot_pm", "build", "runtime"]
    },
    %{id: "none", transport: "denied_no_channel", path: "none", server: "root", callers: []}
  ],
  kernel_protocol: %{
    version: "fr06-r3-bundle/v1",
    caller: "workflow_kernel",
    verifier: "root",
    channel: "kernel-bundle",
    allowed_operations: [
      "domain_event.append_supported",
      "domain_projection.cas",
      "effect.propose",
      "schedule.propose",
      "recovery.propose",
      "query.canonical_inputs"
    ],
    forbidden_fields: [
      "accepted_ref",
      "activation_pointer",
      "budget_authorized",
      "budget_available",
      "budget_consumed",
      "budget_held",
      "claim_state",
      "deployed_release",
      "integrated_ref",
      "mandatory_check_valid",
      "policy_revision",
      "receipt_valid",
      "review_valid",
      "writer_epoch"
    ],
    root_checks: [
      "authenticated_original_command_retained",
      "bundle_schema_supported",
      "complete_revision_cas",
      "current_writer_epoch",
      "protected_fields_absent",
      "raw_receipts_retained",
      "role_profile_operation_scope_allowed"
    ]
  },
  routes: [
    %{
      id: "workflow-kernel-bundle",
      category: "workflow_kernel",
      executable_ids: ["workflow-kernel"],
      principal: "workflow_kernel",
      channel: "kernel-bundle",
      credential_policy:
        "peer UID plus exact kernel artifact, candidate, policy and writer-epoch capability; no SQL/OS/root credential",
      network_policy: "deny IP; kernel.sock only",
      acceptance_probe:
        "valid supported bundle commits through verifier; forged budgets/acceptance/receipts and stale writer epoch refuse without protected mutation",
      production_status: "blocked",
      fail_closed: true,
      blocker:
        "isolated kernel artifact, versioned bundle gateway and old-epoch fencing are unimplemented"
    },
    %{
      id: "governing-omp",
      category: "harness",
      executable_ids: [
        "omp",
        "protected-launcher",
        "current-coordinator",
        "current-tick",
        "current-agent-server",
        "current-herdr-adapter",
        "current-herdr-argv",
        "current-herdr-runner",
        "current-launch-effect",
        "current-prompt-effect",
        "herdr",
        "host-env"
      ],
      principal: "harness",
      channel: "launch",
      credential_policy: "no_reusable_credential; execution capability private to exact process",
      network_policy: "deny AF_INET/AF_INET6; model traffic only over auth.sock",
      acceptance_probe:
        "FR-15aB digest/loadout/CWD/env/FD denial plus FR-09 installed OMP conformance",
      production_status: "blocked",
      fail_closed: true,
      blocker:
        "launcher, gateway routing, remote tools and installed OMP conformance do not exist"
    },
    %{
      id: "pi-evaluation",
      category: "replacement_harness",
      executable_ids: [
        "pi",
        "pi-package",
        "pi-production-tree",
        "node",
        "protected-launcher",
        "checkpoint-f-probe",
        "host-env"
      ],
      principal: "harness",
      channel: "launch",
      credential_policy: "same as OMP; never direct API key",
      network_policy: "deny direct network; auth.sock only",
      acceptance_probe:
        "repeat checkpoint-F protocol cases under FR-15aB then explicit contract review before selection",
      production_status: "blocked",
      fail_closed: true,
      blocker: "Pi not selected; explicit extension and direct bearer paths observed"
    },
    %{
      id: "provider-request",
      category: "model_request",
      executable_ids: ["request-gateway"],
      principal: "auth_gateway",
      channel: "model-request",
      credential_policy:
        "reusable provider auth readable only by _pramana_auth; fixed route from immutable assignment",
      network_policy:
        "only principal allowed provider DNS/TLS destinations; no CONNECT/arbitrary URL",
      acceptance_probe:
        "first/continuation/retry/compaction each show R1 issue and R5 reservation before packet plus receipt/unknown hold",
      production_status: "blocked",
      fail_closed: true,
      blocker: "request gateway and protected R1/R5 primitives are unimplemented"
    },
    %{
      id: "shell",
      category: "shell",
      executable_ids: [
        "effect-bridge",
        "current-check-runner",
        "current-process-group",
        "host-python3",
        "host-ps",
        "host-kill"
      ],
      principal: "slot_developer",
      channel: "effect",
      credential_policy: "credential-free inert argv; no harness/root capability",
      network_policy: "deny all IP egress; acquisition requires fetch.sock",
      acceptance_probe:
        "useful Elixir docs check in slot; direct provider/proxy/auth socket and other-slot access denied",
      production_status: "blocked",
      fail_closed: true,
      blocker: "checkpoint F shell ran same-user inside Pi"
    },
    %{
      id: "file-read",
      category: "file_read",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "effect",
      credential_policy: "invocation-scoped canonical resource capability",
      network_policy: "none",
      acceptance_probe:
        "allow admitted workspace file; deny absolute/traversal/symlink/hardlink/swap and protected roots",
      production_status: "blocked",
      fail_closed: true,
      blocker: "typed canonical-path bridge absent"
    },
    %{
      id: "file-write",
      category: "file_write",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "effect",
      credential_policy: "role and candidate generation bound write capability",
      network_policy: "none",
      acceptance_probe:
        "developer scoped edit succeeds; reviewer/root/common-Git/other-slot writes fail",
      production_status: "blocked",
      fail_closed: true,
      blocker: "typed bridge and actual principals absent"
    },
    %{
      id: "custom-tools",
      category: "custom_tools",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "effect",
      credential_policy: "only manifest-listed typed operations; no arbitrary extension token",
      network_policy: "per operation, default deny",
      acceptance_probe:
        "unknown tool and schema fail before dispatch; active schema digest matches manifest",
      production_status: "blocked",
      fail_closed: true,
      blocker: "current harnesses expose ambient/custom tool execution"
    },
    %{
      id: "explicit-extension",
      category: "explicit_extensions",
      executable_ids: ["omp", "pi", "protected-launcher"],
      principal: "harness",
      channel: "none",
      credential_policy: "no candidate extension permitted",
      network_policy: "not executed",
      acceptance_probe:
        "CLI explicit malicious extension is rejected, not merely hidden; checkpoint-F FD-9 reproduction cannot execute",
      production_status: "blocked",
      fail_closed: true,
      blocker: "checkpoint F proved Pi explicit extension executes despite --no-extensions"
    },
    %{
      id: "discovered-extension",
      category: "discovered_extensions",
      executable_ids: ["omp", "pi", "protected-launcher"],
      principal: "harness",
      channel: "none",
      credential_policy: "neutral root and controller-owned manifest only",
      network_policy: "not executed",
      acceptance_probe: "hostile user/project/ancestor extension/config markers remain absent",
      production_status: "blocked",
      fail_closed: true,
      blocker: "flags observed but no manifest-enforced launcher or OMP proof"
    },
    %{
      id: "startup-code",
      category: "startup_code",
      executable_ids: ["protected-launcher"],
      principal: "launcher",
      channel: "launch",
      credential_policy: "root-installed fixed argv/config digest; candidate CWD never used",
      network_policy: "launcher has no network",
      acceptance_probe:
        "candidate shell rc, env hooks, NODE_OPTIONS, runtime loaders and project config cannot execute",
      production_status: "blocked",
      fail_closed: true,
      blocker: "protected launcher unimplemented"
    },
    %{
      id: "build-hooks",
      category: "build_hooks",
      executable_ids: ["effect-bridge"],
      principal: "build",
      channel: "effect",
      credential_policy:
        "separate build invocation grant; no Git integration/provider credential",
      network_policy: "deny; declared acquisition through fetch.sock only",
      acceptance_probe:
        "hostile package/build hook runs only as _pramana_build and cannot escape workspace or persist hook",
      production_status: "blocked",
      fail_closed: true,
      blocker: "current check runner inherits parent environment and is not account-isolated"
    },
    %{
      id: "language-service",
      category: "language_services",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "effect",
      credential_policy: "pinned server and workspace-only grant",
      network_policy: "deny",
      acceptance_probe:
        "hostile LSP initialization/build command remains within slot; undeclared server refused",
      production_status: "unavailable",
      fail_closed: true,
      blocker: "expert absent and no pinned language-service adapter"
    },
    %{
      id: "subprocess",
      category: "subprocesses",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "owned-pipe",
      credential_policy: "same slot/process group; close-on-exec descriptors only",
      network_policy: "inherits slot deny policy",
      acceptance_probe:
        "descendant tree is attributed, bounded and gone before slot reuse; daemonization cannot escape",
      production_status: "blocked",
      fail_closed: true,
      blocker: "current same-user Bash can spawn arbitrary children"
    },
    %{
      id: "environment",
      category: "inherited_environment",
      executable_ids: ["protected-launcher", "effect-bridge"],
      principal: "launcher",
      channel: "launch",
      credential_policy:
        "env -i style fixed allowlist; no proxy/provider/SSH/Git/runtime override",
      network_policy: "no proxy variables",
      acceptance_probe:
        "checkpoint-F hostile sentinel set absent in harness, extensions, shell, build and runtime",
      production_status: "blocked",
      fail_closed: true,
      blocker: "only synthetic probe launcher currently demonstrates scrub"
    },
    %{
      id: "descriptors",
      category: "inherited_file_descriptors",
      executable_ids: ["protected-launcher", "effect-bridge"],
      principal: "launcher",
      channel: "owned-pipe",
      credential_policy: "close all except enumerated stdio/control descriptors with CLOEXEC",
      network_policy: "no inherited sockets",
      acceptance_probe:
        "synthetic FD 8/9 and inherited sockets absent from harness/tool/build/runtime except named channel",
      production_status: "blocked",
      fail_closed: true,
      blocker: "checkpoint F explicit extension read intentionally passed FD 9"
    },
    %{
      id: "direct-network",
      category: "network",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "none",
      credential_policy: "none",
      network_policy:
        "PF deny-by-UID for IP traffic; local capability sockets separately mode/peer checked",
      acceptance_probe:
        "TCP/UDP/DNS/provider/loopback attempts denied from every slot/build/runtime/harness principal",
      production_status: "blocked",
      fail_closed: true,
      blocker: "host packet-filter policy not provisioned"
    },
    %{
      id: "proxy-network",
      category: "network_proxy",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "none",
      credential_policy: "no proxy env, files, keychain or gateway forwarding",
      network_policy: "general HTTP CONNECT/SOCKS and operator proxies unreachable",
      acceptance_probe:
        "hostile proxy env/config and direct proxy sockets fail; auth gateway rejects arbitrary URL/headers",
      production_status: "blocked",
      fail_closed: true,
      blocker: "actual proxy denial unproved"
    },
    %{
      id: "ipc",
      category: "ipc",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "effect",
      credential_policy: "peer UID plus execution/invocation capability digest",
      network_policy: "only assigned effect.sock endpoint",
      acceptance_probe:
        "root/auth/presentation/other-slot sockets, Mach services and BEAM distribution unavailable",
      production_status: "blocked",
      fail_closed: true,
      blocker: "scoped protocol and host policies absent; legacy RPC is general evaluation"
    },
    %{
      id: "process-memory",
      category: "process_memory",
      executable_ids: ["effect-bridge"],
      principal: "slot_developer",
      channel: "none",
      credential_policy:
        "different UID; no task_for_pid/debug entitlement; no shared memory handles",
      network_policy: "none",
      acceptance_probe:
        "signal/inspect/debug/read harness, auth, root and foreign slot processes denied",
      production_status: "blocked",
      fail_closed: true,
      blocker: "checkpoint F demonstrated same-user signalling"
    },
    %{
      id: "git-custody",
      category: "git_metadata",
      executable_ids: ["effect-bridge", "current-git-evidence", "host-git"],
      principal: "slot_developer",
      channel: "effect",
      credential_policy:
        "disposable object view; protected common repo/refs/remotes/hooks inaccessible",
      network_policy: "no Git network",
      acceptance_probe:
        "shared HEAD/hook/ref/remote mutation denied; controller rebinds diff/commit to observed objects",
      production_status: "blocked",
      fail_closed: true,
      blocker: "checkpoint F read shared worktree common metadata"
    },
    %{
      id: "shared-state",
      category: "shared_state",
      executable_ids: [
        "protected-launcher",
        "effect-bridge",
        "host-pgrep",
        "host-lsof",
        "host-launchctl"
      ],
      principal: "slot_developer",
      channel: "effect",
      credential_policy:
        "execution-scoped home/session/cache/tmp/workspace; no cross-assignment reuse",
      network_policy: "none",
      acceptance_probe:
        "foreign session/cache/transcript/config unavailable; all owned roots removed after quiescence",
      production_status: "blocked",
      fail_closed: true,
      blocker: "installed Pi/OMP/Herdr use same-user roots"
    },
    %{
      id: "presentation",
      category: "herdr_presentation",
      executable_ids: ["herdr"],
      principal: "presentation",
      channel: "presentation",
      credential_policy:
        "sanitized read/control projection only; no steering/harness/provider capability",
      network_policy: "local presentation socket only",
      acceptance_probe:
        "attach/read/close cannot yield operator shell, raw prompt secret, auth socket or completion authority",
      production_status: "blocked",
      fail_closed: true,
      blocker: "current Herdr is same-user and FR-09 presentation conformance unproved"
    },
    %{
      id: "slot-reuse",
      category: "role_slot_reuse",
      executable_ids: ["protected-launcher"],
      principal: "launcher",
      channel: "root-command",
      credential_policy: "role/execution/revocation generation bound; reviewer lineage distinct",
      network_policy: "slot default deny restored before assignment",
      acceptance_probe:
        "developer/reviewer/PM grants do not cross; stale token/session/process cannot control successor",
      production_status: "blocked",
      fail_closed: true,
      blocker: "account pool and revocation/quiescence protocol not provisioned"
    },
    %{
      id: "cleanup",
      category: "cleanup",
      executable_ids: [
        "protected-launcher",
        "effect-bridge",
        "host-pgrep",
        "host-lsof",
        "host-launchctl"
      ],
      principal: "launcher",
      channel: "root-command",
      credential_policy: "root recovery claim identifies exact owned process group and roots",
      network_policy: "deny throughout cleanup",
      acceptance_probe:
        "TERM/KILL bounded escalation, process/FD/socket re-scan, capability revoke, owned-root removal; uncertainty quarantines slot",
      production_status: "blocked",
      fail_closed: true,
      blocker: "actual multi-principal cleanup and quarantine absent"
    },
    %{
      id: "acquisition",
      category: "controlled_acquisition",
      executable_ids: ["fetch-service"],
      principal: "fetch",
      channel: "fetch",
      credential_policy:
        "no provider auth; root-admitted immutable URL/host/digest/size request only",
      network_policy:
        "allowlisted package/artifact TLS destinations only; content returned by descriptor/file, never proxy",
      acceptance_probe:
        "undeclared host/redirect/digest/size fails; admitted artifact stored root-owned then exposed read-only",
      production_status: "blocked",
      fail_closed: true,
      blocker: "fetch service and host allowlist absent; no acquisition performed"
    },
    %{
      id: "accepted-build",
      category: "build",
      executable_ids: [
        "effect-bridge",
        "elixir-ci",
        "otp-ci",
        "foundry-lock",
        "current-check-runner",
        "current-process-group",
        "current-cli-rpc",
        "host-python3",
        "host-ps",
        "host-kill",
        "host-elixir",
        "host-mix"
      ],
      principal: "build",
      channel: "effect",
      credential_policy:
        "fixed check spec and source digest; output is evidence, never self-acceptance",
      network_policy: "offline after controlled acquisition",
      acceptance_probe:
        "provider-free docs/compile/test receipt bound to exact source; hostile hook denial retained",
      production_status: "blocked",
      fail_closed: true,
      blocker: "useful checkpoint-F docs path was same-principal and unmediated"
    },
    %{
      id: "accepted-runtime",
      category: "runtime",
      executable_ids: ["protected-launcher"],
      principal: "runtime",
      channel: "launch",
      credential_policy:
        "immutable accepted release capability only; no build/Git/provider/root credential",
      network_policy: "service-specific listener/egress policy, default deny",
      acceptance_probe:
        "FR-17 real start/stop/health/rollback plus listener inspection under _pramana_runtime",
      production_status: "blocked",
      fail_closed: true,
      blocker: "FR-17 activation and immutable release provisioning not complete"
    }
  ]
}
