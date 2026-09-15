defmodule PramanaFoundry.CLI.RPC do
  @moduledoc """
  Temporary inert transport for the release RPC wrapper.

  The release still exposes a general evaluation command until FR-15a replaces it
  with the protected local command protocol. This module only ensures that arguments
  sent by `bin/pramana` are data rather than generated Elixir source.
  """

  @max_payload_bytes 65_536
  @max_encoded_bytes 87_382
  @token_regex ~r/\A[A-Za-z0-9_-]+\z/
  @envelope_keys MapSet.new(["argv", "version"])
  @ticket_create_options MapSet.new(["--acceptance", "--scope"])

  @type decode_error ::
          :invalid_encoding
          | :payload_too_large
          | :invalid_utf8
          | :invalid_json
          | :duplicate_json_key
          | :invalid_envelope
          | :invalid_argv
          | :nul_byte
          | :unknown_command_shape

  @doc "Decode, validate and dispatch one wrapper payload."
  @spec run(binary()) :: term()
  def run(encoded) do
    case decode(encoded) do
      {:ok, argv} -> PramanaFoundry.CLI.main(argv)
      {:error, reason} -> raise ArgumentError, "invalid RPC payload: #{reason}"
    end
  end

  @doc "Decode and validate one versioned wrapper payload without dispatching it."
  @spec decode(term()) :: {:ok, [binary()]} | {:error, decode_error()}
  def decode(encoded) when is_binary(encoded) do
    with :ok <- validate_encoded_token(encoded),
         {:ok, payload} <- decode_base64(encoded),
         :ok <- validate_payload_bytes(payload),
         {:ok, envelope} <- decode_json(payload),
         {:ok, argv} <- validate_envelope(envelope),
         :ok <- validate_argv(argv),
         :ok <- validate_command_shape(argv) do
      {:ok, argv}
    end
  end

  def decode(_encoded), do: {:error, :invalid_encoding}

  defp validate_encoded_token(encoded)
       when byte_size(encoded) <= @max_encoded_bytes do
    if Regex.match?(@token_regex, encoded), do: :ok, else: {:error, :invalid_encoding}
  end

  defp validate_encoded_token(_encoded), do: {:error, :payload_too_large}

  defp decode_base64(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, payload} ->
        if Base.url_encode64(payload, padding: false) == encoded do
          {:ok, payload}
        else
          {:error, :invalid_encoding}
        end

      :error ->
        {:error, :invalid_encoding}
    end
  end

  defp validate_payload_bytes(payload) when byte_size(payload) > @max_payload_bytes,
    do: {:error, :payload_too_large}

  defp validate_payload_bytes(payload) do
    if String.valid?(payload), do: :ok, else: {:error, :invalid_utf8}
  end

  defp decode_json(payload) do
    decoders = %{
      object_start: fn _old_acc -> {%{}, MapSet.new()} end,
      object_push: &json_object_push/3,
      object_finish: &json_object_finish/2
    }

    case :json.decode(payload, :root, decoders) do
      {value, :root, <<>>} -> {:ok, value}
      _result -> {:error, :invalid_json}
    end
  rescue
    _error -> {:error, :invalid_json}
  catch
    :throw, {__MODULE__, :duplicate_json_key} -> {:error, :duplicate_json_key}
  end

  defp json_object_push(key, value, {object, seen}) do
    if MapSet.member?(seen, key) do
      throw({__MODULE__, :duplicate_json_key})
    else
      {Map.put(object, key, value), MapSet.put(seen, key)}
    end
  end

  defp json_object_finish({object, _seen}, old_acc), do: {object, old_acc}

  defp validate_envelope(%{"version" => 1, "argv" => argv} = envelope) do
    if envelope |> Map.keys() |> MapSet.new() |> MapSet.equal?(@envelope_keys) do
      {:ok, argv}
    else
      {:error, :invalid_envelope}
    end
  end

  defp validate_envelope(_envelope), do: {:error, :invalid_envelope}

  defp validate_argv(argv) when is_list(argv) do
    cond do
      not Enum.all?(argv, &is_binary/1) -> {:error, :invalid_argv}
      Enum.any?(argv, &String.contains?(&1, <<0>>)) -> {:error, :nul_byte}
      true -> :ok
    end
  end

  defp validate_argv(_argv), do: {:error, :invalid_argv}

  defp validate_command_shape(["handoff", "submit", _task_id, "--handoff-path", _path]),
    do: :ok

  defp validate_command_shape(["handoff", "block", _task_id, "--reason" | [_ | _]]),
    do: :ok

  defp validate_command_shape(["review", "submit", _task_id, "--review-path", _path]),
    do: :ok

  defp validate_command_shape([
         "ticket",
         "create",
         "--title",
         _title,
         "--priority",
         priority
         | options
       ])
       when priority in ["P0", "P1", "P2", "P3"] do
    validate_ticket_create_options(options, MapSet.new())
  end

  defp validate_command_shape(["ticket", "status", _task_id]), do: :ok
  defp validate_command_shape(["ticket", "list"]), do: :ok
  defp validate_command_shape(["ticket", "integrate", _task_id]), do: :ok
  defp validate_command_shape(_argv), do: {:error, :unknown_command_shape}

  defp validate_ticket_create_options([], _seen), do: :ok

  defp validate_ticket_create_options([option, _value | rest], seen) do
    if MapSet.member?(@ticket_create_options, option) and not MapSet.member?(seen, option) do
      validate_ticket_create_options(rest, MapSet.put(seen, option))
    else
      {:error, :unknown_command_shape}
    end
  end

  defp validate_ticket_create_options(_options, _seen), do: {:error, :unknown_command_shape}
end
