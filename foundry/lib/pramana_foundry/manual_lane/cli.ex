defmodule PramanaFoundry.ManualLane.CLI do
  @moduledoc """
  T5, the manual-lane CLI (`docs/batch-d/THIN-LANE-DESIGN-2026-09-23.md` §4):
  `bin/pramana lane admit|packet|submit|review|settle|status`, routed here by `CLI.RPC`.

  It runs in the daemon's BEAM against the flag-started `ManualLane.Server`, and only
  translates arguments into `ManualLane.Backend` calls. Output is human-readable, or one
  JSON object with `--json`. A refusal prints its atom and raises, so the release `rpc`
  exits non-zero, as the legacy CLI does.
  """

  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.GitEvidence
  alias PramanaFoundry.ManualLane.{Backend, Replay, Server}
  alias PramanaFoundry.WorkPacket
  alias PramanaFoundry.Workflow.Kernel.Execution

  # Per command: its option switches and whether the ticket id is required.
  @commands %{
    "admit" =>
      {[base_ref: :string, title: :string, scope: :string, acceptance: :keep], :required},
    "packet" => {[role: :string, principal: :string, out: :string], :required},
    "submit" =>
      {[principal: :string, candidate: :string, checkout: :string, blocked: :string], :required},
    "review" =>
      {[principal: :string, verdict: :string, candidate: :string, notes: :string], :required},
    "settle" =>
      {[
         role: :string,
         principal: :string,
         outcome: :string,
         attest: :string,
         issuer_gone: :boolean,
         channel_quiet: :boolean
       ], :required},
    "status" => {[], :optional}
  }

  @required %{
    "admit" => [:base_ref, :title, :scope, :acceptance],
    "packet" => [:principal, :role],
    "submit" => [:principal, :candidate, :checkout],
    "review" => [:principal, :verdict, :candidate, :notes],
    "settle" => [:principal, :role, :outcome, :attest],
    "status" => []
  }

  @roles ~w(developer reviewer)
  @verdicts ~w(approved correction rejected)
  @outcomes %{"non_started" => :non_started, "unknown" => :unknown}
  @awaiting_operator ~w(issued unknown reconciliation_required)

  @doc "Runs one lane command (argv after `lane`), prints its result, raises on refusal."
  def main(argv) do
    json? = "--json" in argv

    case run(argv) do
      {:ok, result} ->
        IO.write(render(Map.put(result, "ok", true), json?))

      {:error, reason, detail} ->
        IO.write(
          render(%{"ok" => false, "error" => to_string(reason), "detail" => detail}, json?)
        )

        raise "lane #{List.first(argv)} refused: #{reason}"
    end
  end

  @doc "Parses lane argv into `{:ok, command, ticket_id | nil, opts}`; the RPC shape check."
  def parse([command | rest]) when is_map_key(@commands, command) do
    {switches, id_rule} = @commands[command]
    # `:keep` so a repeated option is seen and refused rather than silently last-wins.
    strict = for {key, type} <- switches, do: {key, if(type == :string, do: :keep, else: type)}

    case OptionParser.parse(rest, strict: [{:json, :boolean} | strict]) do
      {opts, args, []} ->
        repeated = Keyword.keys(opts) -- Enum.uniq(Keyword.keys(opts))

        cond do
          Enum.any?(repeated, &(&1 != :acceptance)) -> {:error, :unknown_command_shape}
          match?([_], args) -> {:ok, command, hd(args), opts}
          args == [] and id_rule == :optional -> {:ok, command, nil, opts}
          true -> {:error, :unknown_command_shape}
        end

      _ ->
        {:error, :unknown_command_shape}
    end
  end

  def parse(_argv), do: {:error, :unknown_command_shape}

  @doc "Runs one lane command without printing: `{:ok, map}` or `{:error, atom, detail}`."
  def run(argv) do
    with {:ok, command, id, opts} <- parse(argv) |> refusal(),
         :ok <- required(command, opts),
         {:ok, ctx} <- context() do
      command(command, ctx, id, opts)
    end
  end

  # ── Commands ──────────────────────────────────────────────────────────────────

  defp command("admit", ctx, id, opts) do
    ref = opts[:base_ref]

    with {:ok, base} <- rev_parse(ctx.repo, ref) do
      spec = %{
        "base_revision" => base,
        "base_ref" => ref,
        "title" => opts[:title],
        "scope" => String.split(opts[:scope], ",", trim: true),
        "acceptance_criteria" => Keyword.get_values(opts, :acceptance)
      }

      with {:ok, _} <- Backend.admit(ctx, id, spec) |> refusal() do
        ticket = ticket(ctx, id)

        {:ok,
         %{
           "ticket_id" => id,
           "base_revision" => ticket["spec"]["base_revision"],
           "spec_revision_id" => ticket["spec_revision_id"]
         }}
      end
    end
  end

  defp command("packet", ctx, id, opts) do
    with :ok <- one_of(opts[:role], @roles, :unsupported_role),
         {:ok, result} <- Backend.launch(ctx, id, opts[:role], opts[:principal]) |> refusal() do
      case result do
        %{"packet_id" => _} = packet ->
          write_packet(packet, opts[:out])

        %{"ticket" => t} ->
          {:ok, %{"packet" => nil, "phase" => t["phase"], "reason" => t["reason"]}}
      end
    end
  end

  defp command("submit", ctx, id, opts) do
    principal = opts[:principal]
    candidate = opts[:candidate]

    with %{} = ticket <- ticket(ctx, id) || {:error, :ticket_not_found, nil},
         :ok <- git_evidence(opts[:checkout], candidate, ticket["spec"]["base_revision"]),
         receipt =
           attestation(principal, "delivered candidate #{candidate}")
           |> Map.put("candidate_id", candidate)
           |> Map.merge(if opts[:blocked], do: %{"blocked" => opts[:blocked]}, else: %{}),
         {:ok, _} <- Backend.deliver(ctx, id, "developer", principal, receipt) |> refusal(),
         {:ok, _} <- freeze(ctx, id, principal, candidate, opts[:blocked]) do
      t = ticket(ctx, id)
      {:ok, %{"phase" => t["phase"], "candidate_id" => candidate}}
    end
  end

  defp command("review", ctx, id, opts) do
    principal = opts[:principal]
    verdict = opts[:verdict]
    candidate = opts[:candidate]

    with :ok <- one_of(verdict, @verdicts, :invalid_verdict),
         {:ok, notes} <- read_notes(opts[:notes]),
         receipt =
           attestation(principal, "review verdict #{verdict} on candidate #{candidate}")
           |> Map.merge(%{"verdict" => verdict, "notes_sha256" => sha256(notes)}),
         {:ok, %{"ticket" => t}} <-
           Backend.review(ctx, id, principal, verdict, candidate, receipt) |> refusal() do
      {:ok, %{"phase" => t["phase"], "verdict" => verdict, "candidate_id" => candidate}}
    end
  end

  defp command("settle", ctx, id, opts) do
    principal = opts[:principal]

    with :ok <- one_of(opts[:role], @roles, :unsupported_role),
         :ok <- one_of(opts[:outcome], Map.keys(@outcomes), :invalid_outcome),
         attestation =
           attestation(principal, opts[:attest])
           |> Map.merge(
             Map.new(Keyword.take(opts, [:issuer_gone, :channel_quiet]), fn {k, v} ->
               {to_string(k), v}
             end)
           ),
         {:ok, result} <-
           Backend.settle(ctx, id, opts[:role], principal, @outcomes[opts[:outcome]], attestation)
           |> refusal() do
      {:ok,
       %{
         "phase" => ticket(ctx, id)["phase"],
         "outcome" => opts[:outcome],
         "selected_discriminator" => result["selected_discriminator"]
       }}
    end
  end

  defp command("status", ctx, id, _opts) do
    tickets = Backend.state(ctx)["tickets"]

    # Only lane tickets exist in the lane's store: admission refuses any other id.
    selected = if id, do: Map.take(tickets, [id]), else: tickets

    if id && selected == %{} do
      {:error, :ticket_not_found, nil}
    else
      {:ok,
       %{
         "mode" => to_string(Gateway.status(ctx.gateway).mode),
         "tickets" => Map.new(selected, fn {tid, t} -> {tid, ticket_status(ctx, t)} end)
       }}
    end
  end

  defp ticket_status(ctx, ticket) do
    attempts =
      Map.new(ticket["attempts"] || %{}, fn {attempt_id, attempt} ->
        executions =
          for {execution_id, %Execution{} = e} <- attempt["executions"] || %{} do
            effect_id = String.replace_suffix(execution_id, "/execution", "/effect")

            effect =
              case Replay.query(ctx, %{"type" => "effect", "effect_id" => effect_id}) do
                {:ok, effect} -> effect
                _ -> %{}
              end

            %{
              "execution_id" => execution_id,
              "role" => e.role,
              "lifecycle" => e.lifecycle,
              "effect_status" => effect["status"],
              "issuer" => effect["issuer"],
              "awaits_operator" => effect["status"] in @awaiting_operator
            }
          end

        {attempt_id,
         %{
           "phase" => attempt["phase"],
           "candidate_id" => attempt["candidate_id"],
           "verdict" => get_in(attempt, ["review", "verdict"]),
           "executions" => Enum.sort_by(executions, & &1["execution_id"])
         }}
      end)

    %{
      "phase" => ticket["phase"],
      "reason" => ticket["reason"],
      "active_attempt_id" => ticket["active_attempt_id"],
      "attempts" => attempts
    }
  end

  # ── Steps ─────────────────────────────────────────────────────────────────────

  # The developer's result as ingress (Q1, Q4: a second commit after the receipt). Its id
  # names the execution, so a rerun after a split replays as idempotent.
  defp freeze(ctx, id, principal, candidate, blocked) do
    ticket = ticket(ctx, id)
    attempt_id = ticket["active_attempt_id"]
    attempt = get_in(ticket, ["attempts", attempt_id]) || %{}

    open =
      for {eid, %Execution{role: "developer", lifecycle: l}} <- attempt["executions"] || %{},
          l != "closed",
          do: eid

    case open do
      [execution_id] ->
        base = %{"ticket_id" => id, "attempt_id" => attempt_id}
        exec = Map.put(base, "execution_id", execution_id)
        observation = %{"observation_id" => execution_id <> "/freeze"}

        result =
          if blocked,
            do: [
              {"artifact_blocked",
               Map.merge(base, observation)
               |> Map.merge(%{"result" => "blocked", "reason" => blocked})}
            ],
            else: [
              {"artifact_frozen",
               Map.merge(base, observation)
               |> Map.merge(%{"candidate_id" => candidate, "sealed_generation" => candidate})}
            ]

        closing =
          [
            {"stream_sealed", Map.put(exec, "last_accepted_sequence", 0)},
            {"developer_closed", exec}
          ] ++
            if(blocked, do: [], else: [{"checks_started", Map.put(base, "policy_empty", true)}])

        Backend.ingress(ctx, "#{id}/freeze/#{execution_id}", id, result ++ closing, principal)
        |> refusal()

      # Already frozen and closed: a rerun of a completed submit.
      [] when is_binary(attempt_id) ->
        if attempt["candidate_id"] == candidate or blocked,
          do: {:ok, %{"idempotent" => true}},
          else: {:error, :candidate_mismatch, attempt["candidate_id"]}

      _ ->
        {:error, :no_issued_claim, nil}
    end
  end

  defp write_packet(packet, nil), do: {:ok, %{"packet" => packet}}

  defp write_packet(packet, path) do
    case File.write(path, WorkPacket.encode(packet)) do
      :ok -> {:ok, %{"packet" => packet, "out" => path}}
      {:error, reason} -> {:error, :packet_write_failed, to_string(reason)}
    end
  end

  # ── Guards ────────────────────────────────────────────────────────────────────

  # The principal never defaults (§4). Checked before any Gateway call.
  defp required(command, opts) do
    case Enum.reject(@required[command], &(opts[&1] not in [nil, ""])) do
      [] -> :ok
      [:principal | _] -> {:error, :principal_required, nil}
      missing -> {:error, :option_required, Enum.map(missing, &option_name/1)}
    end
  end

  defp context do
    if Process.whereis(Server) do
      ctx = Server.context()

      case Gateway.status(ctx.gateway) do
        %{mode: :ready} -> {:ok, Map.put(ctx, :path, ctx.store_path)}
        %{reason: reason} -> {:error, :gateway_recovery, inspect(reason)}
      end
    else
      {:error, :lane_disabled, nil}
    end
  end

  defp rev_parse(repo, ref) do
    case System.cmd("git", ["-C", repo, "rev-parse", "--verify", "--quiet", ref <> "^{commit}"],
           stderr_to_stdout: true
         ) do
      {sha, 0} -> {:ok, String.trim(sha)}
      _ -> {:error, :git_ref_unresolved, ref}
    end
  end

  defp git_evidence(checkout, candidate, base) do
    case GitEvidence.validate_checkout(checkout, candidate, base) do
      :ok -> :ok
      {:error, message} -> {:error, :git_evidence, message}
    end
  end

  defp read_notes(path) do
    case File.read(path) do
      {:ok, notes} -> {:ok, notes}
      {:error, reason} -> {:error, :notes_unreadable, to_string(reason)}
    end
  end

  defp one_of(value, allowed, reason),
    do: if(value in allowed, do: :ok, else: {:error, reason, value})

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp ticket(ctx, id), do: Backend.state(ctx)["tickets"][id]

  # A1: every receipt the human asserts says so, by whom, and what.
  defp attestation(principal, statement) do
    %{
      "evidence_kind" => "operator_attestation",
      "attested_by" => principal,
      "statement" => statement
    }
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp option_name(key), do: "--" <> String.replace(to_string(key), "_", "-")

  defp refusal({:reject, reason}), do: {:error, reason, nil}
  defp refusal({:error, reason}) when is_atom(reason), do: {:error, reason, nil}
  defp refusal({:error, reason}), do: {:error, :refused, inspect(reason)}
  defp refusal(ok), do: ok

  # ── Output ────────────────────────────────────────────────────────────────────

  defp render(result, true), do: JSON.encode!(result) <> "\n"

  defp render(result, false) do
    result
    |> Map.delete("ok")
    |> Enum.sort()
    |> Enum.map_join(fn {key, value} -> "#{key}: #{human(value)}\n" end)
    |> then(&if(result["ok"], do: &1, else: "refused\n" <> &1))
  end

  defp human(value) when is_binary(value), do: value
  defp human(nil), do: "-"

  defp human(value) when is_map(value) or is_list(value),
    do: :json.format(value) |> IO.iodata_to_binary()

  defp human(value), do: to_string(value)
end
