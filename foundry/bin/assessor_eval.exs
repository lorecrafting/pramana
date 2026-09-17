alias PramanaFoundry.Assessor.Evaluator
alias PramanaFoundry.Assessor.UniqueJSON

case System.argv() do
  [input_path] ->
    with {:ok, bytes} <- File.read(input_path),
         {:ok, input} <- UniqueJSON.decode(bytes),
         %{"cases" => cases, "top_k" => top_k} <- input,
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
