defmodule PramanaFoundry.WorkPacket do
  @moduledoc """
  Batch D T4 (`docs/batch-d/THIN-LANE-DESIGN-2026-09-23.md` §2): turns replayed store state
  into the manual lane's work packet.

  Pure: no I/O, Git, Gateway or clock. `build/3` takes a kernel ticket already rebuilt by
  replay, an effect fact already read from Core (`protected_query %{"type" => "effect"}`,
  with its `claims`), and a policy fact already read at the effect's `policy_revision`. No
  field of the result is a literal, and none comes from a CLI argument.
  """

  @roles ~w(developer reviewer)
  @packet_keys ~w(schema_version packet_id role ticket_id attempt_id execution_id effect_id
                  request_id claim_id writer_epoch issuer base_revision base_ref title
                  spec_revision_id scope acceptance_criteria checks candidate independence
                  return)
  @independence_keys ~w(policy_id policy_revision independent_of_roles excluded_principals)
  @candidate_keys ~w(candidate_id producer_execution_ids)

  @doc "Builds and validates a work packet from already-read store facts."
  @spec build(ticket :: map(), effect :: map(), policy :: map()) ::
          {:ok, map()} | {:error, atom()}
  def build(ticket, effect, policy) do
    with {:ok, ticket_id} <- ticket_id(ticket),
         {:ok, attempt_id, attempt} <- active_attempt(ticket),
         :ok <- effect_matches_ticket(effect, ticket_id, attempt_id),
         {:ok, role} <- supported_role(effect),
         :ok <- execution_in_attempt(effect, attempt),
         {:ok, claim} <- issued_claim(effect),
         spec = spec_of(ticket),
         {:ok, base_revision} <- base_revision(spec),
         {:ok, scope} <- scope(spec),
         {:ok, acceptance_criteria} <- acceptance_criteria(spec),
         {:ok, checks} <- checks(policy),
         {:ok, candidate} <- candidate(role, attempt),
         {:ok, independence} <- independence(role, policy) do
      packet = %{
        "schema_version" => 1,
        "packet_id" => effect["execution_id"],
        "role" => role,
        "ticket_id" => ticket_id,
        "attempt_id" => attempt_id,
        "execution_id" => effect["execution_id"],
        "effect_id" => effect["effect_id"],
        "request_id" => effect["request_id"],
        "claim_id" => claim["claim_id"],
        "writer_epoch" => claim["writer_epoch"],
        "issuer" => effect["issuer"],
        "base_revision" => base_revision,
        "base_ref" => spec["base_ref"],
        "title" => spec["title"],
        "spec_revision_id" => ticket["spec_revision_id"],
        "scope" => scope,
        "acceptance_criteria" => acceptance_criteria,
        "checks" => checks,
        "candidate" => candidate,
        "independence" => independence,
        "return" => return_of(role, ticket_id)
      }

      with :ok <- validate(packet), do: {:ok, packet}
    end
  end

  @doc "Whether `term` is a well-formed work packet: exactly the declared fields, well-typed."
  @spec validate(term()) :: :ok | {:error, atom()}
  def validate(packet) do
    if valid_packet?(packet), do: :ok, else: {:error, :invalid_packet}
  end

  @doc "Canonical JSON: keys sorted, no whitespace, trailing newline."
  @spec encode(map()) :: binary()
  def encode(packet) do
    {:ok, bytes} = PramanaFoundry.DurableStore.Encoding.canonical(packet)
    bytes <> "\n"
  end

  # ── Ticket ───────────────────────────────────────────────────────────────

  defp ticket_id(ticket) do
    case ticket do
      %{"ticket_id" => id} when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :ticket_not_found}
    end
  end

  defp active_attempt(ticket) do
    attempts = is_map(ticket) && ticket["attempts"]

    with true <- is_map(attempts),
         id when is_binary(id) and id != "" <- ticket["active_attempt_id"],
         {:ok, attempt} <- Map.fetch(attempts, id),
         true <- is_map(attempt) do
      {:ok, id, attempt}
    else
      _ -> {:error, :no_active_attempt}
    end
  end

  defp spec_of(ticket) do
    case ticket["spec"] do
      spec when is_map(spec) -> spec
      _ -> %{}
    end
  end

  # ── Effect ───────────────────────────────────────────────────────────────

  defp effect_matches_ticket(effect, ticket_id, attempt_id) do
    if is_map(effect) and effect["ticket_id"] == ticket_id and effect["attempt_id"] == attempt_id do
      :ok
    else
      {:error, :effect_ticket_mismatch}
    end
  end

  defp supported_role(effect) do
    case effect["role"] do
      role when role in @roles -> {:ok, role}
      _ -> {:error, :unsupported_role}
    end
  end

  defp execution_in_attempt(effect, attempt) do
    executions = attempt["executions"]
    execution_id = effect["execution_id"]

    if is_map(executions) and is_binary(execution_id) and Map.has_key?(executions, execution_id) do
      :ok
    else
      {:error, :execution_not_in_attempt}
    end
  end

  defp issued_claim(effect) do
    claims = effect["claims"]

    issued =
      is_list(claims) &&
        Enum.find(claims, fn c -> is_map(c) and c["status"] == "issued" end)

    case issued do
      %{"claim_id" => claim_id, "writer_epoch" => writer_epoch}
      when is_binary(claim_id) and claim_id != "" and is_binary(writer_epoch) and
             writer_epoch != "" ->
        {:ok, issued}

      _ ->
        {:error, :effect_not_issued}
    end
  end

  # ── Spec ─────────────────────────────────────────────────────────────────

  defp base_revision(spec) do
    case spec["base_revision"] do
      rev when is_binary(rev) and rev != "" ->
        if sha40?(rev), do: {:ok, rev}, else: {:error, :base_revision_not_sha}

      _ ->
        {:error, :base_revision_missing}
    end
  end

  defp scope(spec) do
    case spec["scope"] do
      [_ | _] = scope ->
        if Enum.all?(scope, &nonempty_string?/1),
          do: {:ok, scope},
          else: {:error, :scope_missing}

      _ ->
        {:error, :scope_missing}
    end
  end

  defp acceptance_criteria(spec) do
    case spec["acceptance_criteria"] do
      [_ | _] = criteria ->
        if Enum.all?(criteria, &nonempty_string?/1),
          do: {:ok, criteria},
          else: {:error, :acceptance_missing}

      _ ->
        {:error, :acceptance_missing}
    end
  end

  # ── Candidate ────────────────────────────────────────────────────────────

  defp candidate("developer", _attempt), do: {:ok, nil}

  defp candidate("reviewer", attempt) do
    case attempt["candidate_id"] do
      id when is_binary(id) and id != "" ->
        producer_ids =
          attempt["executions"]
          |> Enum.filter(fn {_id, e} -> match?(%{role: "developer"}, e) end)
          |> Enum.map(fn {id, _e} -> id end)
          |> Enum.sort()

        {:ok, %{"candidate_id" => id, "producer_execution_ids" => producer_ids}}

      _ ->
        {:error, :candidate_missing}
    end
  end

  # ── Policy ───────────────────────────────────────────────────────────────

  defp checks(policy) do
    value = is_map(policy) && policy["value"]
    check_set = is_map(value) && value["check_set"]

    case check_set do
      [] -> {:ok, %{"policy_empty" => true}}
      _ -> {:error, :check_set_not_empty}
    end
  end

  defp independence(role, policy) do
    value = is_map(policy) && policy["value"]
    roles_map = is_map(value) && value["independent_of_roles"]

    cond do
      role == "reviewer" and not is_map(roles_map) ->
        {:error, :independence_policy_missing}

      true ->
        independent_of_roles = if is_map(roles_map), do: Map.get(roles_map, role, []), else: []

        {:ok,
         %{
           "policy_id" => policy["policy_id"],
           "policy_revision" => policy["revision"],
           "independent_of_roles" => independent_of_roles,
           # ponytail: excluded_principals needs the issuers of the attempt's other
           # developer effects, which build/3's (ticket, effect, policy) inputs cannot
           # reach (the kernel ticket carries no principal). Left empty until the caller
           # (W2) threads producer-effect facts through; independence is enforced by Core
           # regardless (protected_primitives.ex:1344), so this is display data only.
           "excluded_principals" => []
         }}
    end
  end

  defp return_of("developer", ticket_id), do: %{"command" => "submit", "ticket_id" => ticket_id}
  defp return_of("reviewer", ticket_id), do: %{"command" => "review", "ticket_id" => ticket_id}

  # ── validate/1 ───────────────────────────────────────────────────────────

  defp valid_packet?(packet) do
    is_map(packet) and
      Enum.sort(Map.keys(packet)) == Enum.sort(@packet_keys) and
      packet["schema_version"] == 1 and
      nonempty_string?(packet["packet_id"]) and
      packet["role"] in @roles and
      nonempty_string?(packet["ticket_id"]) and
      nonempty_string?(packet["attempt_id"]) and
      nonempty_string?(packet["execution_id"]) and
      nonempty_string?(packet["effect_id"]) and
      nonempty_string?(packet["request_id"]) and
      nonempty_string?(packet["claim_id"]) and
      nonempty_string?(packet["writer_epoch"]) and
      nonempty_string?(packet["issuer"]) and
      sha40?(packet["base_revision"]) and
      nonempty_string?(packet["base_ref"]) and
      nonempty_string?(packet["title"]) and
      nonempty_string?(packet["spec_revision_id"]) and
      nonempty_string_list?(packet["scope"]) and
      nonempty_string_list?(packet["acceptance_criteria"]) and
      packet["checks"] == %{"policy_empty" => true} and
      valid_candidate?(packet["role"], packet["candidate"]) and
      valid_independence?(packet["independence"]) and
      valid_return?(packet["role"], packet["return"], packet["ticket_id"])
  end

  defp valid_candidate?("developer", nil), do: true

  defp valid_candidate?("reviewer", candidate) when is_map(candidate) do
    Enum.sort(Map.keys(candidate)) == Enum.sort(@candidate_keys) and
      nonempty_string?(candidate["candidate_id"]) and
      is_list(candidate["producer_execution_ids"]) and
      Enum.all?(candidate["producer_execution_ids"], &nonempty_string?/1)
  end

  defp valid_candidate?(_role, _candidate), do: false

  defp valid_independence?(independence) do
    is_map(independence) and
      Enum.sort(Map.keys(independence)) == Enum.sort(@independence_keys) and
      nonempty_string?(independence["policy_id"]) and
      is_integer(independence["policy_revision"]) and independence["policy_revision"] >= 0 and
      is_list(independence["independent_of_roles"]) and
      Enum.all?(independence["independent_of_roles"], &nonempty_string?/1) and
      is_list(independence["excluded_principals"]) and
      Enum.all?(independence["excluded_principals"], &nonempty_string?/1)
  end

  defp valid_return?("developer", return, ticket_id) when is_map(return) do
    Map.keys(return) |> Enum.sort() == ["command", "ticket_id"] and
      return["command"] == "submit" and return["ticket_id"] == ticket_id
  end

  defp valid_return?("reviewer", return, ticket_id) when is_map(return) do
    Map.keys(return) |> Enum.sort() == ["command", "ticket_id"] and
      return["command"] == "review" and return["ticket_id"] == ticket_id
  end

  defp valid_return?(_role, _return, _ticket_id), do: false

  defp nonempty_string?(v), do: is_binary(v) and v != ""

  defp nonempty_string_list?(v),
    do: is_list(v) and v != [] and Enum.all?(v, &nonempty_string?/1)

  defp sha40?(v), do: is_binary(v) and String.match?(v, ~r/\A[0-9a-f]{40}\z/)
end
