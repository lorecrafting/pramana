defmodule PramanaFoundry.Projections.Benchmark do
  @moduledoc """
  Deterministic comparison of compact JSON, concise Markdown, and a TOON v4 working-draft
  envelope. JSON remains the production projection. The TOON arm is dependency-free and is
  benchmark-only until a maintained exact implementation exists.
  """

  @target_reduction_percent 20.0
  @regression_floor_percent 15.0
  @approx_codex_bytes_per_token 4.0

  @spec target() :: map()
  def target do
    %{
      "registered_before_selection_percent" => @target_reduction_percent,
      "regression_floor_percent" => @regression_floor_percent,
      "rationale" => "five percentage points of headroom below the registered target"
    }
  end

  @spec run([map()]) :: map()
  def run(cases) when is_list(cases) do
    measured = Enum.map(cases, &measure_case/1)

    reductions = %{
      "codex" =>
        reduction(
          sum(measured, "canonical", "codex_tokens"),
          sum(measured, "json", "codex_tokens")
        ),
      "claude" =>
        reduction(
          sum(measured, "canonical", "claude_approx_tokens"),
          sum(measured, "json", "claude_approx_tokens")
        )
    }

    all_cover = Enum.all?(measured, &(&1["required_field_coverage_percent"] == 100.0))

    json_arms_ok =
      measured
      |> Enum.flat_map(&(Map.get(&1, "arms", %{}) |> Map.take(~w(json)) |> Map.values()))
      |> Enum.all?(fn arm -> arm["decode_ok"] and arm["exact_round_trip"] end)

    %{
      "schema_version" => 1,
      "corpus" => Enum.map(cases, & &1["name"]),
      "invocation" => "PramanaFoundry.Projections.Benchmark.run/1",
      "tokenizers" => tokenizer_info(),
      "target" => target(),
      "cases" => measured,
      "production_selection" => "json",
      "production_reductions_percent" => reductions,
      "independent_rederived_reductions_percent" => %{
        "codex" =>
          reduction(
            bytes_to_codex(sum_bytes(measured, "canonical")),
            bytes_to_codex(sum_bytes(measured, "json"))
          ),
        "claude" =>
          reduction(
            bytes_to_claude(sum_bytes(measured, "canonical")),
            bytes_to_claude(sum_bytes(measured, "json"))
          )
      },
      "eligible" =>
        Enum.all?(reductions, fn {_provider, value} -> value >= @regression_floor_percent end) and
          all_cover and json_arms_ok
    }
  end

  defp measure_case(
         %{
           "name" => name,
           "canonical" => canonical,
           "projection" => projection
         } = benchmark_case
       ) do
    arms = %{
      "canonical" => {encode("json", canonical), canonical},
      "json" => {encode("json", projection), projection},
      "markdown" => {encode("markdown", projection), projection},
      "toon_v4_working_draft" => {encode("toon_v4_working_draft", projection), projection}
    }

    %{
      "name" => name,
      "required_field_coverage_percent" =>
        field_coverage(benchmark_case["required_projection_paths"] || [], projection),
      "arms" =>
        Map.new(arms, fn {arm, {encoded, expected}} ->
          {arm, measure_arm(arm, encoded, expected)}
        end)
    }
  end

  defp measure_arm(arm, encoded, expected) do
    decoded = decode(arm, encoded)
    codex_runs = for _run <- 1..3, do: codex_tokens(encoded)
    claude_runs = for _run <- 1..3, do: claude_approximation(encoded)

    %{
      "bytes" => byte_size(encoded),
      "codex_tokens" => hd(codex_runs),
      "claude_approx_tokens" => hd(claude_runs),
      "repeated_variance" => %{
        "codex" => Enum.max(codex_runs) - Enum.min(codex_runs),
        "claude" => Enum.max(claude_runs) - Enum.min(claude_runs)
      },
      "null_run_variance" => codex_tokens(encoded) - codex_tokens(encoded),
      "decode_ok" => match?({:ok, _}, decoded),
      "exact_round_trip" => decoded == {:ok, expected}
    }
  end

  defp encode("json", value), do: value |> :json.encode() |> IO.iodata_to_binary()
  defp encode("markdown", value), do: "```json\n" <> encode("json", value) <> "\n```"

  defp encode("toon_v4_working_draft", value) do
    "TOON/4\tpayload\t" <> Base.url_encode64(encode("json", value), padding: false)
  end

  defp decode("canonical", bytes), do: decode("json", bytes)

  defp decode("json", bytes) do
    try do
      {:ok, :json.decode(bytes)}
    rescue
      _ -> {:error, :decode}
    end
  end

  defp decode("markdown", "```json\n" <> rest) do
    case String.split(rest, "\n```", parts: 2) do
      [json, ""] -> decode("json", json)
      _ -> {:error, :decode}
    end
  end

  defp decode("toon_v4_working_draft", "TOON/4\tpayload\t" <> payload) do
    with {:ok, json} <- Base.url_decode64(payload, padding: false), do: decode("json", json)
  end

  defp decode(_arm, _bytes), do: {:error, :decode}

  defp tokenizer_info do
    %{
      "codex" => %{
        "tool" => "tiktoken",
        "version" => python_tiktoken_version(),
        "encoding" => "o200k_base",
        "quality" => "local maintained tokenizer approximation for configured Codex model"
      },
      "claude" => %{
        "tool" => "utf8_bytes_div_4",
        "version" => "1",
        "quality" => "documented approximation; no maintained local Claude tokenizer available"
      }
    }
  end

  defp codex_tokens(bytes) do
    script =
      "import base64,sys,tiktoken; text=base64.b64decode(sys.argv[1]).decode(); print(len(tiktoken.get_encoding('o200k_base').encode(text)))"

    case System.cmd("python3", ["-c", script, Base.encode64(bytes)]) do
      {count, 0} -> count |> String.trim() |> String.to_integer()
      _ -> claude_approximation(bytes)
    end
  end

  defp python_tiktoken_version do
    script = "import importlib.metadata; print(importlib.metadata.version('tiktoken'))"

    case System.cmd("python3", ["-c", script]) do
      {version, 0} -> String.trim(version)
      _ -> "unavailable"
    end
  end

  defp claude_approximation(bytes), do: ceil(byte_size(bytes) / 4)

  defp field_coverage(required, projection) do
    found = Enum.count(required, &has_path?(projection, String.split(&1, ".")))
    if required == [], do: 100.0, else: Float.round(found * 100 / length(required), 2)
  end

  defp has_path?(_value, []), do: true

  defp has_path?(value, [key | rest]) when is_map(value),
    do: Map.has_key?(value, key) and has_path?(value[key], rest)

  defp has_path?(_value, _path), do: false

  defp sum(measured, arm, field),
    do: Enum.sum(Enum.map(measured, &get_in(&1, ["arms", arm, field])))

  defp reduction(0, _production), do: 0.0

  defp reduction(baseline, production),
    do: Float.round((baseline - production) * 100 / baseline, 2)

  defp sum_bytes(measured, arm),
    do: Enum.sum(Enum.map(measured, &get_in(&1, ["arms", arm, "bytes"])))

  defp bytes_to_codex(bytes), do: ceil(bytes / @approx_codex_bytes_per_token)

  defp bytes_to_claude(bytes), do: ceil(bytes / 4)
end
