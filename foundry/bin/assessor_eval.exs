alias PramanaFoundry.Assessor.Evaluator
alias PramanaFoundry.Assessor.UniqueJSON

max_input_bytes = 4_194_304

# `mix run` passes a literal `--` through to argv, so the documented `-- INPUT.json` form
# failed with the usage message (found by the 2026-09-22 bin script health check).
case System.argv() -- ["--"] do
  [input_path] ->
    with {:ok, bytes} <-
           File.open(input_path, [:read, :binary], fn io ->
             IO.binread(io, max_input_bytes + 1)
           end),
         true <- is_binary(bytes) and byte_size(bytes) <= max_input_bytes,
         {:ok, input} <- UniqueJSON.decode(bytes),
         %{"schema_version" => 2, "cases" => cases, "top_k" => top_k} <- input,
         true <- Enum.sort(Map.keys(input)) == ["cases", "schema_version", "top_k"],
         {:ok, result} <- Evaluator.compare(cases, top_k) do
      IO.binwrite(IO.iodata_to_binary([:json.encode(result), "\n"]))
    else
      _ ->
        IO.puts(:stderr, "invalid assessor evaluation input")
        System.halt(2)
    end

  _ ->
    IO.puts(:stderr, "usage: mix run bin/assessor_eval.exs -- INPUT.json")
    System.halt(2)
end
