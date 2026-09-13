defmodule PramanaFoundry.RuntimeRoot do
  @moduledoc """
  Resolves and publishes the single active runtime root before supervision starts.

  Test roots and explicit fresh-root probes are created with `File.mkdir/1`, so an
  existing path is a hard failure rather than an accidental reuse of operator state.
  The configured operator root remains immutable under a separate application key;
  only the active root and its explicit resolution marker are published.
  """

  @app :pramana_foundry
  @operator_key :operator_runtime_root
  @active_key :active_runtime_root
  @resolved_key :runtime_root_resolved
  @override "PRAMANA_RUNTIME_ROOT"
  @fresh "PRAMANA_RUNTIME_ROOT_FRESH"
  @random_bytes 16
  @max_symlink_hops 40

  @spec initialize_operator_root!() :: Path.t()
  def initialize_operator_root! do
    case Application.fetch_env(@app, @operator_key) do
      {:ok, root} ->
        validate_absolute!(root, "operator runtime root")

      :error ->
        root = Application.fetch_env!(@app, :runtime_root)
        root = validate_absolute!(root, "operator runtime root")
        Application.put_env(@app, @operator_key, root, persistent: true)
        root
    end
  end

  @spec resolve_and_publish!(atom(), Path.t()) :: Path.t()
  def resolve_and_publish!(mix_env, operator_root) when mix_env in [:dev, :test, :prod] do
    Application.put_env(@app, @resolved_key, false, persistent: true)
    operator_root = validate_absolute!(operator_root, "operator runtime root")
    initialized_operator = initialize_operator_root!()

    if operator_root != initialized_operator do
      raise ArgumentError, "operator runtime root does not match the initialized root"
    end

    override = System.get_env(@override)
    fresh? = mix_env == :test or System.get_env(@fresh) == "1"

    root =
      cond do
        mix_env == :test and is_nil(override) -> create_random_test_root!(operator_root)
        true -> validate_override_or_operator!(override, operator_root, fresh?)
      end

    if fresh? and not (mix_env == :test and is_nil(override)), do: create_exclusive!(root)
    Application.put_env(@app, @active_key, root, persistent: true)
    Application.put_env(@app, @resolved_key, true, persistent: true)
    root
  end

  @spec fetch!() :: Path.t()
  def fetch! do
    with {:ok, true} <- Application.fetch_env(@app, @resolved_key),
         {:ok, root} <- Application.fetch_env(@app, @active_key) do
      validate_absolute!(root, "published runtime root")
    else
      _ -> raise ArgumentError, "runtime root has not been resolved and published"
    end
  end

  defp validate_override_or_operator!(override, operator_root, fresh?) do
    candidate = override || operator_root
    candidate = validate_absolute!(candidate, "runtime root")

    if fresh? and within?(candidate, operator_root) do
      raise ArgumentError, "fresh runtime root cannot target configured operator state"
    end

    candidate
  end

  defp create_random_test_root!(operator_root) do
    suffix =
      @random_bytes |> then(&:crypto.strong_rand_bytes/1) |> Base.url_encode64(padding: false)

    root = Path.join(System.tmp_dir!(), "pramana-foundry-mix-test-#{suffix}")

    if within?(root, operator_root) do
      raise ArgumentError, "generated test runtime root cannot target configured operator state"
    else
      case File.mkdir(root) do
        :ok ->
          root

        {:error, :eexist} ->
          create_random_test_root!(operator_root)

        {:error, reason} ->
          raise File.Error, reason: reason, action: "create test runtime root", path: root
      end
    end
  end

  defp create_exclusive!(root) do
    case File.mkdir(root) do
      :ok ->
        :ok

      {:error, :eexist} ->
        raise ArgumentError, "fresh runtime root already exists"

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create runtime root", path: root
    end
  end

  defp validate_absolute!(root, label) do
    cond do
      not is_binary(root) or String.trim(root) == "" ->
        raise ArgumentError, "#{label} must be a non-empty absolute path"

      Path.type(root) != :absolute ->
        raise ArgumentError, "#{label} must be absolute"

      true ->
        Path.expand(root)
    end
  end

  defp within?(candidate, operator_root) do
    candidate = canonicalize_existing_ancestry!(candidate)
    operator_root = canonicalize_existing_ancestry!(operator_root)

    candidate == operator_root or String.starts_with?(candidate, operator_root <> "/")
  end

  defp canonicalize_existing_ancestry!(path) do
    [root | parts] = Path.split(Path.expand(path))
    resolve_parts!(root, parts, MapSet.new(), 0)
  end

  defp resolve_parts!(current, [], _seen, _hops), do: Path.expand(current)

  defp resolve_parts!(current, [part | rest], seen, hops) do
    next = Path.join(current, part)

    case File.lstat(next) do
      {:ok, %File.Stat{type: :symlink}} ->
        if hops >= @max_symlink_hops or MapSet.member?(seen, next) do
          raise ArgumentError, "runtime root contains a symlink cycle or exceeds the hop limit"
        end

        target =
          case File.read_link(next) do
            {:ok, link} ->
              if Path.type(link) == :absolute,
                do: link,
                else: Path.expand(link, Path.dirname(next))

            {:error, reason} ->
              raise File.Error, reason: reason, action: "read runtime-root symlink", path: next
          end

        [target_root | target_parts] = Path.split(Path.expand(target))
        resolve_parts!(target_root, target_parts ++ rest, MapSet.put(seen, next), hops + 1)

      {:ok, _stat} ->
        resolve_parts!(next, rest, seen, hops)

      {:error, :enoent} ->
        Path.expand(Path.join([next | rest]))

      {:error, reason} ->
        raise File.Error,
          reason: reason,
          action: "inspect runtime-root ancestry",
          path: next
    end
  end
end
