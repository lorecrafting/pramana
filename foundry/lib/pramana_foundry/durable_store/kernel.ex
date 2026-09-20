defmodule PramanaFoundry.DurableStore.Kernel do
  @moduledoc """
  Pure boundary for an independently updatable workflow kernel.

  A kernel can propose versioned data. It never receives the SQLite connection or SQL.
  The protected gateway validates and commits the proposal using its fixed statements.
  """

  @callback decide(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply(map(), map()) :: {:ok, map()} | {:error, term()}

  @bundle_keys ~w(schema_version result events projections intents ledger_generations claims reservations)a
  @required_keys ~w(schema_version result)a

  def validate_bundle(bundle) when is_map(bundle) do
    with :ok <- exact_keys(bundle, @required_keys, @bundle_keys),
         :ok <- version(bundle),
         :ok <- validate_result(fetch(bundle, :result)),
         :ok <- validate_many(bundle, :events, &validate_event/1),
         :ok <- validate_many(bundle, :projections, &validate_projection/1),
         :ok <- validate_many(bundle, :intents, &validate_intent/1),
         :ok <- validate_many(bundle, :ledger_generations, &validate_generation/1),
         :ok <- validate_many(bundle, :claims, &validate_claim/1),
         :ok <- validate_many(bundle, :reservations, &validate_reservation/1) do
      :ok
    end
  end

  def validate_bundle(_bundle), do: {:error, :invalid_bundle}

  defp validate_result(value) do
    validate_record(
      value,
      ~w(schema_version disposition reason_code)a,
      ~w(schema_version disposition)a,
      fn ->
        if fetch(value, :disposition) in ["accepted", "rejected", "blocked"],
          do: :ok,
          else: {:error, :invalid_disposition}
      end
    )
  end

  defp validate_event(value) do
    validate_record(
      value,
      ~w(schema_version event_id type payload)a,
      ~w(schema_version event_id type payload)a,
      fn ->
        ids(value, [:event_id, :type])
      end
    )
  end

  defp validate_projection(value) do
    validate_record(
      value,
      ~w(schema_version namespace entity_id expected_revision revision last_event_id value)a,
      ~w(schema_version namespace entity_id expected_revision revision last_event_id value)a,
      fn ->
        with :ok <- ids(value, [:namespace, :entity_id, :last_event_id]),
             expected when is_integer(expected) and expected >= -1 <-
               fetch(value, :expected_revision),
             revision when is_integer(revision) and revision >= 0 <- fetch(value, :revision),
             true <- revision == expected + 1 do
          :ok
        else
          _ -> {:error, :invalid_projection_revision}
        end
      end
    )
  end

  defp validate_intent(value) do
    validate_record(
      value,
      ~w(schema_version effect_id request_digest status value)a,
      ~w(schema_version effect_id request_digest status value)a,
      fn ->
        with :ok <- ids(value, [:effect_id, :request_digest]),
             true <-
               fetch(value, :status) in ["pending", "issued", "unknown", "settled", "cancelled"] do
          :ok
        else
          _ -> {:error, :invalid_intent}
        end
      end
    )
  end

  defp validate_generation(value) do
    validate_record(
      value,
      ~w(schema_version generation_id parent_generation_id allocation consumed)a,
      ~w(schema_version generation_id allocation consumed)a,
      fn ->
        with :ok <- ids(value, [:generation_id]),
             allocation when is_integer(allocation) and allocation >= 0 <-
               fetch(value, :allocation),
             consumed when is_integer(consumed) and consumed >= 0 and consumed <= allocation <-
               fetch(value, :consumed) do
          optional_id(value, :parent_generation_id)
        else
          _ -> {:error, :invalid_generation}
        end
      end
    )
  end

  defp validate_claim(value) do
    validate_record(
      value,
      ~w(schema_version claim_id effect_id writer_epoch status value)a,
      ~w(schema_version claim_id effect_id writer_epoch status value)a,
      fn ->
        with :ok <- ids(value, [:claim_id, :effect_id, :writer_epoch]),
             true <- fetch(value, :status) in ["active", "released", "settled", "unknown"] do
          :ok
        else
          _ -> {:error, :invalid_claim}
        end
      end
    )
  end

  defp validate_reservation(value) do
    validate_record(
      value,
      ~w(schema_version reservation_id generation_id claim_id dimension units status value)a,
      ~w(schema_version reservation_id generation_id dimension units status value)a,
      fn ->
        with :ok <- ids(value, [:reservation_id, :generation_id, :dimension]),
             :ok <- optional_id(value, :claim_id),
             units when is_integer(units) and units >= 0 <- fetch(value, :units),
             true <- fetch(value, :status) in ["reserved", "consumed", "refunded", "released"] do
          :ok
        else
          _ -> {:error, :invalid_reservation}
        end
      end
    )
  end

  defp validate_record(value, allowed, required, validator) when is_map(value) do
    with :ok <- exact_keys(value, required, allowed), :ok <- version(value), do: validator.()
  end

  defp validate_record(_value, _allowed, _required, _validator), do: {:error, :invalid_record}

  defp validate_many(bundle, key, validator) do
    case fetch(bundle, key, []) do
      values when is_list(values) -> reduce_valid(values, validator)
      _ -> {:error, {:invalid_collection, key}}
    end
  end

  defp reduce_valid(values, validator) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validator.(value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp version(value) do
    if fetch(value, :schema_version) == 1, do: :ok, else: {:error, :unsupported_version}
  end

  defp ids(value, keys) do
    if Enum.all?(keys, &(is_binary(fetch(value, &1)) and fetch(value, &1) != "")),
      do: :ok,
      else: {:error, :invalid_identity}
  end

  defp optional_id(value, key) do
    case fetch(value, key) do
      nil -> :ok
      id when is_binary(id) and id != "" -> :ok
      _ -> {:error, :invalid_identity}
    end
  end

  defp exact_keys(map, required, allowed) do
    keys = Enum.map(Map.keys(map), &normalize_key/1)

    cond do
      :invalid in keys -> {:error, :unknown_field}
      Enum.any?(required, &(&1 not in keys)) -> {:error, :missing_field}
      Enum.any?(keys, &(&1 not in allowed)) -> {:error, :unknown_field}
      length(Enum.uniq(keys)) != length(keys) -> {:error, :duplicate_field}
      true -> :ok
    end
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    Enum.find(
      @bundle_keys ++
        ~w(disposition reason_code event_id type payload namespace entity_id expected_revision revision last_event_id value effect_id request_digest status generation_id parent_generation_id allocation consumed claim_id writer_epoch reservation_id dimension units)a,
      fn atom ->
        Atom.to_string(atom) == key
      end
    ) || :invalid
  end

  defp normalize_key(_key), do: :invalid

  defp fetch(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
