defmodule PramanaFoundry.CI.FR15aAValidator do
  @moduledoc false

  @schema "pramana-foundry-fr15aa-provisioning/v1"
  @statuses ~w(blocked unavailable supported)
  @required_categories ~w(
    harness replacement_harness model_request shell file_read file_write custom_tools
    explicit_extensions discovered_extensions startup_code build_hooks language_services
    subprocesses inherited_environment inherited_file_descriptors network network_proxy ipc
    process_memory git_metadata shared_state herdr_presentation role_slot_reuse cleanup
    controlled_acquisition build runtime
  )
  @required_principals ~w(
    root launcher auth_gateway harness presentation fetch slot_developer slot_reviewer slot_pm
    build runtime
  )
  @mapped_fields ~w(principal channel credential_policy network_policy acceptance_probe)a

  @spec validate(term()) :: :ok | {:error, [String.t()]}
  def validate(spec) when is_map(spec) do
    errors =
      []
      |> check(spec[:schema] == @schema, "unexpected or missing schema")
      |> check(spec[:authority][:governing_harness] == "omp", "OMP must remain governing")
      |> check(
        spec[:authority][:replacement_disposition] == "evaluated_blocked_not_selected",
        "Pi must remain an unselected blocked candidate"
      )
      |> check(
        spec[:authority][:production_disposition] == "blocked_pending_fr15ab_and_fr09",
        "production must remain blocked behind FR-15aB and FR-09"
      )
      |> validate_unique(spec[:pins], :id, "pin")
      |> validate_unique(spec[:principals], :id, "principal")
      |> validate_unique(spec[:channels], :id, "channel")
      |> validate_unique(spec[:routes], :id, "route")
      |> validate_required_ids(spec[:principals], @required_principals, "principal")
      |> validate_categories(spec[:routes])
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

  defp validate_unique(errors, entries, key, label) when is_list(entries) do
    ids = Enum.map(entries, & &1[key])

    check(
      errors,
      Enum.all?(ids, &(is_binary(&1) and &1 != "")) and length(ids) == length(Enum.uniq(ids)),
      "#{label} ids must be non-empty and unique"
    )
  end

  defp validate_unique(errors, _entries, _key, label),
    do: ["#{label} inventory must be a list" | errors]

  defp validate_required_ids(errors, entries, required, label) when is_list(entries) do
    actual = MapSet.new(entries, & &1.id)
    missing = Enum.reject(required, &MapSet.member?(actual, &1))
    check(errors, missing == [], "missing required #{label}s: #{Enum.join(missing, ", ")}")
  end

  defp validate_required_ids(errors, _entries, required, label),
    do: ["missing required #{label}s: #{Enum.join(required, ", ")}" | errors]

  defp validate_categories(errors, routes) when is_list(routes) do
    actual = MapSet.new(routes, & &1.category)
    required = MapSet.new(@required_categories)
    missing = required |> MapSet.difference(actual) |> Enum.sort()
    unexpected = actual |> MapSet.difference(required) |> Enum.sort()

    errors
    |> check(missing == [], "missing executable categories: #{Enum.join(missing, ", ")}")
    |> check(
      unexpected == [],
      "unrecognized executable categories: #{Enum.join(unexpected, ", ")}"
    )
  end

  defp validate_categories(errors, _routes), do: ["routes must be a list" | errors]

  defp validate_pins(errors, pins) when is_list(pins) do
    Enum.reduce(pins, errors, fn pin, acc ->
      implemented? = pin.status not in ["blocked"]
      digest_ok? = Regex.match?(~r/\A[0-9a-f]{64}\z/, pin.sha256)

      acc
      |> check(
        is_binary(pin.version) and pin.version != "",
        "pin #{inspect(pin.id)} needs a version"
      )
      |> check(is_binary(pin.path) and pin.path != "", "pin #{inspect(pin.id)} needs a path")
      |> check(
        not implemented? or digest_ok? or pin.sha256 == "not-recorded-checkpoint-f",
        "implemented pin #{inspect(pin.id)} needs a recorded SHA-256 or explicit checkpoint limitation"
      )
      |> check(
        implemented? or pin.sha256 == "unimplemented",
        "blocked adapter #{inspect(pin.id)} must be marked unimplemented"
      )
    end)
  end

  defp validate_pins(errors, _pins), do: errors

  defp validate_routes(errors, spec) do
    pins = MapSet.new(spec.pins, & &1.id)
    principals = MapSet.new(spec.principals, & &1.id)
    channels = MapSet.new(spec.channels, & &1.id)

    Enum.reduce(spec.routes, errors, fn route, acc ->
      status = route[:production_status]
      unsupported? = status in ["blocked", "unavailable"]

      acc
      |> check(status in @statuses, "route #{inspect(route[:id])} has invalid status")
      |> check(
        is_list(route[:executable_ids]) and route.executable_ids != [],
        "route #{inspect(route[:id])} needs executable pins"
      )
      |> check(
        Enum.all?(route[:executable_ids] || [], &MapSet.member?(pins, &1)),
        "route #{inspect(route[:id])} references an unknown executable pin"
      )
      |> check(
        MapSet.member?(principals, route[:principal]),
        "route #{inspect(route[:id])} references an unknown principal"
      )
      |> check(
        MapSet.member?(channels, route[:channel]),
        "route #{inspect(route[:id])} references an unknown channel"
      )
      |> check(
        Enum.all?(@mapped_fields, &non_empty?(route[&1])),
        "route #{inspect(route[:id])} lacks principal/channel/credential/network/probe mapping"
      )
      |> check(
        not unsupported? or route[:fail_closed] == true,
        "unsupported route #{inspect(route[:id])} must fail closed"
      )
      |> check(
        not unsupported? or non_empty?(route[:blocker]),
        "unsupported route #{inspect(route[:id])} must name its blocker"
      )
    end)
  end

  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""

  defp check(errors, true, _message), do: errors
  defp check(errors, false, message), do: [message | errors]
end

unless System.get_env("MIX_ENV") == "test" do
  manifest_path = Path.expand("../docs/fr-15a/provisioning-manifest.exs", __DIR__)
  {manifest, _binding} = Code.eval_file(manifest_path)

  case PramanaFoundry.CI.FR15aAValidator.validate(manifest) do
    :ok ->
      IO.puts("FR-15aA provisioning manifest: valid")

    {:error, errors} ->
      Enum.each(errors, &IO.puts(:stderr, "FR-15aA validation error: #{&1}"))
      System.halt(1)
  end
end
