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
         {:ok, items} <- read_targets(adapter, source_state, targets),
         {:ok, after_snapshot, after_at} <- adapter.snapshot(source_state),
         {:ok, after_source} <- canonical_source(after_snapshot),
         :ok <- stable_source(source, after_source),
         now <- Keyword.get(opts, :now, DateTime.utc_now()),
         true <- match?(%DateTime{}, now),
         {:ok, freshness} <- freshness(after_at, now, request.max_age_ms) do
      build_page(request, source, items, after_at, freshness, targets)
    else
      {:error, :invalid_query} -> error_page(:corrupt, :invalid_query)
      false -> error_page(:corrupt, :invalid_clock)
      {:error, :unavailable} -> error_page(:unavailable, :source_unavailable)
      {:error, :not_found} -> error_page(:corrupt, :source_snapshot_missing)
      {:error, :corrupt} -> error_page(:corrupt, :source_corrupt)
      {:error, :source_changed} -> error_page(:unavailable, :source_changed_during_query)
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
         is_integer(query.cursor) and query.cursor >= 0 and is_integer(query.limit) and
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

  defp targets(request, snapshot) do
    pointer_targets =
      if request.include_pointers do
        Enum.map(@pointer_kinds, &{:pointer, &1, snapshot["pointers"][&1]})
      else
        []
      end

    all = pointer_targets ++ Enum.map(request.effect_ids, &{:effect, &1})

    if request.cursor <= length(all) do
      {:ok, all |> Enum.drop(request.cursor) |> Enum.take(request.limit)}
    else
      {:error, :invalid_query}
    end
  end

  defp read_targets(adapter, source_state, targets) do
    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, items} ->
      case read_target(adapter, source_state, target) do
        {:ok, nil} -> {:cont, {:ok, items}}
        {:ok, item} -> {:cont, {:ok, [item | items]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp read_target(_adapter, _source_state, {:pointer, kind, fact}) do
    with {:ok, status, revision} <- pointer_state(kind, fact) do
      {:ok,
       %Observation{
         kind: :pointer,
         status: status,
         quality: :canonical,
         identity: %{"pointer_kind" => kind},
         fact: %{"producer_status" => fact["producer_status"], "revision" => revision}
       }}
    end
  end

  defp read_target(adapter, source_state, {:effect, effect_id}) do
    case adapter.fact(source_state, fact_query("effect", "effect_id", effect_id)) do
      {:error, :not_found} ->
        {:ok, nil}

      {:ok, effect, _observed_at} ->
        with {:ok, identity, effect_fact} <- canonical_effect(effect_id, effect),
             {:ok, control} <- read_control(adapter, source_state, effect),
             {:ok, execution} <- read_execution(adapter, source_state, effect) do
          {:ok,
           %Observation{
             kind: :effect_context,
             status: :present,
             quality: :canonical,
             identity: identity,
             fact:
               redact(
                 Map.merge(effect_fact, %{
                   "control" => control,
                   "execution" => execution,
                   "usage" => %{"status" => "unknown", "reason" => "not_produced"}
                 })
               )
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp canonical_effect(effect_id, effect) do
    identity_fields = ~w(effect_id ticket_id attempt_id execution_id control_id)

    with 1 <- effect["schema_version"],
         ^effect_id <- effect["effect_id"],
         true <- Enum.all?(identity_fields, &valid_id?(effect[&1])),
         revision when is_integer(revision) and revision >= 0 <- effect["revision"],
         claims when is_list(claims) <- effect["claims"],
         reservations when is_list(reservations) <- effect["reservations"],
         true <- Enum.all?(claims, &valid_claim?/1),
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
        |> Map.put("outcome", canonical_outcome(claims))

      {:ok, Map.take(effect, identity_fields), fact}
    else
      _ -> {:error, :corrupt}
    end
  end

  defp bounded_ids(values, key) do
    values
    |> Enum.take(@max_related_ids)
    |> Enum.map(& &1[key])
    |> Enum.filter(&valid_id?/1)
  end

  defp valid_claim?(claim) do
    is_map(claim) and valid_id?(claim["claim_id"]) and is_list(claim["receipts"]) and
      Enum.all?(claim["receipts"], &is_map/1)
  end

  defp valid_related?(value, key), do: is_map(value) and valid_id?(value[key])

  defp canonical_outcome([]), do: %{"status" => "unknown", "reason" => "not_issued"}

  defp canonical_outcome(claims) do
    outcomes =
      claims
      |> Enum.flat_map(fn claim ->
        claim
        |> Map.get("receipts", [])
        |> Enum.map(& &1["outcome"])
      end)
      |> Enum.filter(&(&1 in ~w(succeeded failed non_started unknown)))
      |> Enum.uniq()

    case outcomes do
      [outcome] -> %{"status" => outcome}
      [] -> %{"status" => "unknown", "reason" => "no_terminal_receipt"}
      _ -> %{"status" => "unknown", "reason" => "conflicting_receipts"}
    end
  end

  defp read_control(adapter, source_state, effect) do
    id = effect["control_id"]

    case adapter.fact(source_state, fact_query("control", "control_id", id)) do
      {:ok, %{"schema_version" => 1, "control_id" => ^id, "revision" => revision} = fact,
       _observed_at}
      when is_integer(revision) and revision >= 0 ->
        status = get_in(fact, ["value", "status"])

        if is_binary(status) do
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

        {:ok,
         %{
           "execution_id" => id,
           "status" => Map.get(resolution, "status", "unknown"),
           "revision" => fact["revision"],
           "last_sequence" => fact["last_sequence"],
           "sealed_sequence" => fact["sealed_sequence"]
         }}

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

  defp redact(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      if sensitive_key?(key), do: {key, "[REDACTED]"}, else: {key, redact(nested)}
    end)
  end

  defp redact(value) when is_list(value), do: Enum.map(value, &redact/1)

  defp redact(value) when is_binary(value) do
    if String.match?(value, ~r/(?:bearer\s+|sk-[a-z0-9_-]{8,}|api[_-]?key\s*[=:])/i),
      do: "[REDACTED]",
      else: value
  end

  defp redact(value), do: value

  defp sensitive_key?(key) when is_binary(key),
    do: String.match?(key, ~r/(?:token|secret|password|credential|authorization|api[_-]?key)/i)

  defp sensitive_key?(_key), do: false

  defp pointer_state(kind, fact) do
    with %{"pointer_kind" => ^kind, "producer_status" => status, "revision" => revision} <-
           fact,
         true <- status in ["absent", "available"],
         true <- is_integer(revision) and revision >= 0 do
      {:ok, if(status == "absent", do: :absent, else: :present), revision}
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
         "protected_schema_version" => snapshot["protected_schema_version"],
         "projection_version" => snapshot["projection_version"],
         "pointers" => pointers
       }}
    else
      _ -> {:error, :corrupt}
    end
  end

  defp stable_source(before, after_source) do
    stable_keys =
      ~w(installation_id repository_id writer_epoch last_protected_command_sequence last_domain_event_sequence protected_schema_version projection_version pointers)

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

  defp build_page(request, source, items, observed_at, freshness, targets) do
    total_targets = if(request.include_pointers, do: 3, else: 0) + length(request.effect_ids)
    consumed = length(targets)
    next_cursor = if request.cursor + consumed < total_targets, do: request.cursor + consumed

    page = %Page{
      status: :ok,
      quality: :canonical,
      freshness: freshness,
      observed_at: observed_at,
      source: Map.delete(source, "pointers"),
      items: items,
      next_cursor: next_cursor,
      size_bytes: 0,
      error_code: nil
    }

    sized = put_size(page)

    if sized.size_bytes <= request.max_bytes do
      sized
    else
      error_page(:corrupt, :page_size_limit_exceeded)
    end
  end

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
