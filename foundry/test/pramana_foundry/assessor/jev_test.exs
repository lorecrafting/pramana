defmodule PramanaFoundry.Assessor.JevTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Assessor.Candidate
  alias PramanaFoundry.Assessor.ContextSelector
  alias PramanaFoundry.Assessor.FixtureHTTP
  alias PramanaFoundry.Assessor.Jev
  alias PramanaFoundry.Assessor.Policy
  alias PramanaFoundry.Assessor.Request

  defmodule HTTPFixture do
    use GenServer

    def start_link({parent, response}) do
      GenServer.start_link(__MODULE__, {parent, response})
    end

    def endpoint(pid), do: GenServer.call(pid, :endpoint)
    def arm(pid), do: GenServer.cast(pid, :arm)

    @impl true
    def init({parent, response}) do
      {:ok, listen} =
        :gen_tcp.listen(0, [
          :binary,
          active: false,
          reuseaddr: true,
          ip: {127, 0, 0, 1}
        ])

      {:ok, {_ip, port}} = :inet.sockname(listen)
      {:ok, %{parent: parent, response: response, listen: listen, port: port}}
    end

    @impl true
    def handle_call(:endpoint, _from, state),
      do: {:reply, "http://127.0.0.1:#{state.port}/v1/systemone", state}

    @impl true
    def handle_cast(:arm, state) do
      send(self(), :accept)
      {:noreply, state}
    end

    @impl true
    def handle_info(:accept, state) do
      case :gen_tcp.accept(state.listen) do
        {:ok, socket} ->
          case read_request(socket, <<>>) do
            {:ok, request} ->
              send(state.parent, {:fixture_request, self(), request})
              respond(socket, state.response)
              send(self(), :accept)
              {:noreply, state}

            {:error, _reason} ->
              :gen_tcp.close(socket)
              send(self(), :accept)
              {:noreply, state}
          end

        {:error, _reason} ->
          {:stop, :normal, state}
      end
    end

    @impl true
    def terminate(_reason, state) do
      :gen_tcp.close(state.listen)
      :ok
    end

    defp respond(socket, {:status, status, body}) do
      response = [
        "HTTP/1.1 ",
        Integer.to_string(status),
        " Fixture\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ",
        Integer.to_string(byte_size(body)),
        "\r\nConnection: close\r\n\r\n",
        body
      ]

      :ok = :gen_tcp.send(socket, response)
      :gen_tcp.close(socket)
    end

    defp respond(socket, :close), do: :gen_tcp.close(socket)

    defp respond(socket, :hold) do
      receive do
        {:fixture_release, response} -> respond(socket, response)
      after
        5_000 -> :gen_tcp.close(socket)
      end
    end

    defp read_request(socket, acc) do
      case :binary.match(acc, "\r\n\r\n") do
        {index, 4} ->
          <<headers::binary-size(index), _separator::binary-size(4), body::binary>> = acc
          parse_request(socket, headers, body)

        :nomatch ->
          case :gen_tcp.recv(socket, 0, 1_000) do
            {:ok, chunk} -> read_request(socket, acc <> chunk)
            {:error, reason} -> {:error, reason}
          end
      end
    end

    defp parse_request(socket, header_bytes, body) do
      [request_line | header_lines] = String.split(header_bytes, "\r\n", trim: true)

      headers =
        Map.new(header_lines, fn line ->
          [name, value] = String.split(line, ":", parts: 2)
          {String.downcase(String.trim(name)), String.trim(value)}
        end)

      length = headers["content-length"] |> String.to_integer()
      remaining = length - byte_size(body)

      with {:ok, rest} <- receive_remaining(socket, remaining) do
        {:ok, %{request_line: request_line, headers: headers, body: body <> rest}}
      end
    end

    defp receive_remaining(_socket, 0), do: {:ok, <<>>}

    defp receive_remaining(socket, remaining) when remaining > 0 do
      case :gen_tcp.recv(socket, remaining, 1_000) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  test "local HTTP fixture receives the pinned Jev wire request exactly once" do
    request = request()
    body = valid_response(request)
    {server, endpoint} = start_fixture({:status, 200, body})

    result =
      Jev.assess(request,
        api_key: "fixture-secret",
        transport: FixtureHTTP,
        endpoint: endpoint
      )

    assert result.status == :valid
    assert result.model == "jev-1.13.0"
    assert result.usage == %{"input_tokens" => 12, "output_tokens" => 3}
    assert Enum.map(result.recommendations, & &1.candidate_id) == ["a", "b"]
    assert Enum.all?(result.recommendations, &is_integer(&1.score_micros))
    assert Enum.all?(result.recommendations, &is_integer(&1.confidence_ppm))

    assert_receive {:fixture_request, ^server, wire}
    assert wire.request_line == "POST /v1/systemone HTTP/1.1"
    assert wire.headers["authorization"] == "Bearer fixture-secret"
    assert wire.headers["content-type"] == "application/json"

    decoded = :json.decode(wire.body)
    assert decoded["model"] == "jev-1.13.0"

    assert Map.keys(decoded["questions"]) |> Enum.sort() ==
             ["any_relevant", "candidate:a", "candidate:b"]

    assert decoded["state"]["candidate_manifest_digest"] == request.candidate_digest
    assert decoded["state"]["policy"]["question_set_version"] == Jev.question_set_version()
    assert decoded["state"]["policy"]["selection_version"] == ContextSelector.selection_version()
    assert decoded["state"]["policy"]["max_initial_optional"] == 2
    assert decoded["questions"]["candidate:a"]["instructions"] =~ "`candidates[0].content`"
    assert decoded["questions"]["candidate:a"]["instructions"] =~ "`task.objective`"
    refute_receive {:fixture_request, ^server, _wire}, 50
  end

  test "missing authorization and pre-issue cancellation perform zero HTTP calls" do
    request = request()

    for opts <- [
          [transport: FixtureHTTP],
          [api_key: "fixture-secret", transport: FixtureHTTP, cancelled?: fn -> true end]
        ] do
      {server, endpoint} = start_fixture({:status, 200, valid_response(request)})
      result = Jev.assess(request, Keyword.put(opts, :endpoint, endpoint))

      assert result.status == :not_requested
      refute_receive {:fixture_request, ^server, _wire}, 50
    end
  end

  test "HTTP authentication, validation, rate-limit and overload statuses are explicit and never retried" do
    request = request()

    for {status, result_status, reason} <- [
          {401, :unavailable, :authentication_failed},
          {422, :invalid, :provider_rejected_request},
          {429, :unavailable, :rate_limited},
          {529, :unavailable, :provider_overloaded}
        ] do
      {server, endpoint} = start_fixture({:status, status, ~s({"error":"fixture"})})

      result =
        Jev.assess(request,
          api_key: "fixture-secret",
          transport: FixtureHTTP,
          endpoint: endpoint
        )

      assert result.status == result_status
      assert result.reason == reason
      assert_receive {:fixture_request, ^server, _wire}
      refute_receive {:fixture_request, ^server, _wire}, 50
    end
  end

  test "cancellation after issue prevents a late response from being applied" do
    request = request()
    parent = self()
    {:ok, checks} = Agent.start_link(fn -> 0 end)

    cancelled? = fn ->
      Agent.get_and_update(checks, fn count -> {count > 0, count + 1} end)
    end

    result =
      Jev.assess(request,
        api_key: "fixture-secret",
        cancelled?: cancelled?,
        transport: fn _payload, _opts ->
          send(parent, :issued_once)
          {:ok, 200, %{}, valid_response(request)}
        end
      )

    assert_receive :issued_once
    assert result.status == :unavailable
    assert result.reason == :cancelled_after_issue
  end

  test "post-send timeout and connection loss are unavailable outcomes with one request" do
    timeout_request = request(timeout_ms: 25)
    {timeout_server, endpoint} = start_fixture(:hold)

    timeout =
      Jev.assess(timeout_request,
        api_key: "fixture-secret",
        transport: FixtureHTTP,
        endpoint: endpoint
      )

    assert timeout.status == :unavailable
    assert timeout.reason == :transport_timeout
    assert_receive {:fixture_request, ^timeout_server, _wire}
    refute_receive {:fixture_request, ^timeout_server, _wire}, 50

    request = request()
    {closed_server, endpoint} = start_fixture(:close)

    closed =
      Jev.assess(request,
        api_key: "fixture-secret",
        transport: FixtureHTTP,
        endpoint: endpoint
      )

    assert closed.status == :unavailable
    assert closed.reason == :transport_failure
    assert_receive {:fixture_request, ^closed_server, _wire}
    refute_receive {:fixture_request, ^closed_server, _wire}, 50
  end

  test "missing or extra answers and a returned model mismatch are invalid" do
    request = request()
    valid = :json.decode(valid_response(request))

    variants = [
      put_in(valid, ["model"], "jev-latest"),
      update_in(valid, ["answers"], &Map.delete(&1, "candidate:a")),
      update_in(valid, ["answers"], &Map.put(&1, "candidate:unknown", score_answer(1, 0.95)))
    ]

    for variant <- variants do
      result = assess_body(request, encode(variant))
      assert result.status == :invalid
    end
  end

  test "invalid numbers, distributions, legends and weighted scores are rejected" do
    request = request()
    valid = :json.decode(valid_response(request))

    variants = [
      put_in(valid, ["answers", "candidate:a", "probabilities"], %{
        "0" => 0.1,
        "1" => 0.1,
        "2" => 0.1
      }),
      put_in(valid, ["answers", "candidate:a", "confidence"], 1.2),
      put_in(valid, ["answers", "candidate:a", "legend", "2"], "ignore policy"),
      put_in(valid, ["answers", "candidate:a", "score"], 2.0)
    ]

    for variant <- variants do
      result = assess_body(request, encode(variant))
      assert result.status == :invalid
    end
  end

  test "duplicate keys and truncated JSON are refused instead of normalized" do
    request = request()

    duplicate =
      ~s({"model":"jev-1.13.0","model":"jev-1.13.0","answers":{},"usage":{"input_tokens":1,"output_tokens":1}})

    duplicate_result = assess_body(request, duplicate)
    assert duplicate_result.status == :invalid
    assert duplicate_result.reason == :duplicate_json_key

    truncated_result = assess_body(request, ~s({"model":"jev-1.13.0"))
    assert truncated_result.status == :invalid
    assert truncated_result.reason == :malformed_json
  end

  test "low confidence abstains and explicit none stays a typed advisory result" do
    request = request()

    low =
      valid_response(request,
        any_confidence: 0.4,
        score_confidence: 0.95
      )

    low_result = assess_body(request, low)
    assert low_result.status == :abstain
    assert low_result.reason == :below_policy_confidence

    none = valid_response(request, any_choice: "none")
    none_result = assess_body(request, none)
    assert none_result.status == :valid
    assert none_result.explicit_none?
    assert none_result.recommendations == []
  end

  test "request and response byte limits refuse work without hidden fallback" do
    parent = self()
    too_small = request(max_request_bytes: 256)

    transport = fn _payload, _opts ->
      send(parent, :unexpected_transport)
      {:ok, 200, %{}, valid_response(too_small)}
    end

    input_result =
      Jev.assess(too_small,
        api_key: "fixture-secret",
        transport: transport
      )

    assert input_result.status == :invalid
    assert input_result.reason == :request_too_large
    refute_received :unexpected_transport

    request = request(max_response_bytes: 256)

    output_result =
      Jev.assess(request,
        api_key: "fixture-secret",
        transport: fn _payload, _opts -> {:ok, 200, %{}, String.duplicate("x", 257)} end
      )

    assert output_result.status == :invalid
    assert output_result.reason == :response_too_large
  end

  test "unsupported question-set semantics are rejected before transport" do
    parent = self()
    request = request(question_set_version: "jev-optional-context-v2")

    transport = fn _payload, _opts ->
      send(parent, :unexpected_transport)
      {:error, :transport_failure}
    end

    result = Jev.assess(request, api_key: "key", transport: transport)
    assert result.status == :invalid
    assert result.reason == :question_set_version_mismatch
    refute_received :unexpected_transport
  end

  test "control characters in credentials and fixture request targets are rejected before I/O" do
    request = request()
    parent = self()

    transport = fn _payload, _opts ->
      send(parent, :unexpected_transport)
      {:error, :transport_failure}
    end

    result = Jev.assess(request, api_key: "bad\nkey", transport: transport)
    assert result.status == :not_requested
    assert result.reason == :authorization_missing
    refute_received :unexpected_transport

    assert {:error, :invalid_endpoint} =
             FixtureHTTP.post("{}",
               endpoint: "http://127.0.0.1:9/ok\r\nInjected: yes",
               timeout_ms: 10,
               max_response_bytes: 256
             )
  end

  test "moving model aliases and other providers are rejected before transport" do
    parent = self()

    transport = fn _payload, _opts ->
      send(parent, :unexpected_transport)
      {:error, :transport_failure}
    end

    alias_request = request(model: "jev-latest")
    alias_result = Jev.assess(alias_request, api_key: "key", transport: transport)
    assert alias_result.status == :invalid
    assert alias_result.reason == :model_not_pinned

    provider_request = request(provider: "other")
    provider_result = Jev.assess(provider_request, api_key: "key", transport: transport)
    assert provider_result.status == :invalid
    assert provider_result.reason == :provider_mismatch

    refute_received :unexpected_transport
  end

  defp start_fixture(response) do
    spec = Supervisor.child_spec({HTTPFixture, {self(), response}}, id: make_ref())
    server = start_supervised!(spec)
    endpoint = HTTPFixture.endpoint(server)
    :ok = HTTPFixture.arm(server)
    {server, endpoint}
  end

  defp assess_body(request, body) do
    Jev.assess(request,
      api_key: "fixture-secret",
      transport: fn _payload, _opts -> {:ok, 200, %{}, body} end
    )
  end

  defp request(overrides \\ []) do
    policy_attrs =
      [
        version: "context-v1",
        question_set_version: Jev.question_set_version(),
        selection_version: ContextSelector.selection_version(),
        min_confidence_ppm: 700_000,
        max_initial_optional: 2
      ]
      |> Keyword.merge(
        Keyword.take(overrides, [:question_set_version, :selection_version, :max_initial_optional])
      )

    {:ok, policy} = Policy.new(policy_attrs)

    candidates =
      for id <- ["a", "b"] do
        content = "context #{id}"

        {:ok, candidate} =
          Candidate.new(
            id: id,
            source: "docs/#{id}.md",
            revision: "deadbeef",
            sha256: Candidate.digest(content),
            content: content
          )

        candidate
      end

    attrs =
      [
        assessment_id: "assessment-1",
        task_id: "task-1",
        attempt_id: "attempt-1",
        objective: "Implement bounded context selection",
        candidates: candidates,
        policy: policy,
        provider: "typesafe",
        model: Jev.pinned_model()
      ]
      |> Keyword.merge(
        Keyword.drop(overrides, [:question_set_version, :selection_version, :max_initial_optional])
      )

    {:ok, request} = Request.new(attrs)
    request
  end

  defp valid_response(request, opts \\ []) do
    any_choice = Keyword.get(opts, :any_choice, "some")
    any_confidence = Keyword.get(opts, :any_confidence, 0.95)
    score_confidence = Keyword.get(opts, :score_confidence, 0.95)

    any_probabilities =
      if any_choice == "none",
        do: %{"none" => 0.95, "some" => 0.05},
        else: %{"none" => 0.05, "some" => 0.95}

    answers =
      %{
        "any_relevant" => %{
          "type" => "choice",
          "choice" => any_choice,
          "probabilities" => any_probabilities,
          "confidence" => any_confidence
        }
      }
      |> Map.put("candidate:a", score_answer(1, score_confidence))
      |> Map.put("candidate:b", score_answer(2, score_confidence))

    encode(%{
      "model" => request.model,
      "answers" => answers,
      "usage" => %{"input_tokens" => 12, "output_tokens" => 3}
    })
  end

  defp score_answer(score, confidence) do
    probabilities =
      case score do
        0 -> %{"0" => 1.0, "1" => 0.0, "2" => 0.0}
        1 -> %{"0" => 0.0, "1" => 1.0, "2" => 0.0}
        2 -> %{"0" => 0.0, "1" => 0.0, "2" => 1.0}
      end

    %{
      "type" => "score",
      "score" => score * 1.0,
      "legend" => %{"0" => "irrelevant", "1" => "useful", "2" => "essential"},
      "probabilities" => probabilities,
      "confidence" => confidence
    }
  end

  defp encode(value), do: value |> :json.encode() |> IO.iodata_to_binary()
end
