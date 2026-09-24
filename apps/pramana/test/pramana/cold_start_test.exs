defmodule Pramana.ColdStartTest do
  use ExUnit.Case, async: true

  test "mode and evaluation type dispatch work in a fresh BEAM before retrievers load" do
    ebin = :code.which(Pramana.Retrieval) |> to_string() |> Path.dirname()

    script = """
    false = :code.is_loaded(Pramana.Retrieval.Lexical)
    for name <- ~w(phrase ngram terms auto hybrid semantic) do
      ^name = Pramana.Retrieval.mode(name) |> Atom.to_string()
    end
    for name <- ~w(retrieval topical quote_verify quote_reject provenance absence rendering gloss) do
      ^name = Pramana.Evals.Case.type_atom(name) |> Atom.to_string()
    end
    false = :code.is_loaded(Pramana.Retrieval.Lexical)
    IO.puts("cold dispatch passed")
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-pa", ebin, "-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "cold dispatch passed"
  end
end
