defmodule PramanaFoundry.DurableStore.ProtectedVerifier do
  @moduledoc false

  alias PramanaFoundry.DurableStore.RecordCodec

  @fact_keys ~w(writer_epoch required_revisions ledger_generations effect_authorizations)a
  @authorization_keys ~w(effect_id claim_id generation_id reservation_id dimension units)a

  def derive(command, proposal, facts) when is_map(facts) do
    with :ok <- exact_keys(facts, @fact_keys),
         writer_epoch when is_binary(writer_epoch) and writer_epoch != "" <-
           fetch(facts, :writer_epoch),
         :ok <- validate_required_revisions(command, fetch(facts, :required_revisions)),
         generations when is_list(generations) <- fetch(facts, :ledger_generations),
         true <- proper_list?(generations),
         authorizations when is_list(authorizations) <- fetch(facts, :effect_authorizations),
         true <- proper_list?(authorizations),
         {:ok, normalized_generations} <- normalize_generations(generations),
         :ok <- validate_authorizations(proposal, authorizations, normalized_generations),
         claims <- claims(authorizations, writer_epoch),
         reservations <- reservations(authorizations) do
      {:ok,
       %{
         required_revisions: fetch(facts, :required_revisions),
         ledger_generations: normalized_generations,
         claims: claims,
         reservations: reservations
       }}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_protected_facts}
    end
  end

  def derive(_command, _proposal, _facts), do: {:error, :invalid_protected_facts}

  defp validate_required_revisions(command, required) when is_map(required) do
    supplied = fetch(command, :expected_revisions)

    if is_map(supplied) and
         Enum.all?(required, fn {key, value} -> Map.get(supplied, key) == value end),
       do: :ok,
       else: {:error, :incomplete_protected_read_set}
  end

  defp validate_required_revisions(_command, _required),
    do: {:error, :invalid_required_revisions}

  defp normalize_generations(generations) do
    Enum.reduce_while(generations, {:ok, []}, fn generation, {:ok, acc} ->
      case RecordCodec.normalize(:candidate_ledger_generation, generation) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} -> {:halt, {:error, :unsupported_child_ledger_generation}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  defp validate_authorizations(proposal, authorizations, generations) do
    intents = fetch(proposal, :intents, [])
    intent_ids = MapSet.new(intents, &fetch(&1, :effect_id))

    available =
      Map.new(generations, fn generation ->
        {fetch(generation, :generation_id),
         fetch(generation, :allocation) - fetch(generation, :consumed)}
      end)

    with true <- length(authorizations) == MapSet.size(intent_ids),
         :ok <-
           validate_many(authorizations, fn authorization ->
             with :ok <- exact_keys(authorization, @authorization_keys),
                  :ok <-
                    identities(authorization, [
                      :effect_id,
                      :claim_id,
                      :generation_id,
                      :reservation_id,
                      :dimension
                    ]),
                  units when is_integer(units) and units > 0 <- fetch(authorization, :units),
                  true <- MapSet.member?(intent_ids, fetch(authorization, :effect_id)) do
               :ok
             else
               _ -> {:error, :invalid_effect_authorization}
             end
           end),
         true <- MapSet.new(authorizations, &fetch(&1, :effect_id)) == intent_ids,
         :ok <- allocations_fit(authorizations, available) do
      :ok
    else
      {:error, _reason} = error -> error
      _ -> {:error, :incomplete_effect_authorization}
    end
  end

  defp allocations_fit(authorizations, available) do
    requested =
      Enum.reduce(authorizations, %{}, fn authorization, acc ->
        Map.update(
          acc,
          fetch(authorization, :generation_id),
          fetch(authorization, :units),
          &(&1 + fetch(authorization, :units))
        )
      end)

    if Enum.all?(requested, fn {generation_id, _units} ->
         Map.has_key?(available, generation_id)
       end) and
         Enum.all?(available, fn {generation_id, remaining} ->
           Map.get(requested, generation_id, 0) == remaining
         end),
       do: :ok,
       else: {:error, :insufficient_ledger_allocation}
  end

  defp claims(authorizations, writer_epoch) do
    Enum.map(authorizations, fn authorization ->
      %{
        schema_version: 1,
        claim_id: fetch(authorization, :claim_id),
        effect_id: fetch(authorization, :effect_id),
        writer_epoch: writer_epoch,
        status: "claimed",
        value: %{"verified" => true}
      }
    end)
  end

  defp reservations(authorizations) do
    Enum.map(authorizations, fn authorization ->
      %{
        schema_version: 1,
        reservation_id: fetch(authorization, :reservation_id),
        generation_id: fetch(authorization, :generation_id),
        claim_id: fetch(authorization, :claim_id),
        dimension: fetch(authorization, :dimension),
        units: fetch(authorization, :units),
        status: "reserved",
        value: %{"verified" => true}
      }
    end)
  end

  defp validate_many(values, fun) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case fun.(value) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp exact_keys(map, allowed) when is_map(map) do
    keys = Enum.map(Map.keys(map), &normalize_key(&1, allowed))

    if :invalid in keys or length(keys) != length(allowed) or
         length(Enum.uniq(keys)) != length(keys),
       do: {:error, :invalid_protected_fields},
       else: :ok
  end

  defp exact_keys(_map, _allowed), do: {:error, :invalid_protected_fields}

  defp normalize_key(key, allowed) when is_atom(key),
    do: if(key in allowed, do: key, else: :invalid)

  defp normalize_key(key, allowed) when is_binary(key) do
    Enum.find(allowed, &(Atom.to_string(&1) == key)) || :invalid
  end

  defp normalize_key(_key, _allowed), do: :invalid

  defp identities(map, keys) do
    if Enum.all?(keys, fn key -> identity(map, key) == :ok end),
      do: :ok,
      else: {:error, :invalid_identity}
  end

  defp identity(map, key) do
    case fetch(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, :invalid_identity}
    end
  end

  defp fetch(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp proper_list?(value) do
    _length = length(value)
    true
  rescue
    ArgumentError -> false
  end
end
