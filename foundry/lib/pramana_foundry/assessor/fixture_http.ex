defmodule PramanaFoundry.Assessor.FixtureHTTP do
  @moduledoc """
  Bounded loopback-only HTTP transport for Stage A fixtures.

  This is intentionally not a production TypeSafe transport. It accepts only plain HTTP
  to localhost/127.0.0.1, performs exactly one request, has no retry path, requires no
  SDK, and bounds response headers/body before returning them to the Jev adapter.
  """

  @behaviour PramanaFoundry.Assessor.Transport

  @max_header_bytes 16_384
  @loopback_hosts ["127.0.0.1", "localhost"]

  @impl true
  def post(body, opts) when is_binary(body) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 2_000)
    max_response_bytes = Keyword.get(opts, :max_response_bytes, 131_072)

    with {:ok, endpoint} <- endpoint(Keyword.get(opts, :endpoint)),
         :ok <- positive_integer(timeout_ms),
         :ok <- positive_integer(max_response_bytes),
         {:ok, headers} <- headers(Keyword.get(opts, :headers, [])),
         {:ok, socket} <- connect(endpoint, timeout_ms) do
      try do
        with :ok <- send_request(socket, endpoint, headers, body),
             {:ok, status, response_headers, response_body} <-
               receive_response(socket, timeout_ms, max_response_bytes) do
          {:ok, status, response_headers, response_body}
        end
      after
        :gen_tcp.close(socket)
      end
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
    end
  end

  def post(_body, _opts), do: {:error, :transport_failure}

  defp endpoint(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{
        scheme: "http",
        host: host,
        port: port,
        userinfo: nil,
        fragment: nil
      } = uri
      when host in @loopback_hosts ->
        port = port || 80
        path = if uri.path in [nil, ""], do: "/", else: uri.path
        path = if is_binary(uri.query), do: path <> "?" <> uri.query, else: path

        if is_integer(port) and port > 0 and port <= 65_535,
          do: {:ok, %{host: host, port: port, path: path}},
          else: {:error, :invalid_endpoint}

      _ ->
        {:error, :invalid_endpoint}
    end
  end

  defp endpoint(_value), do: {:error, :invalid_endpoint}

  defp positive_integer(value) when is_integer(value) and value > 0, do: :ok
  defp positive_integer(_value), do: {:error, :invalid_transport_limit}

  defp headers(value) when is_list(value) do
    if Enum.all?(value, &valid_header?/1), do: {:ok, value}, else: {:error, :invalid_header}
  end

  defp headers(_value), do: {:error, :invalid_header}

  defp valid_header?({name, value}) when is_binary(name) and is_binary(value) do
    name != "" and not String.contains?(name, ["\r", "\n", ":"]) and
      not String.contains?(value, ["\r", "\n"])
  end

  defp valid_header?(_header), do: false

  defp connect(endpoint, timeout_ms) do
    options = [:binary, active: false, packet: :raw]

    case :gen_tcp.connect(String.to_charlist(endpoint.host), endpoint.port, options, timeout_ms) do
      {:ok, socket} -> {:ok, socket}
      {:error, :timeout} -> {:error, :timeout}
      {:error, _reason} -> {:error, :transport_failure}
    end
  end

  defp send_request(socket, endpoint, headers, body) do
    host = endpoint.host <> ":" <> Integer.to_string(endpoint.port)

    request =
      [
        "POST ",
        endpoint.path,
        " HTTP/1.1\r\n",
        "Host: ",
        host,
        "\r\n",
        Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end),
        "Content-Length: ",
        Integer.to_string(byte_size(body)),
        "\r\n",
        "Connection: close\r\n\r\n",
        body
      ]

    case :gen_tcp.send(socket, request) do
      :ok -> :ok
      {:error, _reason} -> {:error, :transport_failure}
    end
  end

  defp receive_response(socket, timeout_ms, max_response_bytes) do
    with {:ok, header_bytes, initial_body} <- receive_headers(socket, timeout_ms, <<>>),
         {:ok, status, headers} <- parse_headers(header_bytes),
         {:ok, body} <-
           receive_body(socket, headers, initial_body, timeout_ms, max_response_bytes) do
      {:ok, status, headers, body}
    end
  end

  defp receive_headers(socket, timeout_ms, acc) do
    case :binary.match(acc, "\r\n\r\n") do
      {index, 4} ->
        if index <= @max_header_bytes do
          <<header_bytes::binary-size(^index), _separator::binary-size(4), body::binary>> = acc
          {:ok, header_bytes, body}
        else
          {:error, :response_headers_too_large}
        end

      :nomatch when byte_size(acc) > @max_header_bytes ->
        {:error, :response_headers_too_large}

      :nomatch ->
        case :gen_tcp.recv(socket, 0, timeout_ms) do
          {:ok, chunk} -> receive_headers(socket, timeout_ms, acc <> chunk)
          {:error, :timeout} -> {:error, :timeout}
          {:error, _reason} -> {:error, :transport_failure}
        end
    end
  end

  defp parse_headers(bytes) do
    case String.split(bytes, "\r\n", trim: true) do
      [status_line | lines] ->
        with {:ok, status} <- status(status_line),
             {:ok, headers} <- header_map(lines) do
          {:ok, status, headers}
        end

      _ ->
        {:error, :invalid_http_response}
    end
  end

  defp status(line) do
    case Regex.run(~r/\AHTTP\/1\.[01] ([0-9]{3})(?: |\z)/, line) do
      [_, digits] ->
        value = String.to_integer(digits)
        if value in 100..599, do: {:ok, value}, else: {:error, :invalid_http_response}

      _ ->
        {:error, :invalid_http_response}
    end
  end

  defp header_map(lines) do
    Enum.reduce_while(lines, {:ok, %{}}, fn line, {:ok, acc} ->
      case :binary.split(line, ":", [:global]) do
        [name, value] ->
          key = name |> String.trim() |> String.downcase()
          value = String.trim(value)

          if key == "" or Map.has_key?(acc, key),
            do: {:halt, {:error, :invalid_http_response}},
            else: {:cont, {:ok, Map.put(acc, key, value)}}

        _ ->
          {:halt, {:error, :invalid_http_response}}
      end
    end)
  end

  defp receive_body(socket, headers, initial, timeout_ms, max_response_bytes) do
    case Map.get(headers, "content-length") do
      nil ->
        receive_until_close(socket, initial, timeout_ms, max_response_bytes)

      value ->
        case Integer.parse(value) do
          {length, ""} when length >= 0 and length <= max_response_bytes ->
            receive_length(socket, initial, length, timeout_ms)

          {length, ""} when length > max_response_bytes ->
            {:error, :response_too_large}

          _ ->
            {:error, :invalid_http_response}
        end
    end
  end

  defp receive_length(_socket, initial, length, _timeout_ms) when byte_size(initial) > length,
    do: {:error, :invalid_http_response}

  defp receive_length(_socket, initial, length, _timeout_ms) when byte_size(initial) == length,
    do: {:ok, initial}

  defp receive_length(socket, initial, length, timeout_ms) do
    remaining = length - byte_size(initial)

    case :gen_tcp.recv(socket, remaining, timeout_ms) do
      {:ok, chunk} when byte_size(chunk) == remaining -> {:ok, initial <> chunk}
      {:ok, _chunk} -> {:error, :invalid_http_response}
      {:error, :timeout} -> {:error, :timeout}
      {:error, _reason} -> {:error, :transport_failure}
    end
  end

  defp receive_until_close(socket, acc, timeout_ms, max_response_bytes) do
    if byte_size(acc) > max_response_bytes do
      {:error, :response_too_large}
    else
      case :gen_tcp.recv(socket, 0, timeout_ms) do
        {:ok, chunk} ->
          receive_until_close(socket, acc <> chunk, timeout_ms, max_response_bytes)

        {:error, :closed} ->
          {:ok, acc}

        {:error, :timeout} ->
          {:error, :timeout}

        {:error, _reason} ->
          {:error, :transport_failure}
      end
    end
  end
end
