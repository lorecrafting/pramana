defmodule PramanaFoundry.Observations do
  @moduledoc """
  Minimal honest query surface over FR-08A protected facts.

  This module does not read legacy projections and does not infer activation. The
  accepted-source, selected-deployment and healthy-build slots are reported as three
  separate root facts, including their honest `absent` producer state.
  """

  alias PramanaFoundry.Observations.{GatewaySource, Observation, Page, Query}

  @pointer_kinds ~w(accepted_source selected_deployment healthy_build)
  @max_effect_ids 200
  @max_id_bytes 256
  @max_limit 50
  @min_page_bytes 8_192
  @max_page_bytes 262_144
  @max_related_ids 20
  @protected_envelope_reserve 4_096
  @version_fields ~w(sql_schema_version protected_schema_version protocol_version event_version projection_version)
  @supported_versions %{
    "sql_schema_version" => "1",
    "protected_schema_version" => "3",
    "protocol_version" => "1",
    "event_version" => "1",
    "projection_version" => "1"
  }
  @effect_statuses ~w(pending claimed issued unknown reconciliation_required succeeded failed non_started cancelled)
  @claim_statuses ~w(claimed issued unknown reconciliation_required succeeded failed non_started cancelled)
  @receipt_outcomes ~w(succeeded failed non_started unknown)
  @control_statuses ~w(active cancel_requested)
  @execution_statuses ~w(open result exit sealed_without_result_or_exit)

  @effect_fields ~w(effect_id ticket_id attempt_id execution_id control_id policy_id request_id assignment_id role operation scope profile channel status revision policy_revision control_revision phase_generation operation_ordinal predecessor_effect_id)

  @doc "Queries a live protected Gateway with a bounded typed request."
  @spec query(Query.t(), pid() | atom(), term(), keyword()) :: Page.t()
  def query(%Query{} = request, gateway, capability, opts \\ []) do
    source = {GatewaySource, %{gateway: gateway, capability: capability}}
    query_source(request, source, opts)
  end

  @doc false
  @spec query_source(Query.t(), {module(), term()}, keyword()) :: Page.t()
  def query_source(request, source, opts \\ [])

  def query_source(%Query{} = request, {adapter, source_state}, opts)
      when is_atom(adapter) do
    with :ok <- validate_query(request),
         {:ok, before, _before_at} <- adapter.snapshot(source_state),
         {:ok, source} <- canonical_source(before),
         {:ok, targets} <- targets(request, before),
         {:ok, items, effect_cursor} <-
           read_targets(adapter, source_state, targets, request, source),
         {:ok, after_snapshot, after_at} <- adapter.snapshot(source_state),
         {:ok, after_source} <- canonical_source(after_snapshot),
         :ok <- stable_source(source, after_source),
         now <- Keyword.get(opts, :now, DateTime.utc_now()),
         true <- match?(%DateTime{}, now),
         {:ok, freshness} <- freshness(after_at, now, request.max_age_ms) do
      build_page(request, source, items, after_at, freshness, targets, effect_cursor)
    else
      {:error, :invalid_query} -> error_page(:corrupt, :invalid_query)
      false -> error_page(:corrupt, :invalid_clock)
      {:error, :unavailable} -> error_page(:unavailable, :source_unavailable)
      {:error, :not_found} -> error_page(:corrupt, :source_snapshot_missing)
      {:error, :corrupt} -> error_page(:corrupt, :source_corrupt)
      {:error, :source_changed} -> error_page(:unavailable, :source_changed_during_query)
      {:error, :stale} -> error_page(:unavailable, :stale_protected_cursor)
      {:error, :oversized} -> error_page(:unavailable, :protected_observation_oversized)
      {:error, :invalid_freshness} -> error_page(:corrupt, :invalid_freshness)
      {:error, _reason} -> error_page(:corrupt, :source_corrupt)
    end
  end

  def query_source(_request, _source, _opts), do: error_page(:corrupt, :invalid_query)

  defp validate_query(%Query{} = query) do
    valid_ids? =
      is_list(query.effect_ids) and length(query.effect_ids) <= @max_effect_ids and
        Enum.all?(query.effect_ids, &valid_id?/1) and
        length(Enum.uniq(query.effect_ids)) == length(query.effect_ids)

    if query.schema_version == 1 and valid_ids? and is_boolean(query.include_pointers) and
         valid_public_cursor?(query.cursor) and is_integer(query.limit) and
         query.limit >= 1 and query.limit <= @max_limit and is_integer(query.max_bytes) and
         query.max_bytes >= @min_page_bytes and query.max_bytes <= @max_page_bytes and
         is_integer(query.max_age_ms) and query.max_age_ms >= 0 do
      :ok
    else
      {:error, :invalid_query}
    end
  end

  defp valid_id?(value),
    do: is_binary(value) and byte_size(value) in 1..@max_id_bytes and String.valid?(value)

  defp valid_public_cursor?(cursor) when is_integer(cursor), do: cursor >= 0

  defp valid_public_cursor?(cursor) when is_map(cursor) and not is_struct(cursor) do
    Map.keys(cursor) |> Enum.sort() ==
      ~w(effect_cursor schema_version target_offset) and cursor["schema_version"] == 1 and
      is_integer(cursor["target_offset"]) and cursor["target_offset"] >= 0 and
      is_map(cursor["effect_cursor"]) and not is_struct(cursor["effect_cursor"])
  end

  defp valid_public_cursor?(_cursor), do: false

  defp public_target_offset(cursor) when is_integer(cursor), do: cursor
  defp public_target_offset(cursor), do: cursor["target_offset"]

  defp protected_effect_cursor(cursor) when is_map(cursor), do: cursor["effect_cursor"]
  defp protected_effect_cursor(_cursor), do: nil

  defp targets(request, snapshot) do
    pointer_targets =
      if request.include_pointers do
        Enum.map(@pointer_kinds, &{:pointer, &1, snapshot["pointers"][&1]})
      else
        []
      end

    all = pointer_targets ++ Enum.map(request.effect_ids, &{:effect, &1})

    offset = public_target_offset(request.cursor)

    if offset <= length(all) do
      selected = all |> Enum.drop(offset) |> Enum.take(request.limit)

      if is_map(request.cursor) and not match?([{:effect, _id} | _], selected) do
        {:error, :invalid_query}
      else
        {:ok, take_through_first_effect(selected)}
      end
    else
      {:error, :invalid_query}
    end
  end

  defp take_through_first_effect(targets), do: take_through_first_effect(targets, [])

  defp take_through_first_effect([], acc), do: Enum.reverse(acc)

  defp take_through_first_effect([{:effect, _id} = target | _rest], acc),
    do: Enum.reverse([target | acc])

  defp take_through_first_effect([target | rest], acc),
    do: take_through_first_effect(rest, [target | acc])

  defp read_targets(adapter, source_state, targets, request, source) do
    start_offset = public_target_offset(request.cursor)

    targets
    |> Enum.with_index(start_offset)
    |> Enum.reduce_while({:ok, [], nil}, fn {target, target_offset}, {:ok, items, nil} ->
      cursor = if target_offset == start_offset, do: protected_effect_cursor(request.cursor)

      case read_target(adapter, source_state, target, request, cursor, source) do
        {:ok, nil, nil} ->
          {:cont, {:ok, items, nil}}

        {:ok, item, nil} ->
          {:cont, {:ok, [item | items], nil}}

        {:ok, item, next_effect_cursor} ->
          public_cursor = %{
            "schema_version" => 1,
            "target_offset" => target_offset,
            "effect_cursor" => next_effect_cursor
          }

          {:halt, {:ok, [item | items], public_cursor}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items, cursor} -> {:ok, Enum.reverse(items), cursor}
      error -> error
    end
  end

  defp read_target(_adapter, _source_state, {:pointer, kind, fact}, _request, nil, _source) do
    with {:ok, status, revision} <- pointer_state(kind, fact) do
      {:ok,
       %Observation{
         kind: :pointer,
         status: status,
         quality: :canonical,
         identity: %{"pointer_kind" => kind},
         fact: %{"producer_status" => fact["producer_status"], "revision" => revision}
       }, nil}
    end
  end

  defp read_target(adapter, source_state, {:effect, effect_id}, request, cursor, source) do
    protected_max_bytes = max(request.max_bytes - @protected_envelope_reserve, 1_024)

    query = %{
      "schema_version" => 1,
      "type" => "effect_observation_page",
      "effect_id" => effect_id,
      "limit" => min(request.limit, @max_related_ids),
      "max_bytes" => protected_max_bytes,
      "cursor" => cursor
    }

    case adapter.fact(source_state, query) do
      {:error, :not_found} ->
        {:ok, nil, nil}

      {:ok, effect, _observed_at} ->
        with {:ok, identity, effect_fact, next_cursor, summaries} <-
               canonical_effect(effect_id, effect, source),
             {:ok, control, execution} <-
               effect_summaries(adapter, source_state, effect, summaries) do
          {:ok,
           %Observation{
             kind: :effect_context,
             status: :present,
             quality: :canonical,
             identity: identity,
             fact:
               Map.merge(effect_fact, %{
                 "control" => control,
                 "execution" => execution,
                 "usage" => %{"status" => "unknown", "reason" => "not_produced"}
               })
           }, next_cursor}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp effect_summaries(_adapter, _source_state, _effect, {:bounded, control, execution}),
    do: {:ok, Map.delete(control, "schema_version"), Map.delete(execution, "schema_version")}

  defp effect_summaries(adapter, source_state, effect, :legacy) do
    with {:ok, control} <- read_control(adapter, source_state, effect),
         {:ok, execution} <- read_execution(adapter, source_state, effect) do
      {:ok, control, execution}
    end
  end

  defp canonical_effect(
         effect_id,
         %{
           "schema_version" => 1,
           "type" => "effect_observation_page"
         } = page,
         source
       ) do
    effect = page["effect"]
    relations = page["relations"]
    protected_page = page["page"]
    settlement = page["settlement"]

    with true <-
           exact_map_keys?(
             page,
             ~w(schema_version type source effect control execution relations infrastructure_settlement settlement page)
           ),
         true <- valid_effect_page_source?(page["source"], source, effect),
         true <- is_map(effect),
         ^effect_id <- effect["effect_id"],
         true <- is_list(relations),
         true <- is_map(protected_page),
         true <- is_map(settlement),
         true <- valid_effect_header?(effect),
         true <- valid_effect_relations?(relations, effect_id),
         true <- valid_protected_effect_page?(protected_page, relations, page),
         true <- valid_control_summary?(page["control"], effect),
         true <- valid_execution_summary?(page["execution"], effect),
         1 <- settlement["schema_version"],
         true <- settlement["status"] == effect["status"],
         true <- settlement["receipt_history"] in ["complete", "unknown"],
         true <-
           valid_infrastructure_settlement?(
             page["infrastructure_settlement"],
             effect_id,
             effect["status"]
           ) do
      claims = Enum.filter(relations, &(&1["kind"] == "claim"))
      receipts = Enum.filter(relations, &(&1["kind"] == "receipt"))
      reservations = Enum.filter(relations, &(&1["kind"] == "reservation"))
      leases = Enum.filter(relations, &(&1["kind"] == "lease"))

      receipt_history =
        receipts
        |> Enum.map(& &1["outcome"])
        |> Enum.uniq()
        |> Enum.sort_by(&receipt_outcome_order/1)

      outcome = canonical_outcome_from_page(effect["status"], receipt_history, settlement)

      fact =
        effect
        |> Map.take(@effect_fields)
        |> Map.put("claim_ids", bounded_ids(claims, "claim_id"))
        |> Map.put("reservation_ids", bounded_ids(reservations, "reservation_id"))
        |> Map.put("lease_ids", bounded_ids(leases, "lease_id"))
        |> Map.put("relations", relations)
        |> Map.put("relations_truncated", protected_page["truncated"])
        |> Map.put("receipt_history_quality", settlement["receipt_history"])
        |> Map.put("infrastructure_settlement", page["infrastructure_settlement"])
        |> Map.put("outcome", outcome)

      identity = Map.take(effect, ~w(effect_id ticket_id attempt_id execution_id control_id))

      {:ok, identity, fact, protected_page["next_cursor"],
       {:bounded, page["control"], page["execution"]}}
    else
      _ -> {:error, :corrupt}
    end
  end

  defp canonical_effect(effect_id, effect, _source) do
    identity_fields = ~w(effect_id ticket_id attempt_id execution_id control_id)

    with 1 <- effect["schema_version"],
         ^effect_id <- effect["effect_id"],
         true <- Enum.all?(identity_fields, &valid_id?(effect[&1])),
         revision when is_integer(revision) and revision >= 0 <- effect["revision"],
         status when status in @effect_statuses <- effect["status"],
         claims when is_list(claims) <- effect["claims"],
         reservations when is_list(reservations) <- effect["reservations"],
         true <- Enum.all?(claims, &valid_claim?(&1, effect_id)),
         true <- Enum.all?(claims, &(&1["status"] == status)),
         true <- Enum.all?(reservations, &valid_related?(&1, "reservation_id")) do
      claim_ids = bounded_ids(claims, "claim_id")
      reservation_ids = bounded_ids(reservations, "reservation_id")

      fact =
        effect
        |> Map.take(@effect_fields)
        |> Map.put("claim_ids", claim_ids)
        |> Map.put("claims_truncated", length(claims) > @max_related_ids)
        |> Map.put("reservation_ids", reservation_ids)
        |> Map.put("reservations_truncated", length(reservations) > @max_related_ids)
        |> Map.put("outcome", canonical_outcome(status, claims))

      {:ok, Map.take(effect, identity_fields), fact, nil, :legacy}
    else
      _ -> {:error, :corrupt}
    end
  end

  defp valid_effect_header?(effect) do
    effect["schema_version"] == 1 and
      Enum.all?(
        ~w(effect_id ticket_id attempt_id execution_id control_id policy_id operation scope),
        &valid_id?(effect[&1])
      ) and effect["status"] in @effect_statuses and is_integer(effect["revision"]) and
      effect["revision"] >= 0 and is_integer(effect["policy_revision"]) and
      effect["policy_revision"] >= 0 and is_integer(effect["control_revision"]) and
      effect["control_revision"] >= 0
  end

  defp valid_effect_relations?(relations, effect_id) do
    Enum.all?(relations, fn
      %{"kind" => "claim", "effect_id" => ^effect_id} = claim ->
        claim["schema_version"] == 1 and valid_id?(claim["claim_id"]) and
          valid_id?(claim["writer_epoch"]) and
          claim["status"] in @claim_statuses and nonnegative?(claim["revision"])

      %{"kind" => "receipt"} = receipt ->
        receipt["schema_version"] == 1 and
          Enum.all?(~w(receipt_id claim_id request_id receipt_digest), &valid_id?(receipt[&1])) and
          receipt["outcome"] in @receipt_outcomes

      %{"kind" => "reservation"} = reservation ->
        reservation["schema_version"] == 1 and valid_id?(reservation["reservation_id"]) and
          reservation["owner_kind"] == "effect" and
          reservation["owner_id"] == effect_id and nonnegative?(reservation["revision"])

      %{"kind" => "lease"} = lease ->
        lease["schema_version"] == 1 and valid_id?(lease["lease_id"]) and
          valid_id?(lease["claim_id"]) and
          nonnegative?(lease["revision"])

      _ ->
        false
    end)
  end

  defp valid_protected_effect_page?(page, relations, envelope) do
    exact_map_keys?(page, ~w(item_count size_bytes truncated truncated_reason next_cursor)) and
      page["item_count"] == length(relations) and
      page["size_bytes"] == :erlang.external_size(envelope) and
      is_integer(page["item_count"]) and page["item_count"] >= 0 and
      page["item_count"] <= @max_related_ids and is_integer(page["size_bytes"]) and
      page["size_bytes"] >= 0 and is_boolean(page["truncated"]) and
      page["truncated_reason"] in [nil, "item_limit", "byte_limit"] and
      ((page["truncated"] and valid_protected_cursor?(page["next_cursor"], envelope)) or
         (not page["truncated"] and is_nil(page["next_cursor"]) and
            is_nil(page["truncated_reason"])))
  end

  defp valid_effect_page_source?(page_source, source, effect) when is_map(page_source) do
    exact_map_keys?(
      page_source,
      ~w(installation_id repository_id last_protected_command_sequence effect_revision)
    ) and
      page_source["installation_id"] == source["installation_id"] and
      page_source["repository_id"] == source["repository_id"] and
      page_source["last_protected_command_sequence"] == source["last_protected_command_sequence"] and
      is_map(effect) and page_source["effect_revision"] == effect["revision"]
  end

  defp valid_effect_page_source?(_page_source, _source, _effect), do: false

  defp valid_protected_cursor?(cursor, envelope) when is_map(cursor) do
    source = envelope["source"]
    effect = envelope["effect"]

    exact_map_keys?(
      cursor,
      ~w(schema_version query_type scope_digest source_digest protected_sequence effect_revision section offset)
    ) and
      cursor["schema_version"] == 1 and cursor["query_type"] == "effect_observation_page" and
      digest?(cursor["scope_digest"]) and digest?(cursor["source_digest"]) and
      cursor["protected_sequence"] == source["last_protected_command_sequence"] and
      cursor["effect_revision"] == effect["revision"] and
      cursor["section"] in ~w(claims receipts reservations leases) and
      nonnegative?(cursor["offset"])
  end

  defp valid_protected_cursor?(_cursor, _envelope), do: false

  defp digest?(value),
    do: is_binary(value) and byte_size(value) == 64 and String.match?(value, ~r/\A[0-9a-f]+\z/)

  defp exact_map_keys?(value, keys) when is_map(value),
    do: Enum.sort(Map.keys(value)) == Enum.sort(keys)

  defp exact_map_keys?(_value, _keys), do: false

  defp valid_control_summary?(control, effect) when is_map(control) do
    exact_map_keys?(control, ~w(schema_version control_id revision status)) and
      control["schema_version"] == 1 and control["control_id"] == effect["control_id"] and
      nonnegative?(control["revision"]) and control["status"] in @control_statuses
  end

  defp valid_control_summary?(_control, _effect), do: false

  defp valid_execution_summary?(%{"status" => "absent"} = execution, effect) do
    exact_map_keys?(execution, ~w(schema_version execution_id status)) and
      execution["schema_version"] == 1 and execution["execution_id"] == effect["execution_id"]
  end

  defp valid_execution_summary?(execution, effect) when is_map(execution) do
    base_keys = ~w(schema_version execution_id status revision last_sequence sealed_sequence)

    allowed_keys =
      if(execution["status"] in ~w(result exit), do: base_keys ++ ["sequence"], else: base_keys)

    exact_map_keys?(execution, allowed_keys) and execution["schema_version"] == 1 and
      execution["execution_id"] == effect["execution_id"] and
      valid_execution_fact(execution, execution) == :ok
  end

  defp valid_execution_summary?(_execution, _effect), do: false

  defp valid_infrastructure_settlement?(nil, _effect_id, _effect_status), do: true

  defp valid_infrastructure_settlement?(settlement, effect_id, effect_status)
       when is_map(settlement) do
    settlement["schema_version"] == 1 and effect_status in ~w(non_started reconciliation_required) and
      settlement["effect_id"] == effect_id and
      Enum.all?(
        ~w(claim_id receipt_id role work_owner failure_class),
        &valid_id?(settlement[&1])
      ) and nonnegative?(settlement["infrastructure_generation"]) and
      is_integer(settlement["ordinal"]) and settlement["ordinal"] > 0 and
      (is_nil(settlement["predecessor_effect_id"]) or
         valid_id?(settlement["predecessor_effect_id"]))
  end

  defp valid_infrastructure_settlement?(_settlement, _effect_id, _effect_status), do: false

  defp nonnegative?(value), do: is_integer(value) and value >= 0

  defp canonical_outcome_from_page(status, history, _settlement) do
    base =
      case status do
        terminal when terminal in ~w(succeeded failed non_started cancelled) ->
          %{"status" => terminal}

        "unknown" ->
          %{"status" => "unknown", "reason" => "outcome_unknown"}

        "reconciliation_required" ->
          %{"status" => "unknown", "reason" => "reconciliation_required"}

        _ ->
          %{"status" => "unknown", "reason" => "no_terminal_receipt"}
      end

    Map.put(base, "receipt_history", history)
  end

  defp bounded_ids(values, key) do
    values
    |> Enum.take(@max_related_ids)
    |> Enum.map(& &1[key])
    |> Enum.filter(&valid_id?/1)
  end

  defp valid_claim?(claim, effect_id) do
    is_map(claim) and claim["schema_version"] == 1 and valid_id?(claim["claim_id"]) and
      claim["effect_id"] == effect_id and valid_id?(claim["writer_epoch"]) and
      claim["status"] in @claim_statuses and is_integer(claim["revision"]) and
      claim["revision"] >= 0 and is_list(claim["receipts"]) and
      Enum.all?(claim["receipts"], &valid_receipt?/1)
  end

  defp valid_related?(value, key), do: is_map(value) and valid_id?(value[key])

  defp valid_receipt?(receipt) do
    is_map(receipt) and receipt["schema_version"] == 1 and
      receipt["outcome"] in @receipt_outcomes
  end

  defp canonical_outcome(status, claims) do
    history =
      claims
      |> Enum.flat_map(fn claim ->
        claim
        |> Map.get("receipts", [])
        |> Enum.map(& &1["outcome"])
      end)
      |> Enum.uniq()
      |> Enum.sort_by(&receipt_outcome_order/1)

    outcome =
      case status do
        terminal when terminal in ~w(succeeded failed non_started cancelled) ->
          %{"status" => terminal}

        "unknown" ->
          %{"status" => "unknown", "reason" => "outcome_unknown"}

        "reconciliation_required" ->
          %{"status" => "unknown", "reason" => "reconciliation_required"}

        _nonterminal ->
          %{"status" => "unknown", "reason" => "no_terminal_receipt"}
      end

    Map.put(outcome, "receipt_history", history)
  end

  defp receipt_outcome_order("unknown"), do: 0
  defp receipt_outcome_order("non_started"), do: 1
  defp receipt_outcome_order("succeeded"), do: 2
  defp receipt_outcome_order("failed"), do: 3

  defp read_control(adapter, source_state, effect) do
    id = effect["control_id"]

    case adapter.fact(source_state, fact_query("control", "control_id", id)) do
      {:ok, %{"schema_version" => 1, "control_id" => ^id, "revision" => revision} = fact,
       _observed_at}
      when is_integer(revision) and revision >= 0 ->
        status = get_in(fact, ["value", "status"])

        if status in @control_statuses do
          {:ok, %{"control_id" => id, "revision" => revision, "status" => status}}
        else
          {:error, :corrupt}
        end

      {:error, :not_found} ->
        {:error, :corrupt}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :corrupt}
    end
  end

  defp read_execution(adapter, source_state, effect) do
    id = effect["execution_id"]

    case adapter.fact(source_state, fact_query("inbox", "execution_id", id)) do
      {:ok, %{"schema_version" => 1, "execution_id" => ^id} = fact, _observed_at} ->
        resolution = Map.get(fact, "resolution", %{})

        with :ok <- valid_execution_fact(fact, resolution) do
          {:ok,
           %{
             "execution_id" => id,
             "status" => resolution["status"],
             "revision" => fact["revision"],
             "last_sequence" => fact["last_sequence"],
             "sealed_sequence" => fact["sealed_sequence"]
           }}
        end

      {:error, :not_found} ->
        {:ok, %{"execution_id" => id, "status" => "absent"}}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :corrupt}
    end
  end

  defp fact_query(type, key, value),
    do: %{"schema_version" => 1, "type" => type, key => value}

  defp valid_execution_fact(fact, resolution) do
    revision = fact["revision"]
    last_sequence = fact["last_sequence"]
    sealed_sequence = fact["sealed_sequence"]
    status = resolution["status"]

    valid_sealed? =
      is_nil(sealed_sequence) or
        (is_integer(sealed_sequence) and sealed_sequence >= 0 and sealed_sequence <= last_sequence)

    valid_resolution? =
      case status do
        "open" ->
          is_nil(sealed_sequence)

        status when status in ["result", "exit"] ->
          valid_resolution_sequence?(resolution, sealed_sequence)

        "sealed_without_result_or_exit" ->
          is_integer(sealed_sequence)

        _ ->
          false
      end

    if is_integer(revision) and revision >= 0 and is_integer(last_sequence) and
         last_sequence >= 0 and valid_sealed? and status in @execution_statuses and
         valid_resolution? do
      :ok
    else
      {:error, :corrupt}
    end
  end

  defp valid_resolution_sequence?(resolution, sealed_sequence) do
    sequence = resolution["sequence"]

    is_integer(sequence) and is_integer(sealed_sequence) and sequence >= 1 and
      sequence <= sealed_sequence
  end

  defp redact(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      cond do
        sensitive_key?(key) -> {key, "[REDACTED]"}
        secret_shaped?(key) -> {"[REDACTED_KEY]", redact(nested)}
        true -> {key, redact(nested)}
      end
    end)
  end

  defp redact(value) when is_list(value), do: Enum.map(value, &redact/1)

  defp redact(value) when is_binary(value) do
    if secret_shaped?(value), do: "[REDACTED]", else: value
  end

  defp redact(value), do: value

  defp sensitive_key?(key) when is_binary(key),
    do: String.match?(key, ~r/(?:token|secret|password|credential|authorization|api[_-]?key)/i)

  defp sensitive_key?(_key), do: false

  defp secret_shaped?(value) when is_binary(value),
    do: String.match?(value, ~r/(?:bearer\s+|sk-[a-z0-9_-]{8,}|api[_-]?key\s*[=:])/i)

  defp secret_shaped?(_value), do: false

  defp pointer_state(kind, fact) do
    with %{
           "schema_version" => 1,
           "pointer_kind" => ^kind,
           "producer_status" => status,
           "revision" => revision
         } <-
           fact,
         true <- status in ["absent", "unavailable", "present"],
         true <- is_integer(revision) and revision >= 0 do
      observation_status =
        case status do
          "absent" -> :absent
          "unavailable" -> :unavailable
          "present" -> :present
        end

      {:ok, observation_status, revision}
    else
      _ -> {:error, :corrupt}
    end
  end

  defp canonical_source(snapshot) do
    with 1 <- snapshot["schema_version"],
         true <- valid_id?(snapshot["installation_id"]),
         true <- valid_id?(snapshot["repository_id"]),
         true <- valid_id?(snapshot["writer_epoch"]),
         protected when is_integer(protected) and protected >= 0 <-
           snapshot["last_protected_command_sequence"],
         domain when is_integer(domain) and domain >= 0 <- snapshot["last_domain_event_sequence"],
         true <- Enum.all?(@version_fields, &(snapshot[&1] == @supported_versions[&1])),
         pointers when is_map(pointers) <- snapshot["pointers"],
         true <- Enum.sort(Map.keys(pointers)) == Enum.sort(@pointer_kinds),
         true <-
           Enum.all?(@pointer_kinds, fn kind ->
             match?({:ok, _, _}, pointer_state(kind, pointers[kind]))
           end) do
      {:ok,
       %{
         "kind" => "protected_store",
         "installation_id" => snapshot["installation_id"],
         "repository_id" => snapshot["repository_id"],
         "writer_epoch" => snapshot["writer_epoch"],
         "last_protected_command_sequence" => protected,
         "last_domain_event_sequence" => domain,
         "sql_schema_version" => snapshot["sql_schema_version"],
         "protected_schema_version" => snapshot["protected_schema_version"],
         "protocol_version" => snapshot["protocol_version"],
         "event_version" => snapshot["event_version"],
         "projection_version" => snapshot["projection_version"],
         "pointers" => pointers
       }}
    else
      _ -> {:error, :corrupt}
    end
  end

  defp stable_source(before, after_source) do
    stable_keys =
      ~w(installation_id repository_id writer_epoch last_protected_command_sequence last_domain_event_sequence sql_schema_version protected_schema_version protocol_version event_version projection_version pointers)

    if Map.take(before, stable_keys) == Map.take(after_source, stable_keys),
      do: :ok,
      else: {:error, :source_changed}
  end

  defp freshness(observed_at, now, max_age_ms)
       when is_struct(observed_at, DateTime) and is_struct(now, DateTime) do
    age = DateTime.diff(now, observed_at, :millisecond)

    cond do
      age < 0 -> {:error, :invalid_freshness}
      age <= max_age_ms -> {:ok, :fresh}
      true -> {:ok, :stale}
    end
  end

  defp freshness(_observed_at, _now, _max_age_ms), do: {:error, :invalid_freshness}

  defp build_page(request, source, items, observed_at, freshness, targets, effect_cursor) do
    total_targets = if(request.include_pointers, do: 3, else: 0) + length(request.effect_ids)
    consumed = length(targets)
    offset = public_target_offset(request.cursor)

    next_cursor =
      effect_cursor ||
        if(offset + consumed < total_targets, do: offset + consumed)

    page = %Page{
      status: :ok,
      quality: :canonical,
      freshness: freshness,
      observed_at: observed_at,
      source: Map.delete(source, "pointers"),
      items: Enum.map(items, &redact_observation/1),
      next_cursor: redact(next_cursor),
      size_bytes: 0,
      error_code: nil
    }

    sized = page |> redact_page() |> put_size()

    if sized.size_bytes <= request.max_bytes do
      sized
    else
      error_page(:unavailable, :page_size_limit_exceeded)
    end
  end

  defp redact_observation(%Observation{} = observation) do
    %{observation | identity: redact(observation.identity), fact: redact(observation.fact)}
  end

  defp redact_page(%Page{} = page), do: %{page | source: redact(page.source)}

  defp error_page(status, code) do
    %Page{
      status: status,
      quality: status,
      freshness: :unknown,
      observed_at: nil,
      source: nil,
      items: [],
      next_cursor: nil,
      size_bytes: 0,
      error_code: code
    }
    |> put_size()
  end

  defp put_size(page) do
    first = %{page | size_bytes: :erlang.external_size(page)}
    %{first | size_bytes: :erlang.external_size(first)}
  end
end
