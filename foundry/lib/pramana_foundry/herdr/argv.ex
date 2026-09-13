defmodule PramanaFoundry.Herdr.Argv do
  @moduledoc """
  Pure argv builders for every Herdr verb this adapter uses. Every function returns a
  plain list of binaries, never a shell string, and rejects a non-binary or empty
  identity field rather than coercing it.
  """

  @type argv :: [binary()]

  @spec pane_split(binary(), binary(), %{optional(binary()) => binary()}) ::
          {:ok, argv()} | {:error, term()}
  def pane_split(cwd, direction, env)
      when is_binary(cwd) and is_binary(direction) and is_map(env) do
    with :ok <- non_empty(cwd, :cwd),
         :ok <- non_empty(direction, :direction),
         :ok <- env_ok(env) do
      env_args = env |> Enum.sort() |> Enum.flat_map(fn {k, v} -> ["--env", "#{k}=#{v}"] end)

      {:ok,
       ["pane", "split", "--current", "--direction", direction, "--cwd", cwd] ++
         env_args ++ ["--no-focus"]}
    end
  end

  @spec agent_start(binary(), binary(), binary(), pos_integer(), [binary()]) ::
          {:ok, argv()} | {:error, term()}
  def agent_start(name, kind, pane_id, timeout_ms, native_args)
      when is_binary(name) and is_binary(kind) and is_binary(pane_id) and
             is_integer(timeout_ms) and timeout_ms > 0 and is_list(native_args) do
    with :ok <- non_empty(name, :name),
         :ok <- non_empty(kind, :kind),
         :ok <- non_empty(pane_id, :pane_id),
         :ok <- string_list_ok(native_args, :native_args) do
      base = [
        "agent",
        "start",
        name,
        "--kind",
        kind,
        "--pane",
        pane_id,
        "--timeout",
        Integer.to_string(timeout_ms)
      ]

      {:ok, if(native_args == [], do: base, else: base ++ ["--"] ++ native_args)}
    end
  end

  @spec agent_get(binary()) :: {:ok, argv()} | {:error, term()}
  def agent_get(target) when is_binary(target) do
    with :ok <- non_empty(target, :target), do: {:ok, ["agent", "get", target]}
  end

  @spec pane_get(binary()) :: {:ok, argv()} | {:error, term()}
  def pane_get(pane_id) when is_binary(pane_id) do
    with :ok <- non_empty(pane_id, :pane_id), do: {:ok, ["pane", "get", pane_id]}
  end

  @spec pane_process_info(binary()) :: {:ok, argv()} | {:error, term()}
  def pane_process_info(pane_id) when is_binary(pane_id) do
    with :ok <- non_empty(pane_id, :pane_id),
         do: {:ok, ["pane", "process-info", "--pane", pane_id]}
  end

  @spec agent_prompt(binary(), binary()) :: {:ok, argv()} | {:error, term()}
  def agent_prompt(target, text) when is_binary(target) and is_binary(text) do
    with :ok <- non_empty(target, :target), do: {:ok, ["agent", "prompt", target, text]}
  end

  @spec agent_read(binary(), pos_integer()) :: {:ok, argv()} | {:error, term()}
  def agent_read(target, lines) when is_binary(target) and is_integer(lines) and lines > 0 do
    with :ok <- non_empty(target, :target) do
      {:ok,
       [
         "agent",
         "read",
         target,
         "--source",
         "recent-unwrapped",
         "--lines",
         Integer.to_string(lines)
       ]}
    end
  end

  @spec agent_send_keys(binary(), binary()) :: {:ok, argv()} | {:error, term()}
  def agent_send_keys(target, keys) when is_binary(target) and is_binary(keys) do
    with :ok <- non_empty(target, :target), :ok <- non_empty(keys, :keys) do
      {:ok, ["agent", "send-keys", target, keys]}
    end
  end

  @spec pane_close(binary()) :: {:ok, argv()} | {:error, term()}
  def pane_close(pane_id) when is_binary(pane_id) do
    with :ok <- non_empty(pane_id, :pane_id), do: {:ok, ["pane", "close", pane_id]}
  end

  defp non_empty(value, _field) when is_binary(value) and value != "", do: :ok
  defp non_empty(_value, field), do: {:error, {:invalid_identity_field, field}}

  defp env_ok(env) do
    if Enum.all?(env, fn {k, v} -> is_binary(k) and is_binary(v) end),
      do: :ok,
      else: {:error, {:invalid_identity_field, :environment}}
  end

  defp string_list_ok(list, field) do
    if Enum.all?(list, &is_binary/1), do: :ok, else: {:error, {:invalid_identity_field, field}}
  end
end
