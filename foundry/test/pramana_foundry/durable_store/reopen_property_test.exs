defmodule PramanaFoundry.DurableStore.ReopenPropertyTest do
  # A committed state must survive reopen. On 2026-09-23 six accepted states were refused by
  # the restart check (ProtectedPrimitives.validate, run on open), one probe test each. This
  # drives seeded random sequences of protected operations over a small id space through the
  # real Gateway, reopens at random midpoints and at the end, and requires mode :ready.
  #
  # FOUNDRY_REOPEN_RUNS (default 150) sets the number of sequences, FOUNDRY_REOPEN_SEED (default 1)
  # the base seed; sequence i uses seed base + i, so a printed seed replays alone with RUNS=1.
  # FOUNDRY_REOPEN_STATS=1 prints outcomes per operation type. A command that drops the live
  # gateway into recovery also fails the sequence.
  #
  # Red at d0cc0037 on two unfixed findings (seeds 49 and 56): reset_generation of a root ledger
  # that has delegated to a child, and create_effect after an owned proposed reservation was
  # released. Red controls: dropping cancel_effect's ledgers (d67eeac2) fails seed 1; dropping
  # set_control's cascaded ledgers (487e83b4) fails seed 3.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  @epoch "writer-epoch-fr08a"
  @ledgers ~w(L0 L1 L2)
  @effects ~w(e0 e1 e2 e3)
  @receipts ~w(rc0 rc1 rc2)
  @controls ~w(k0 k1)
  @executions ~w(x0 x1)
  @attempts ~w(a0 a1 a2)

  @operation_types ~w(append_inbox cancel_effect claim_effect close_attempt close_generation
                      create_effect delegate_allocation grant_ledger issue_claim
                      release_reservation reserve reset_generation return_allocation
                      seal_inbox set_control set_policy settle_claim)

  @moduletag timeout: :infinity

  test "every committed state reopens :ready" do
    runs = env_int("FOUNDRY_REOPEN_RUNS", 150)
    base = env_int("FOUNDRY_REOPEN_SEED", 1)

    # Every failing seed is kept; the first seed of each distinct verdict is minimized.
    failures =
      for seed <- base..(base + runs - 1),
          ops = generate(seed),
          failure = execute(ops),
          failure != :ok,
          do: {seed, ops, failure}

    if System.get_env("FOUNDRY_REOPEN_STATS"),
      do:
        IO.inspect(Enum.sort(Process.get(:tally, %{})),
          label: "operation outcomes",
          limit: :infinity
        )

    # A green run means little for an operation the store never accepted (review B1:
    # set_control was unreachable and return_allocation never accepted). Checked on the
    # default budget and above, where every type should occur.
    if runs >= 150 do
      tally = Process.get(:tally, %{})
      accepted = for {{type, "accepted"}, _n} <- tally, into: MapSet.new(), do: type
      never = Enum.reject(@operation_types, &(&1 in accepted))
      assert never == [], "never accepted in #{runs} runs: #{inspect(never)}"
    end

    if failures != [] do
      reports =
        failures
        |> Enum.group_by(fn {_seed, _ops, {kind, _i, verdict}} -> {kind, verdict} end)
        |> Enum.map(fn {verdict, [{seed, ops, _} | _] = group} ->
          minimal = minimize(ops)

          """
          #{inspect(verdict)}
          seeds #{inspect(Enum.map(group, &elem(&1, 0)), charlists: :as_lists)}; replay: FOUNDRY_REOPEN_SEED=#{seed} FOUNDRY_REOPEN_RUNS=1
          minimal operations (#{length(minimal)} of #{length(ops)}), then reopen:
          #{inspect(minimal, pretty: true, limit: :infinity, printable_limit: :infinity)}
          minimal failure: #{inspect(execute(minimal))}
          """
        end)

      flunk("#{length(failures)} of #{runs} sequences failed\n\n" <> Enum.join(reports, "\n"))
    end
  end

  defp env_int(name, default),
    do: String.to_integer(System.get_env(name) || Integer.to_string(default))

  ## Generation

  defp generate(seed) do
    :rand.seed(:exsss, {seed, seed, seed})

    seeds = [
      set_policy("p0", true),
      set_control("k0", "active"),
      set_control("k1", "active"),
      grant("L0", 0, 6),
      grant("L1", 0, 4)
    ]

    seeds ++ Enum.flat_map(1..(20 + :rand.uniform(20)), fn _ -> List.wrap(operation()) end)
  end

  defp operation do
    case :rand.uniform(100) do
      n when n <= 3 -> :reopen
      n when n <= 11 -> pipeline(pick(@effects))
      n when n <= 12 -> set_policy(pick(~w(p0 p1)), :rand.uniform(4) > 1)
      n when n <= 14 -> set_control(pick(@controls), pick(~w(active active cancel_requested)))
      n when n <= 15 -> grant(pick(@ledgers), gen(), :rand.uniform(3))
      n when n <= 17 -> delegate()
      n when n <= 18 -> return()
      n when n <= 19 -> round_trip()
      n when n <= 30 -> reserve()
      n when n <= 36 -> release()
      n when n <= 46 -> create_effect()
      n when n <= 60 -> claim()
      n when n <= 68 -> issue()
      n when n <= 74 -> cancel()
      n when n <= 86 -> settle()
      n when n <= 89 -> close_generation()
      n when n <= 93 -> reset()
      n when n <= 95 -> close_attempt()
      _ -> inbox()
    end
  end

  defp pick(list), do: Enum.random(list)
  defp gen, do: pick([0, 0, 1])
  defp often, do: :rand.uniform(5) > 1
  defp ledger, do: if(often(), do: pick(~w(L0 L1)), else: pick(@ledgers))

  # Reservations are usually named after, and owned by, their effect, so create_effect can
  # list them; a random owner or listing still makes the mismatch refusals reachable.
  defp reservation(effect), do: "r-#{effect}-#{:rand.uniform(2) - 1}"

  # One effect driven to pending, claimed or issued, then usually ended by the matching
  # settlement or cancel proof, or by a cancel of its control; deep states are common, not rare.
  defp pipeline(effect) do
    control = pick(@controls)
    depth = pick([2, 3, 4, 4])
    rid = reservation(effect)

    hold =
      Map.merge(reserve(effect), %{
        "reservation_id" => rid,
        "ledger_id" => pick(~w(L0 L1)),
        "generation" => 0,
        "owner_id" => effect,
        "units" => 1
      })

    create =
      Map.merge(create_effect(effect, control), %{
        "attempt_id" => "a-" <> effect,
        "policy_revision" => :current,
        "control_revision" => :current,
        "reservation_ids" => [rid]
      })

    steps = [hold, create, claim(effect), issue(effect)]
    proof = Enum.at(~w(unissued unissued issuer_quiescent control_ack), depth - 1)

    ending =
      pick([
        [],
        [settle(effect)],
        [settle(effect), settle(effect)],
        [cancel(effect, proof)],
        [set_control(control, "cancel_requested"), set_control(control, "active")]
      ])

    Enum.take(steps, depth) ++ ending
  end

  defp set_policy(id, allow) do
    scopes = if allow, do: ["ticket:T0"], else: []

    %{
      "type" => "set_policy",
      "policy_id" => id,
      "value" => %{"allowed_operations" => ["launch"], "allowed_scopes" => scopes}
    }
  end

  defp set_control(id, status),
    do: %{"type" => "set_control", "control_id" => id, "value" => %{"status" => status}}

  defp grant(ledger, generation, units),
    do: %{
      "type" => "grant_ledger",
      "ledger_id" => ledger,
      "generation" => generation,
      "dimension" => "starts.developer",
      "units" => units
    }

  defp delegate do
    [parent, child] = Enum.take_random(@ledgers, 2)

    %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => parent,
      "parent_generation" => gen(),
      "child_ledger_id" => child,
      "child_generation" => gen(),
      "dimension" => "starts.developer",
      "units" => :rand.uniform(2)
    }
  end

  # A delegation followed by a return of what it delegated, so return_allocation is
  # accepted: a random return almost never names a child that holds nothing and delegates
  # nothing (review B1: 0 of 46 accepted before this).
  defp round_trip do
    delegation = %{delegate() | "units" => 1}

    [
      delegation,
      %{
        "type" => "return_allocation",
        "child_ledger_id" => delegation["child_ledger_id"],
        "child_generation" => delegation["child_generation"],
        "units" => 1
      }
    ]
  end

  defp return,
    do: %{
      "type" => "return_allocation",
      "child_ledger_id" => ledger(),
      "child_generation" => gen(),
      "units" => :rand.uniform(2)
    }

  defp reserve(effect \\ pick(@effects)),
    do: %{
      "type" => "reserve",
      "reservation_id" => reservation(effect),
      "ledger_id" => ledger(),
      "generation" => if(often(), do: 0, else: 1),
      "owner_kind" => "effect",
      "owner_id" => if(often(), do: effect, else: pick(@effects)),
      "units" => :rand.uniform(2)
    }

  defp release,
    do: %{
      "type" => "release_reservation",
      "reservation_id" => reservation(pick(@effects)),
      "proof" => "unissued"
    }

  defp create_effect(effect \\ pick(@effects), control \\ pick(@controls)) do
    %{
      "type" => "create_effect",
      "effect_id" => effect,
      "request" => %{
        "request_id" => "request-" <> effect,
        "role" => "developer",
        "profile" => "sol"
      },
      "operation" => "launch",
      "scope" => "ticket:T0",
      "ticket_id" => "T0",
      "attempt_id" => if(often(), do: "a-" <> effect, else: pick(@attempts)),
      "execution_id" => pick(@executions),
      "policy_id" => "p0",
      "policy_revision" => if(often(), do: :current, else: 0),
      "control_id" => control,
      "control_revision" => if(often(), do: :current, else: 0),
      "reservation_ids" =>
        Enum.uniq([
          reservation(effect) | if(often(), do: [], else: [reservation(pick(@effects))])
        ]),
      "leases" => [%{"lease_id" => "lease-" <> effect, "resource_id" => pick(~w(slot0 slot1))}]
    }
  end

  # Claims are usually named after their effect, so settlement can find the request id.
  defp claim(effect \\ pick(@effects)) do
    %{
      "type" => "claim_effect",
      "effect_id" => effect,
      "claim_id" => "c-" <> if(often(), do: effect, else: pick(@effects)),
      "writer_epoch" => @epoch
    }
  end

  defp issue(effect \\ pick(@effects)),
    do: %{"type" => "issue_claim", "claim_id" => "c-" <> effect, "writer_epoch" => @epoch}

  defp cancel(effect \\ pick(@effects), proof \\ pick(~w(unissued issuer_quiescent control_ack))),
    do: %{"type" => "cancel_effect", "effect_id" => effect, "proof" => proof}

  @proof %{
    "succeeded" => "delivered",
    "failed" => "delivered",
    "non_started" => "issuer_quiescent",
    "unknown" => "outcome_unknown"
  }

  # Every outcome; receipt ids are shared across claims, so reuse and conflicts happen.
  defp settle(effect \\ pick(@effects)) do
    outcome = pick(~w(succeeded failed non_started unknown))

    %{
      "type" => "settle_claim",
      "claim_id" => "c-" <> effect,
      "receipt_id" => pick(@receipts),
      "request_id" => "request-" <> if(often(), do: effect, else: pick(@effects)),
      "outcome" => outcome,
      "proof" => if(often(), do: @proof[outcome], else: pick(Map.values(@proof))),
      "payload" => %{"provider" => "synthetic-fixture"}
    }
  end

  defp close_generation,
    do: %{"type" => "close_generation", "ledger_id" => ledger(), "generation" => gen()}

  defp reset do
    ledger = ledger()
    old = gen()
    parent = if :rand.uniform(2) == 1, do: nil, else: pick(@ledgers -- [ledger])

    %{
      "type" => "reset_generation",
      "ledger_id" => ledger,
      "old_generation" => old,
      "new_generation" => if(often(), do: old + 1, else: gen()),
      "parent_ledger_id" => parent,
      "parent_generation" => if(parent, do: gen()),
      "units" => :rand.uniform(2)
    }
  end

  defp close_attempt,
    do: %{
      "type" => "close_attempt",
      "scope" => "ticket:T0",
      "ticket_id" => "T0",
      "attempt_id" => pick(@attempts ++ Enum.map(@effects, &("a-" <> &1)))
    }

  defp inbox do
    if :rand.uniform(4) == 1 do
      %{
        "type" => "seal_inbox",
        "execution_id" => pick(@executions),
        "last_sequence" => :rand.uniform(4) - 1
      }
    else
      %{
        "type" => "append_inbox",
        "execution_id" => pick(@executions),
        "sequence" => :rand.uniform(3),
        "item_kind" => pick(~w(observation observation result)),
        "payload" => %{"note" => "n"}
      }
    end
  end

  ## Execution: :ok, or the first reopen that was not :ready (or a gateway exit).

  defp execute(ops) do
    root =
      Path.join(
        "/private/tmp",
        "reopen-prop-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")

    try do
      :ok =
        Gateway.initialize(path,
          installation_id: "installation-fr08a",
          repository_id: "repository-fr08a"
        )

      capability = make_ref()
      {:ok, gw} = open(path, capability)

      ops
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, gw}, fn
        {:reopen, i}, {:ok, gw} -> reopen(gw, path, capability, i)
        {op, i}, {:ok, gw} -> run(gw, path, capability, op, i)
      end)
      |> case do
        {:ok, gw} ->
          case reopen(gw, path, capability, length(ops)) do
            {:cont, {:ok, gw}} -> GenServer.stop(gw)
            {:halt, failure} -> failure
          end

        failure ->
          failure
      end
    after
      File.rm_rf!(root)
    end
  end

  # Unlinked, so a crash is reported with its seed instead of killing the test.
  defp open(path, capability),
    do:
      GenServer.start(Gateway,
        path: path,
        protected_capability: capability,
        writer_epoch: @epoch
      )

  defp reopen(gw, path, capability, i) do
    GenServer.stop(gw)
    {:ok, gw} = open(path, capability)

    case Gateway.status(gw) do
      %{mode: :ready} ->
        {:cont, {:ok, gw}}

      status ->
        GenServer.stop(gw)
        {:halt, {:not_ready_at, i, Map.take(status, [:mode, :reason])}}
    end
  end

  # Accepted or refused does not matter while the gateway stays live; the next reopen decides.
  defp run(gw, _path, capability, op, i) do
    op = resolve(gw, capability, op)

    result =
      case protected(gw, capability, "C#{i}-PROBE", %{}, op) do
        {:ok, %{"reason_code" => "incomplete_read_set", "facts" => facts}, _} ->
          protected(gw, capability, "C#{i}", facts["required_revisions"], op)

        other ->
          other
      end

    tally(op["type"], result)

    # A command that drops the live gateway into recovery fails the sequence; four such
    # refusals were fixed on 2026-09-23 (live_refusal_probe_test.exs).
    if match?({:error, {:storage_unavailable, _}}, result),
      do: {:halt, {:live_recovery_at, i, result}},
      else: {:cont, {:ok, gw}}
  catch
    :exit, reason -> {:halt, {:gateway_exit_at, i, reason}}
  end

  # Counts each operation type's outcomes for FOUNDRY_REOPEN_STATS=1.
  defp tally(type, result) do
    outcome =
      case result do
        {:ok, %{"disposition" => "accepted"}, _} -> "accepted"
        {:ok, %{"reason_code" => reason}, _} -> reason
        other -> inspect(other)
      end

    Process.put(:tally, Map.update(Process.get(:tally, %{}), {type, outcome}, 1, &(&1 + 1)))
  end

  # create_effect usually names the current policy and control revisions, so it can succeed.
  defp resolve(gw, capability, %{"type" => "create_effect"} = op) do
    op
    |> revision(gw, capability, {"policy_revision", "policy", "policy_id"})
    |> revision(gw, capability, {"control_revision", "control", "control_id"})
  end

  defp resolve(_gw, _capability, op), do: op

  defp revision(op, gw, capability, {field, type, key}) do
    query = %{"schema_version" => 1, "type" => type, key => op[key]}

    case {op[field], Gateway.protected_query(gw, capability, query)} do
      {:current, {:ok, %{"revision" => r}}} -> Map.put(op, field, r)
      {:current, _} -> Map.put(op, field, 0)
      _ -> op
    end
  end

  defp protected(gw, capability, id, reads, op) do
    Gateway.protected_command(gw, capability, "operator", %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => op
    })
  end

  ## Minimization: cut after the failure, drop midpoint reopens, then drop one operation at a
  ## time, each only while the same verdict still fails.

  defp minimize(ops) do
    {kind, i, verdict} = execute(ops)
    same? = &match?({^kind, _, ^verdict}, execute(&1))
    ops = Enum.take(ops, i + 1)
    without_reopens = Enum.reject(ops, &(&1 == :reopen))
    shrink(if(same?.(without_reopens), do: without_reopens, else: ops), 0, same?)
  end

  defp shrink(ops, i, _same?) when i >= length(ops), do: ops

  defp shrink(ops, i, same?) do
    candidate = List.delete_at(ops, i)
    if same?.(candidate), do: shrink(candidate, i, same?), else: shrink(ops, i + 1, same?)
  end
end
