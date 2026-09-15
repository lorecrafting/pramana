defmodule PramanaFoundry.LaunchEligibility do
  @moduledoc """
  Temporary fail-closed admission for autonomous model launches.

  This containment contract is intentionally explicit: a profile is eligible only
  when operator configuration names its OMP profile, provider, subscription billing
  class, exact allowed model, reasoning, approval mode, allowed autonomous roles,
  and currently available quota. Credentials and model names are never treated as
  authorization.

  FR-16 will replace the single requested-profile decision with durable bounded
  switching. Until then, this module never selects a fallback profile.
  """

  @roles ~w(developer reviewer pm)
  @billing_classes ~w(subscription paid manual)
  @quota_statuses ~w(available exhausted unknown cooldown)
  @reasoning_levels ~w(off minimal low medium high xhigh max auto)
  @approval_modes ~w(always-ask write yolo)
  @required_binary_fields ~w(provider account model reasoning approval_mode)
  @profile_fields ~w(provider account billing_class subscription_authorized premium_authorized automatic_roles quota_status exhausted model allowed_models approval_mode reasoning)
  @cooldown_fields ~w(profile provider until_epoch reason recorded_at)
  @profile_identity ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @provider_identity ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @exact_model_identity ~r/\A[a-z0-9][a-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._:-]*\z/

  @type authorized_profile :: %{
          name: String.t(),
          provider: String.t(),
          account: String.t(),
          billing_class: String.t(),
          model: String.t(),
          approval_mode: String.t(),
          reasoning: String.t(),
          role: String.t()
        }

  @spec select_profile(term(), term(), atom() | String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def select_profile(explicit_name, role_profiles, role) do
    with {:ok, role_name} <- role_name(role),
         :ok <- valid_role_profiles(role_profiles) do
      case explicit_name do
        nil -> present_profile_name(Map.get(role_profiles, role_name), role_name)
        name -> present_profile_name(name, role_name)
      end
    end
  end

  @spec resolve(term(), term(), atom() | String.t(), term(), keyword()) ::
          {:ok, authorized_profile()} | {:error, term()}
  def resolve(profiles, requested_name, role, workflow_state \\ %{}, opts \\ []) do
    now = if Keyword.keyword?(opts), do: Keyword.get(opts, :now, System.system_time(:second))

    with {:ok, role_name} <- role_name(role),
         {:ok, name} <- present_profile_name(requested_name, role_name),
         :ok <- valid_profiles(profiles),
         :ok <- valid_cooldowns(workflow_state),
         :ok <- valid_now(now),
         {:ok, profile} <- configured_profile(profiles, name),
         :ok <- subscription_authorized(profile),
         :ok <- automatic_role_authorized(profile, role_name),
         :ok <- model_allowed(profile),
         :ok <- quota_available(profile),
         :ok <- not_cooled_down(workflow_state, name, now) do
      {:ok,
       %{
         name: name,
         provider: profile["provider"],
         account: profile["account"],
         billing_class: profile["billing_class"],
         model: profile["model"],
         approval_mode: profile["approval_mode"],
         reasoning: profile["reasoning"],
         role: role_name
       }}
    end
  end

  @doc "Human-readable, stable reason for status and telemetry surfaces."
  @spec reason(term()) :: String.t()
  def reason({:profile_required, role}), do: "no subscription profile configured for #{role}"
  def reason({:profile_not_configured, name}), do: "profile #{inspect(name)} is not configured"

  def reason({:profile_not_subscription_authorized, name}),
    do: "profile #{inspect(name)} is not authorized for subscription billing"

  def reason({:profile_not_authorized_for_role, name, role}),
    do: "profile #{inspect(name)} is not authorized for automatic #{role} launches"

  def reason({:profile_model_not_allowed, name, model}),
    do: "profile #{inspect(name)} does not allow configured model #{inspect(model)}"

  def reason({:profile_quota_unavailable, name, status}),
    do: "profile #{inspect(name)} quota is #{inspect(status)}"

  def reason({:profile_cooldown_active, name}),
    do: "profile #{inspect(name)} has an active cooldown"

  def reason({:profile_field_missing, name, field}),
    do: "profile #{inspect(name)} is missing explicit #{field} configuration"

  def reason({:invalid_profile_field, name, field}),
    do: "profile #{inspect(name)} has invalid #{field} configuration"

  def reason({:invalid_profile_selection, role, _value}),
    do: "invalid explicit profile selection for #{role}"

  def reason({:invalid_role_profile_mapping, detail}),
    do: "invalid automatic role profile mapping: #{detail}"

  def reason({:invalid_cooldown_policy, detail}),
    do: "invalid provider cooldown policy: #{detail}"

  def reason({:unsupported_autonomous_role, role}),
    do: "unsupported autonomous role #{inspect(role)}"

  def reason(:invalid_launch_policy), do: "invalid autonomous launch policy"

  def reason(:subscription_route_not_enforced),
    do: "launch backend does not enforce a subscription-only route"

  def reason(other), do: inspect(other)

  defp role_name(role) when is_atom(role), do: role_name(Atom.to_string(role))
  defp role_name(role) when role in @roles, do: {:ok, role}
  defp role_name(role), do: {:error, {:unsupported_autonomous_role, role}}

  defp valid_role_profiles(role_profiles) do
    if plain_map?(role_profiles) do
      case Enum.find(role_profiles, fn {role, name} ->
             role not in @roles or not canonical_profile_identity?(name)
           end) do
        nil -> :ok
        {role, _name} -> {:error, {:invalid_role_profile_mapping, inspect(role)}}
      end
    else
      {:error, {:invalid_role_profile_mapping, "expected a string-keyed plain map"}}
    end
  end

  defp present_profile_name(nil, role), do: {:error, {:profile_required, role}}

  defp present_profile_name(name, role) do
    if canonical_profile_identity?(name),
      do: {:ok, name},
      else: {:error, {:invalid_profile_selection, role, :invalid}}
  end

  defp valid_profiles(profiles) do
    if plain_map?(profiles) do
      Enum.reduce_while(profiles, :ok, fn {name, profile}, :ok ->
        if canonical_profile_identity?(name) and plain_map?(profile) do
          case valid_profile_shape(profile, name) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        else
          {:halt, {:error, {:invalid_profile_field, name, "profile"}}}
        end
      end)
    else
      {:error, :invalid_launch_policy}
    end
  end

  defp valid_profile_shape(profile, name) do
    with :ok <- only_known_fields(profile, name),
         :ok <- required_fields_present(profile, name),
         :ok <- valid_enum(profile, name, "billing_class", @billing_classes),
         :ok <- valid_required_boolean(profile, name, "subscription_authorized"),
         :ok <- valid_optional_boolean(profile, name, "premium_authorized"),
         :ok <- valid_optional_boolean(profile, name, "exhausted"),
         :ok <- valid_route_selectors(profile, name),
         :ok <- valid_roles(profile, name),
         :ok <- valid_enum(profile, name, "quota_status", @quota_statuses),
         :ok <- valid_string_list(profile, name, "allowed_models"),
         :ok <- valid_enum(profile, name, "reasoning", @reasoning_levels),
         :ok <- valid_enum(profile, name, "approval_mode", @approval_modes) do
      :ok
    end
  end

  defp valid_route_selectors(profile, name) do
    cond do
      not canonical_profile_identity?(profile["account"]) or profile["account"] == "default" ->
        {:error, {:invalid_profile_field, name, "account"}}

      not canonical_provider_identity?(profile["provider"]) ->
        {:error, {:invalid_profile_field, name, "provider"}}

      not exact_model_identity?(profile["model"]) ->
        {:error, {:invalid_profile_field, name, "model"}}

      true ->
        :ok
    end
  end

  defp only_known_fields(profile, name) do
    if Enum.all?(profile, fn {field, _value} -> field in @profile_fields end),
      do: :ok,
      else: {:error, {:invalid_profile_field, name, "unknown field"}}
  end

  defp required_fields_present(profile, name) do
    case Enum.find(@required_binary_fields, fn field ->
           not (is_binary(profile[field]) and profile[field] != "")
         end) do
      nil -> :ok
      field -> {:error, {:profile_field_missing, name, field}}
    end
  end

  defp valid_required_boolean(profile, name, field) do
    case Map.fetch(profile, field) do
      {:ok, value} when is_boolean(value) -> :ok
      {:ok, _value} -> {:error, {:invalid_profile_field, name, field}}
      :error -> {:error, {:profile_field_missing, name, field}}
    end
  end

  defp valid_optional_boolean(profile, name, field) do
    case Map.fetch(profile, field) do
      {:ok, value} when is_boolean(value) -> :ok
      {:ok, _value} -> {:error, {:invalid_profile_field, name, field}}
      :error -> :ok
    end
  end

  defp valid_roles(profile, name) do
    case Map.fetch(profile, "automatic_roles") do
      {:ok, roles} when is_list(roles) ->
        if proper_list?(roles) and Enum.all?(roles, &(&1 in @roles)) and
             Enum.uniq(roles) == roles,
           do: :ok,
           else: {:error, {:invalid_profile_field, name, "automatic_roles"}}

      {:ok, _roles} ->
        {:error, {:invalid_profile_field, name, "automatic_roles"}}

      :error ->
        {:error, {:profile_field_missing, name, "automatic_roles"}}
    end
  end

  defp valid_string_list(profile, name, field) do
    case Map.fetch(profile, field) do
      {:ok, values} when is_list(values) ->
        if proper_list?(values) and values != [] and
             Enum.all?(values, &exact_model_identity?/1) and Enum.uniq(values) == values,
           do: :ok,
           else: {:error, {:invalid_profile_field, name, field}}

      {:ok, _values} ->
        {:error, {:invalid_profile_field, name, field}}

      :error ->
        {:error, {:profile_field_missing, name, field}}
    end
  end

  defp valid_enum(profile, name, field, allowed) do
    case Map.fetch(profile, field) do
      {:ok, value} when is_binary(value) ->
        if value in allowed,
          do: :ok,
          else: {:error, {:invalid_profile_field, name, field}}

      {:ok, _value} ->
        {:error, {:invalid_profile_field, name, field}}

      :error ->
        {:error, {:profile_field_missing, name, field}}
    end
  end

  defp configured_profile(profiles, name) do
    case Map.fetch(profiles, name) do
      {:ok, profile} -> {:ok, Map.put(profile, "name", name)}
      :error -> {:error, {:profile_not_configured, name}}
    end
  end

  defp subscription_authorized(profile) do
    name = profile_name(profile)

    if profile["subscription_authorized"] == true and
         profile["billing_class"] == "subscription" and
         profile["premium_authorized"] != true do
      :ok
    else
      {:error, {:profile_not_subscription_authorized, name}}
    end
  end

  defp automatic_role_authorized(profile, role) do
    if role in profile["automatic_roles"],
      do: :ok,
      else: {:error, {:profile_not_authorized_for_role, profile_name(profile), role}}
  end

  defp model_allowed(profile) do
    if profile["model"] in profile["allowed_models"],
      do: :ok,
      else: {:error, {:profile_model_not_allowed, profile_name(profile), profile["model"]}}
  end

  defp quota_available(profile) do
    if profile["quota_status"] == "available" and profile["exhausted"] != true do
      :ok
    else
      {:error, {:profile_quota_unavailable, profile_name(profile), profile["quota_status"]}}
    end
  end

  defp valid_cooldowns(workflow_state) do
    if plain_map?(workflow_state) do
      case Map.fetch(workflow_state, "provider_cooldowns") do
        :error -> :ok
        {:ok, cooldowns} -> validate_cooldown_container(cooldowns)
      end
    else
      {:error, {:invalid_cooldown_policy, "expected workflow state plain map"}}
    end
  end

  defp validate_cooldown_container(cooldowns) do
    if plain_map?(cooldowns),
      do: validate_cooldown_entries(cooldowns),
      else: {:error, {:invalid_cooldown_policy, "expected a plain map"}}
  end

  defp validate_cooldown_entries(cooldowns) do
    case Enum.find(cooldowns, fn {name, entry} ->
           not canonical_profile_identity?(name) or not plain_map?(entry) or
             invalid_cooldown_entry?(entry)
         end) do
      nil -> :ok
      {name, _entry} -> {:error, {:invalid_cooldown_policy, "invalid entry #{inspect(name)}"}}
    end
  end

  defp invalid_cooldown_entry?(entry) do
    Enum.any?(Map.keys(entry), &(&1 not in @cooldown_fields)) or
      not (is_integer(entry["until_epoch"]) and entry["until_epoch"] >= 0) or
      invalid_optional_string?(entry, "profile") or
      invalid_optional_string?(entry, "provider") or
      invalid_optional_string?(entry, "reason") or
      invalid_optional_string?(entry, "recorded_at") or
      invalid_optional_identity?(entry, "profile", @profile_identity) or
      invalid_optional_identity?(entry, "provider", @provider_identity)
  end

  defp invalid_optional_string?(entry, field) do
    case Map.fetch(entry, field) do
      {:ok, value} -> not canonical_nonempty_string?(value)
      :error -> false
    end
  end

  defp invalid_optional_identity?(entry, field, pattern) do
    case Map.fetch(entry, field) do
      {:ok, value} -> not canonical_identity?(value, pattern)
      :error -> false
    end
  end

  defp valid_now(now) when is_integer(now) and now >= 0, do: :ok
  defp valid_now(_now), do: {:error, {:invalid_cooldown_policy, "invalid current epoch"}}

  defp not_cooled_down(state, name, now) do
    case get_in(state, ["provider_cooldowns", name]) do
      %{"until_epoch" => until_epoch} when now < until_epoch ->
        {:error, {:profile_cooldown_active, name}}

      _ ->
        :ok
    end
  end

  defp profile_name(profile), do: Map.get(profile, "name", "<requested>")

  defp canonical_profile_identity?(value) when is_binary(value),
    do: value != "default" and canonical_identity?(value, @profile_identity)

  defp canonical_profile_identity?(_value), do: false

  defp canonical_provider_identity?(value),
    do: canonical_identity?(value, @provider_identity)

  defp exact_model_identity?(value),
    do: canonical_identity?(value, @exact_model_identity)

  defp canonical_identity?(value, pattern) when is_binary(value),
    do: canonical_nonempty_string?(value) and Regex.match?(pattern, value)

  defp canonical_identity?(_value, _pattern), do: false

  defp canonical_nonempty_string?(value) when is_binary(value),
    do: value != "" and String.valid?(value) and String.trim(value) == value

  defp canonical_nonempty_string?(_value), do: false

  defp proper_list?([]), do: true
  defp proper_list?([_head | tail]), do: proper_list?(tail)
  defp proper_list?(_value), do: false

  defp plain_map?(value), do: is_map(value) and not is_struct(value)
end
