defmodule PramanaFoundry.Schema do
  @moduledoc """
  Validation and normalization for the supported Python workflow wire records.

  Snapshot and assignment records carry an explicit schema version. Python control and
  event envelopes are versioned by their interchange contract and are normalized to the
  canonical version-1 representation without dropping event evidence.
  """

  @max_bytes 8 * 1024 * 1024
  @identity_options [{"task_id", :task_id}, {"run_id", :run_id}, {"role", :role}]
  @roles ~w(developer reviewer pm system)
  @control_actions ~w(pause reset_pm_attempts resume steer stop)

  @spec decode_file(Path.t(), atom(), keyword()) :: {:ok, map()} | {:error, map()}
  def decode_file(path, kind, opts \\ []) do
    limit = Keyword.get(opts, :max_bytes, @max_bytes)

    with {:ok, stat} <- File.stat(path),
         :ok <- size_ok(stat.size, limit),
         {:ok, bytes} <- File.read(path),
         :ok <- size_ok(byte_size(bytes), limit),
         true <- String.valid?(bytes),
         {:ok, value} <- decode(bytes),
         {:ok, validated} <- validate(kind, value, opts) do
      {:ok, validated}
    else
      false -> failure(:invalid_utf8, path)
      {:error, reason} when is_atom(reason) -> failure(reason, path)
      {:error, %{reason: _} = error} -> {:error, error}
      {:error, reason} -> failure(reason, path)
    end
  end

  @spec validate(atom(), term(), keyword()) :: {:ok, map()} | {:error, map()}
  def validate(kind, value, opts \\ [])

  def validate(:control, value, opts) when is_map(value) do
    with :ok <- reject_wire_version(value),
         :ok <- exact_fields(value, ~w(action created_at payload), []),
         :ok <-
           types(value, %{"action" => &non_empty_binary?/1, "created_at" => &non_empty_binary?/1}),
         :ok <- control_action(value),
         normalized = %{
           "schema_version" => 1,
           "action" => value["action"],
           "created_at" => value["created_at"],
           "payload" => value["payload"],
           "evidence" => %{"python_wire_record" => value}
         },
         :ok <- identity(normalized, opts) do
      {:ok, normalized}
    else
      {:error, reason} -> failure(reason, value)
    end
  end

  def validate(:event, %{"schema_version" => _version} = value, opts) do
    validate_canonical_event(value, opts)
  end

  def validate(:event, value, opts) when is_map(value) do
    required = ~w(event at)
    optional = ~w(task_id run_id role)

    with :ok <- reject_canonical_event_fields(value),
         :ok <- required_fields(value, required),
         :ok <- types(value, %{"event" => &non_empty_binary?/1, "at" => &non_empty_binary?/1}),
         :ok <- optional_binary(value, "task_id"),
         :ok <- optional_binary(value, "run_id"),
         :ok <- optional_role(value),
         evidence = Map.drop(value, required ++ optional),
         normalized =
           %{
             "schema_version" => 1,
             "event" => value["event"],
             "at" => value["at"],
             "attributes" => %{},
             "evidence" => evidence
           }
           |> copy_optional_identity(value),
         :ok <- identity(normalized, opts) do
      {:ok, normalized}
    else
      {:error, reason} -> failure(reason, value)
    end
  end

  def validate(:assignment, value, opts) when is_map(value) do
    with :ok <- validate_assignment(value),
         :ok <- identity(value, opts) do
      {:ok, value}
    else
      {:error, reason} -> failure(reason, value)
    end
  end

  def validate(:snapshot, value, opts) when is_map(value) do
    with {:ok, spec} <- spec(:snapshot),
         :ok <- exact_fields(value, spec.required, spec.optional),
         :ok <- version(value),
         :ok <- types(value, spec.types),
         :ok <- identity(value, opts) do
      {:ok, value}
    else
      {:error, reason} -> failure(reason, value)
    end
  end

  def validate(kind, value, _opts) when kind in [:control, :event, :snapshot, :assignment],
    do: failure(:not_an_object, value)

  def validate(_kind, value, _opts), do: failure(:unsupported_schema, value)

  def max_bytes, do: @max_bytes

  defp decode(bytes) do
    try do
      {:ok, :json.decode(bytes)}
    rescue
      _ -> {:error, :malformed_json}
    catch
      _, _ -> {:error, :malformed_json}
    end
  end

  defp spec(:snapshot) do
    {:ok,
     %{
       required:
         ~w(schema_version generation status paused stop_requested supervisor assignments queue steering accepted_revision integration scheduler pm updated_at),
       optional:
         ~w(audit legacy_python_supervisor migrated_at migration_complete migration_revision provider_cooldowns scheduling_plan),
       types: %{
         "generation" => &non_negative_integer?/1,
         "status" => &is_binary/1,
         "paused" => &is_boolean/1,
         "stop_requested" => &is_boolean/1,
         "supervisor" => &is_map/1,
         "assignments" => &is_map/1,
         "queue" => &is_list/1,
         "steering" => &is_list/1,
         "accepted_revision" => &nullable_binary?/1,
         "integration" => &is_map/1,
         "scheduler" => &is_map/1,
         "pm" => &is_map/1,
         "updated_at" => &is_binary/1,
         "audit" => &is_map/1,
         "legacy_python_supervisor" => &is_binary/1,
         "migrated_at" => &is_binary/1,
         "migration_complete" => &is_boolean/1,
         "migration_revision" => &is_binary/1,
         "provider_cooldowns" => &is_map/1,
         "scheduling_plan" => &is_map/1
       }
     }}
  end

  defp validate_canonical_event(value, opts) do
    required = ~w(schema_version event at attributes evidence)
    optional = ~w(task_id run_id role)

    with :ok <- exact_fields(value, required, optional),
         :ok <- version(value),
         :ok <-
           types(value, %{
             "event" => &non_empty_binary?/1,
             "at" => &non_empty_binary?/1,
             "attributes" => &is_map/1,
             "evidence" => &is_map/1
           }),
         :ok <- optional_binary(value, "task_id"),
         :ok <- optional_binary(value, "run_id"),
         :ok <- optional_role(value),
         :ok <- identity(value, opts) do
      {:ok, value}
    else
      {:error, reason} -> failure(reason, value)
    end
  end

  defp exact_fields(value, required, optional) do
    keys = Map.keys(value)
    missing = required -- keys
    unknown = (keys -- required) -- optional

    cond do
      missing != [] -> {:error, {:missing_fields, Enum.sort(missing)}}
      unknown != [] -> {:error, {:unknown_fields, Enum.sort(unknown)}}
      true -> :ok
    end
  end

  defp required_fields(value, required) do
    case required -- Map.keys(value) do
      [] -> :ok
      missing -> {:error, {:missing_fields, Enum.sort(missing)}}
    end
  end

  defp reject_wire_version(value) do
    if Map.has_key?(value, "schema_version"), do: {:error, :unsupported_version}, else: :ok
  end

  defp reject_canonical_event_fields(value) do
    case Map.keys(value)
         |> Enum.filter(&(&1 in ~w(schema_version attributes evidence)))
         |> Enum.sort() do
      [] -> :ok
      fields -> {:error, {:unknown_authority_fields, fields}}
    end
  end

  defp version(%{"schema_version" => 1}), do: :ok
  defp version(_), do: {:error, :unsupported_version}

  defp types(value, types) do
    Enum.reduce_while(types, :ok, fn {field, predicate}, :ok ->
      case Map.fetch(value, field) do
        {:ok, field_value} ->
          if predicate.(field_value),
            do: {:cont, :ok},
            else: {:halt, {:error, {:invalid_type, field}}}

        :error ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_assignment(%{"role" => role} = value) when role in ~w(developer reviewer) do
    required =
      ~w(schema_version task_id run_id role accepted_revision assignment_path proposal_path disabled_operations configured_model configured_model_id configured_profile configured_reasoning expected_checkout_head ticket)

    optional = ~w(candidate_commit continuation correction handoff)

    with :ok <- exact_fields(value, required, optional),
         :ok <- version(value),
         :ok <- worker_assignment_types(value),
         :ok <- assignment_task_identity(value),
         :ok <- validate_ticket(value["ticket"]),
         :ok <- authority_consistent(value),
         :ok <- reviewer_fields(role, value) do
      :ok
    end
  end

  defp validate_assignment(%{"role" => "pm"} = value) do
    required =
      ~w(schema_version task_id run_id role accepted_revision assignment_path proposal_path audit_path profile configured_model configured_model_id configured_reasoning max_proposals allowed_operations disabled_operations planning_context native_entrypoint)

    with :ok <- exact_fields(value, required, []),
         :ok <- version(value),
         :ok <- pm_assignment_types(value),
         :ok <- pm_constraints(value) do
      :ok
    end
  end

  defp validate_assignment(%{"role" => _role}), do: {:error, {:invalid_value, "role"}}
  defp validate_assignment(_value), do: {:error, {:missing_fields, ["role"]}}

  defp worker_assignment_types(value) do
    types(value, %{
      "task_id" => &non_empty_binary?/1,
      "run_id" => &non_empty_binary?/1,
      "accepted_revision" => &nullable_sha1?/1,
      "assignment_path" => &non_empty_binary?/1,
      "proposal_path" => &is_nil_value?/1,
      "disabled_operations" => &string_list?/1,
      "configured_model" => &non_empty_binary?/1,
      "configured_model_id" => &non_empty_binary?/1,
      "configured_profile" => &non_empty_binary?/1,
      "configured_reasoning" => &non_empty_binary?/1,
      "expected_checkout_head" => &sha1?/1,
      "ticket" => &is_map/1,
      "candidate_commit" => &nullable_sha1?/1,
      "continuation" => &nil_map_or_present?/1,
      "correction" => &nil_map_or_present?/1,
      "handoff" => &nil_map_or_present?/1
    })
  end

  defp pm_assignment_types(value) do
    types(value, %{
      "task_id" => &non_empty_binary?/1,
      "run_id" => &non_empty_binary?/1,
      "accepted_revision" => &sha1?/1,
      "assignment_path" => &non_empty_binary?/1,
      "proposal_path" => &non_empty_binary?/1,
      "audit_path" => &nullable_binary?/1,
      "profile" => &non_empty_binary?/1,
      "configured_model" => &non_empty_binary?/1,
      "configured_model_id" => &non_empty_binary?/1,
      "configured_reasoning" => &non_empty_binary?/1,
      "max_proposals" => &positive_integer?/1,
      "allowed_operations" => &string_list?/1,
      "disabled_operations" => &string_list?/1,
      "planning_context" => &is_map/1,
      "native_entrypoint" => &(&1 in ~w(AGENTS.md CLAUDE.md))
    })
  end

  defp validate_ticket(ticket) when is_map(ticket) do
    required =
      ~w(task_id outcome priority evidence dependencies scope exclusions acceptance_criteria required_checks review_required_checks checkout base_revision role model requested_operations handoff_path review_path workload)

    optional =
      ~w(integration_only_checks review_inspection_only_reason profile reasoning risk reviewer_profile work_class work_timeout_seconds check_timeout_seconds environment shared_resources scheduling_decision)

    with :ok <- exact_fields(ticket, required, optional),
         :ok <-
           types(ticket, %{
             "task_id" => &non_empty_binary?/1,
             "outcome" => &non_empty_binary?/1,
             "priority" => &priority?/1,
             "evidence" => &string_list?/1,
             "dependencies" => &string_list?/1,
             "scope" => &string_list?/1,
             "exclusions" => &string_list?/1,
             "acceptance_criteria" => &string_list?/1,
             "required_checks" => &argv_list?/1,
             "review_required_checks" => &argv_list?/1,
             "integration_only_checks" => &argv_list?/1,
             "checkout" => &non_empty_binary?/1,
             "base_revision" => &sha1?/1,
             "role" => &(&1 == "developer"),
             "model" => &non_empty_binary?/1,
             "requested_operations" => &string_list?/1,
             "handoff_path" => &non_empty_binary?/1,
             "review_path" => &non_empty_binary?/1,
             "workload" => &(&1 in ~w(lightweight standard heavy)),
             "environment" => &string_map?/1,
             "shared_resources" => &resources?/1
           }) do
      :ok
    end
  end

  defp validate_ticket(_ticket), do: {:error, {:invalid_type, "ticket"}}

  defp reviewer_fields("reviewer", value) do
    missing =
      []
      |> then(fn list ->
        if has_candidate_commit?(value), do: list, else: ["candidate_commit" | list]
      end)
      |> then(fn list ->
        if has_handoff?(value), do: list, else: ["handoff" | list]
      end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_fields, Enum.sort(fields)}}
    end
  end

  defp reviewer_fields("developer", _value), do: :ok

  defp has_candidate_commit?(value) do
    case Map.fetch(value, "candidate_commit") do
      {:ok, val} -> nullable_sha1?(val)
      :error -> false
    end
  end

  defp has_handoff?(value) do
    case Map.fetch(value, "handoff") do
      {:ok, val} -> nil_map_or_present?(val)
      :error -> false
    end
  end

  defp pm_constraints(%{"task_id" => "PM"}), do: :ok
  defp pm_constraints(_value), do: {:error, {:identity_mismatch, "task_id"}}

  defp assignment_task_identity(%{"task_id" => task_id, "ticket" => ticket}) do
    case Map.fetch(ticket, "task_id") do
      {:ok, ^task_id} when is_binary(task_id) and byte_size(task_id) > 0 -> :ok
      {:ok, _other_task_id} -> {:error, {:identity_mismatch, "ticket.task_id"}}
      :error -> {:error, {:missing_fields, ["ticket.task_id"]}}
    end
  end

  defp authority_consistent(%{
         "disabled_operations" => disabled,
         "ticket" => %{"requested_operations" => requested}
       }) do
    case Enum.sort(Enum.filter(requested, &(&1 in disabled))) do
      [] -> :ok
      contradictory -> {:error, {:contradictory_authority, contradictory}}
    end
  end

  defp control_action(%{"action" => action}) when action in @control_actions, do: :ok
  defp control_action(_value), do: {:error, {:invalid_value, "action"}}

  defp optional_binary(value, field) do
    case Map.fetch(value, field) do
      {:ok, field_value} when is_binary(field_value) and byte_size(field_value) > 0 -> :ok
      {:ok, _field_value} -> {:error, {:invalid_type, field}}
      :error -> :ok
    end
  end

  defp optional_role(value) do
    case Map.fetch(value, "role") do
      {:ok, role} when role in @roles -> :ok
      {:ok, _role} -> {:error, {:invalid_value, "role"}}
      :error -> :ok
    end
  end

  defp copy_optional_identity(normalized, value) do
    Enum.reduce(~w(task_id run_id role), normalized, fn key, result ->
      case Map.fetch(value, key) do
        {:ok, field_value} -> Map.put(result, key, field_value)
        :error -> result
      end
    end)
  end

  defp identity(value, opts) do
    Enum.reduce_while(@identity_options, :ok, fn {field, option}, :ok ->
      case Keyword.fetch(opts, option) do
        {:ok, expected} ->
          if Map.get(value, field) == expected,
            do: {:cont, :ok},
            else: {:halt, {:error, {:identity_mismatch, field}}}

        :error ->
          {:cont, :ok}
      end
    end)
  end

  defp size_ok(size, limit)
       when is_integer(limit) and limit >= 0 and is_integer(size) and size <= limit,
       do: :ok

  defp size_ok(_size, _limit), do: {:error, :oversized}

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp is_nil_value?(value), do: value in [nil, :null]

  defp nil_map_or_present?(value) do
    value in [nil, :null] or (is_map(value) and map_size(value) > 0)
  end

  defp string_list?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)

  defp argv_list?(value) do
    is_list(value) and
      Enum.all?(value, fn argv ->
        is_list(argv) and argv != [] and Enum.all?(argv, &non_empty_binary?/1)
      end)
  end

  defp string_map?(value) do
    is_map(value) and
      Enum.all?(value, fn {key, item} -> is_binary(key) and is_binary(item) end)
  end

  defp resources?(value) when is_map(value) do
    keys = ~w(corpus database gpu other service_ports)
    Enum.sort(Map.keys(value)) == keys and Enum.all?(Map.values(value), &string_list?/1)
  end

  defp resources?(_value), do: false
  defp priority?(<<"P", rest::binary>>), do: rest != "" and rest =~ ~r/^\d+$/
  defp priority?(_value), do: false

  defp non_negative_integer?(value), do: is_integer(value) and value >= 0
  defp nullable_binary?(value), do: value in [nil, :null] or is_binary(value)
  defp non_empty_binary?(value), do: is_binary(value) and byte_size(value) > 0

  defp sha1?(value) do
    is_binary(value) and byte_size(value) == 40 and
      value
      |> String.to_charlist()
      |> Enum.all?(&(&1 in ?0..?9 or &1 in ?a..?f))
  end

  defp nullable_sha1?(value), do: value in [nil, :null] or sha1?(value)

  defp failure(reason, evidence), do: {:error, %{reason: reason, evidence: evidence}}
end
