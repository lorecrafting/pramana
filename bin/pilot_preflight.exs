defmodule Pramana.PilotPreflight do
  @moduledoc false

  @schema "pramana-pilot-preflight/v1"

  @mandatory_gates ~w(
    foundry_g0
    pilot_scope
    cbeta_rights
    lexicon_rights
    inference_authority
    provider_terms
    bilingual_evaluators
    participant_protocol
    retrieval_baseline
    evaluation_rubric
    critical_taxonomy
    rehearsal_trust
  )

  @states ~w(ready blocked)

  @spec load_manifest!(String.t()) :: map()
  def load_manifest!(path) do
    path
    |> File.read!()
    |> :json.decode()
  end

  @spec validate(map(), String.t()) :: :ok | {:error, [String.t()]}
  def validate(manifest, root) when is_map(manifest) do
    errors =
      []
      |> check_top_level(manifest)
      |> check_revision(manifest["subject_revision"])
      |> check_gates(manifest["gates"], root)

    case Enum.reverse(errors) do
      [] -> :ok
      found -> {:error, found}
    end
  end

  def validate(_manifest, _root), do: {:error, ["manifest must be an object"]}

  @spec status(map()) :: String.t()
  def status(%{"gates" => gates}) when is_list(gates) do
    if Enum.all?(gates, &(&1["state"] == "ready")), do: "ready", else: "blocked"
  end

  def status(_manifest), do: "invalid"

  @spec ready(map(), String.t(), String.t()) :: :ok | {:error, [String.t()]}
  def ready(manifest, root, current_revision) do
    with :ok <- validate(manifest, root) do
      errors =
        []
        |> add_if(status(manifest) != "ready", "one or more mandatory gates are blocked")
        |> add_if(
          manifest["subject_revision"] != current_revision,
          "subject_revision must equal the exact current Git revision"
        )

      case Enum.reverse(errors) do
        [] -> :ok
        found -> {:error, found}
      end
    end
  end

  @spec default_manifest(String.t()) :: String.t()
  def default_manifest(root), do: Path.join(root, "docs/strategy/pilot_preflight.json")

  @spec git_revision!(String.t()) :: String.t()
  def git_revision!(root) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      {output, status} -> raise "git rev-parse failed (#{status}): #{String.trim(output)}"
    end
  end

  defp check_top_level(errors, manifest) do
    expected = MapSet.new(~w(schema pilot_id subject_revision gates))
    actual = manifest |> Map.keys() |> MapSet.new()

    errors
    |> add_if(manifest["schema"] != @schema, "schema must be #{@schema}")
    |> add_if(not nonempty_string?(manifest["pilot_id"]), "pilot_id must be a non-empty string")
    |> add_if(
      MapSet.difference(actual, expected) != MapSet.new(),
      "manifest contains unknown top-level fields"
    )
    |> add_if(
      MapSet.difference(expected, actual) != MapSet.new(),
      "manifest is missing required top-level fields"
    )
  end

  defp check_revision(errors, nil), do: errors

  defp check_revision(errors, revision) do
    add_if(
      errors,
      not (is_binary(revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, revision)),
      "subject_revision must be null or a 40-character lowercase Git SHA"
    )
  end

  defp check_gates(errors, gates, root) when is_list(gates) do
    ids = Enum.map(gates, & &1["id"])

    errors =
      errors
      |> add_if(length(ids) != length(Enum.uniq(ids)), "gate ids must be unique")
      |> add_if(
        Enum.sort(ids) != Enum.sort(@mandatory_gates),
        "gate ids must match the complete mandatory gate set"
      )

    Enum.reduce(gates, errors, &check_gate(&1, &2, root))
  end

  defp check_gates(errors, _gates, _root), do: ["gates must be an array" | errors]

  defp check_gate(gate, errors, root) when is_map(gate) do
    expected = MapSet.new(~w(id state reason evidence))
    actual = gate |> Map.keys() |> MapSet.new()
    state = gate["state"]
    reason = gate["reason"]
    evidence = gate["evidence"]

    errors =
      errors
      |> add_if(MapSet.difference(actual, expected) != MapSet.new(), "gate contains unknown fields")
      |> add_if(
        MapSet.difference(expected, actual) != MapSet.new(),
        "gate is missing required fields"
      )
      |> add_if(not nonempty_string?(gate["id"]), "gate id must be a non-empty string")
      |> add_if(state not in @states, "gate #{inspect(gate["id"])} has invalid state")
      |> add_if(not valid_evidence?(evidence), "gate #{inspect(gate["id"])} evidence must be non-empty")
      |> check_gate_state(gate["id"], state, reason)

    Enum.reduce(evidence_list(evidence), errors, fn reference, acc ->
      add_if(acc, not valid_evidence_reference?(reference, root), "invalid evidence reference #{inspect(reference)}")
    end)
  end

  defp check_gate(_gate, errors, _root), do: ["every gate must be an object" | errors]

  defp check_gate_state(errors, id, "ready", reason) do
    add_if(errors, reason not in [nil, ""], "ready gate #{inspect(id)} must not carry a blocking reason")
  end

  defp check_gate_state(errors, id, "blocked", reason) do
    add_if(errors, not nonempty_string?(reason), "blocked gate #{inspect(id)} must carry a reason")
  end

  defp check_gate_state(errors, _id, _state, _reason), do: errors

  defp valid_evidence?(evidence) when is_list(evidence) and evidence != [] do
    Enum.all?(evidence, &nonempty_string?/1)
  end

  defp valid_evidence?(_evidence), do: false

  defp evidence_list(evidence) when is_list(evidence), do: evidence
  defp evidence_list(_evidence), do: []

  defp valid_evidence_reference?(reference, root) do
    [path | _fragment] = String.split(reference, "#", parts: 2)

    safe_relative_path?(path) and
      File.regular?(Path.join(root, path))
  end

  defp safe_relative_path?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and ".." not in Path.split(path)
  end

  defp safe_relative_path?(_path), do: false

  defp nonempty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp add_if(errors, true, message), do: [message | errors]
  defp add_if(errors, false, _message), do: errors
end
