# Corpus integration tests need `raw/`, which is gitignored — we publish the pipeline,
# not the corpus. Exclude them when it is absent so a skip is REPORTED as an exclusion
# rather than silently passing. A test that quietly asserts nothing is worse than no
# test: it reads as green forever.
corpus_available? =
  [Application.get_env(:pramana, :project_root) || File.cwd!(), "raw", "cbeta"]
  |> Path.join()
  |> File.dir?()

unless corpus_available? do
  IO.puts("""
  \n[test] raw/cbeta not found — excluding :corpus tests.
         Run `mix pramana.acquire --source cbeta` to enable them.
  """)
end

ExUnit.start(exclude: if(corpus_available?, do: [], else: [:corpus]))
Ecto.Adapters.SQL.Sandbox.mode(Pramana.Repo, :manual)
