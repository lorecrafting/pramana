defmodule Architecture.BoundariesTest do
  @moduledoc """
  The two structural boundaries in `docs/CHECKS.md` §2, checked mechanically.

  §2 is the **architecture review**: re-read `CLAUDE.md`'s invariants and confirm the code
  still honours them. It is owed by a person at every phase gate, `mix pramana.gate` says
  so in its closing summary, and most of it genuinely needs judgement — *has this codebase
  quietly stopped being the thing it was designed to be* is not a grep.

  **But two of its five audits were already being performed as greps**, and the 2026-08-28
  review in `docs/HISTORY.md` records them as exactly that: zero `Repo.` in `pramana_web`,
  and four Python files importing nothing but stdlib and tensor libraries. A check a person
  performs by running a grep at a phase gate is a check that runs **once a phase**, on the
  honour system, long after the commit that broke it. Here it runs on every push, in CI,
  and names the file.

  This does **not** replace §2 and nothing here should be read as doing so. The three
  audits it cannot do are listed in `unmechanised/0` below, and they are the ones that
  needed judgement in the first place.

  ## Leeway is the point, and it is deliberate

  These boundaries will move. `priv/embed` may need another tensor library; the web app may
  one day have a reason nobody has thought of yet. So each rule carries an **allowlist with
  a reason**, and widening it is one line in a diff somebody reviews.

  What that buys is the distinction between *evolution* and *drift*: a boundary crossed on
  purpose is an edit to this file, and a boundary crossed by accident is a red test naming
  the line. A rule with no escape hatch gets deleted the first time it is inconvenient,
  which is strictly worse than a rule with a visible list of exceptions — the exceptions
  are then the review.
  """
  use ExUnit.Case, async: true

  # `__DIR__`-relative and not `:project_root`, for the reason `Docs.RoutingTest` gives:
  # that key is global application state and other async tests repoint it at temp
  # directories, which would make these assertions pass against an empty tree.
  @root Path.expand("../../../..", __DIR__)

  describe "the web app is transport and the domain app owns the data" do
    # `CLAUDE.md` layout: "`pramana` is pure domain logic with no web dependency", and the
    # inverse is what keeps it true. It has drifted once already — via an MCP resource that
    # built its own aggregation — which is why §2 names this one specifically.
    #
    # Empty on purpose. If this ever needs an entry, the entry is the argument.
    @db_allowed %{}

    test "nothing in apps/pramana_web reads the database directly" do
      offenders =
        Path.wildcard(Path.join(@root, "apps/pramana_web/lib/**/*.ex"))
        |> Enum.flat_map(&db_access_in/1)
        |> Enum.reject(fn {file, _line, _match} -> Map.has_key?(@db_allowed, file) end)

      assert offenders == [],
             """
             The web app is transport; the domain app owns the data. These read the
             database directly:

             #{Enum.map_join(offenders, "\n", fn {file, line, match} -> "    #{file}:#{line}  #{match}" end)}

             Call a function on `Pramana.*` instead. A query here is a second place that
             knows the schema, and the reader and the MCP surface are supposed to read the
             SAME domain functions — that is what makes the reader a renderer.

             If this one is genuinely right, add it to `@db_allowed` with the reason.
             """
    end
  end

  describe "the Python sidecar does tensor math and nothing else" do
    # `CLAUDE.md`: "Do not let the Python sidecar grow. It does tensor math." Every other
    # decision — orchestration, retries, normalization, provenance, retrieval — is Elixir,
    # and the sidecar stays replaceable only while its interface stays `{texts, mode} ->
    # vectors`.
    #
    # The vocabulary is the tell. A sidecar that knows what a URN is has stopped being a
    # tensor service. This is the exact set the 2026-08-28 review in `docs/HISTORY.md`
    # grepped for, plus `bake_id`; a wider list invented here would be a wider list nobody
    # had ever run.
    #
    # MATCHED ON WORD BOUNDARIES, and the first version was not. `urn` as a substring is
    # inside every `return` in the file, which is the "four different greps that matched a
    # substring" already on `docs/ROADMAP.md`'s risk list — reproduced while writing the
    # check meant to catch drift.
    @domain_words ~w(urn provenance citation witness canon bake_id)

    # Standard library plus the tensor stack. Adding to this list is how the sidecar is
    # allowed to grow in the direction it is supposed to grow in.
    @allowed_imports ~w(
      argparse hashlib json os random sys time
      torch transformers peft modal numpy
    )

    defp sidecar_files do
      Path.join(@root, "priv/embed/*.py") |> Path.wildcard()
    end

    test "there are sidecar files to check, so a rename cannot make this pass vacuously" do
      # A structural test whose subject has moved passes by finding nothing, which reads as
      # green forever. Rule 8's shape, applied to a test rather than to a patch.
      assert sidecar_files() != [], "no .py files under priv/embed — has the sidecar moved?"
    end

    test "no domain vocabulary leaks into priv/embed" do
      offenders =
        for file <- sidecar_files(),
            {line, number} <- code_lines(file),
            word <- @domain_words,
            Regex.match?(~r/\b#{word}\b/i, line),
            do: {relative(file), number, word, String.trim(line)}

      assert offenders == [],
             """
             Domain vocabulary in the Python sidecar. It does tensor math; a sidecar that
             knows what a URN or a witness is has stopped being one, and `CLAUDE.md` is
             explicit that this is a signal the logic is in the wrong place:

             #{Enum.map_join(offenders, "\n", fn {file, line, _word, text} -> "    #{file}:#{line}  #{text}" end)}
             """
    end

    test "its imports stay inside the tensor stack" do
      offenders =
        for file <- sidecar_files(),
            {line, number} <- numbered_lines(file),
            module = imported_module(line),
            module != nil,
            module not in @allowed_imports,
            do: {relative(file), number, module}

      assert offenders == [],
             """
             The sidecar imported something outside the standard library and the tensor
             stack:

             #{Enum.map_join(offenders, "\n", fn {file, line, mod} -> "    #{file}:#{line}  #{mod}" end)}

             If it belongs — another tensor library, say — add it to `@allowed_imports`.
             If it is a database driver, an HTTP client or a parser, the work belongs in
             Elixir.
             """
    end
  end

  describe "the lockfile and the bake id move together" do
    # `Pramana.Bake.bake_id/1` is a hash of `sources.lock.json`, so ANY task that writes
    # the lockfile changes it by definition — and a bake row that no longer describes its
    # inputs stamps every API response with an id for a corpus that does not exist.
    #
    # `mix pramana.gate` catches the divergence, which means each such task leaves the gate
    # red the next time it runs. Six of eleven did, until 2026-09-02. The fix was one line
    # each; this is what stops the seventh.
    #
    # It cannot live in `Lockfile` itself — a file-manipulation module writing a database
    # row is a layering violation, and it would break in any context without a repo.
    @bake_exempt %{}

    test "every task that writes the lockfile also records a bake" do
      offenders =
        Path.wildcard(Path.join(@root, "apps/*/lib/mix/tasks/*.ex"))
        |> Enum.filter(fn file ->
          source = elixir_code(file)

          String.contains?(source, "Lockfile.put_source") or
            String.contains?(source, "Lockfile.merge_source")
        end)
        # CODE, NOT COMMENTS — and the first version of this check did not say so, so it
        # passed with the call deleted because the comment above the call still contained
        # the words `Bake.record`. "Four different greps that matched a substring" is
        # already on `docs/ROADMAP.md`'s risk list; this was the fifth, inside the test
        # written to make the rule stick.
        |> Enum.reject(&String.contains?(elixir_code(&1), "Bake.record("))
        |> Enum.map(&relative/1)
        |> Enum.reject(&Map.has_key?(@bake_exempt, &1))

      assert offenders == [],
             """
             These tasks write `sources.lock.json` and never re-record the bake, so each
             leaves `mix pramana.gate` failing on `:bake_id_diverged` the next time it runs:

             #{Enum.map_join(offenders, "\n", &"    #{&1}")}

             `Bake.record/1` writes a row; it does not re-bake. If a task genuinely should
             not — it writes a lockfile for something that is not an input to any bake —
             add it to `@bake_exempt` with the reason.
             """
    end
  end

  @doc """
  What `docs/CHECKS.md` §2 asks for that this file cannot answer.

  Kept as a function rather than a comment so it is printed by the test below: a green
  suite must not be mistaken for a completed architecture review, and the cheapest way to
  prevent that is for the mechanical half to name the half it is not doing.
  """
  def unmechanised do
    [
      "Can any tool return text without urn + offsets + sha256? Shape, not substring.",
      "Is any generated translation reachable as a top-level URN? Invariant #8, and the " <>
        "guard tests cover the resolver, not every future path to it.",
      "Is the bake still reproducible from sources.lock.json alone?",
      "And the question none of these is: has this codebase quietly stopped being the " <>
        "thing it was designed to be?"
    ]
  end

  test "this file says which audits it does not perform" do
    assert length(unmechanised()) == 4
  end

  defp db_access_in(file) do
    for {line, number} <- numbered_lines(file),
        match = db_access(line),
        match != nil,
        do: {relative(file), number, match}
  end

  # Narrow on purpose. `Repo.` and `import Ecto.Query` are unambiguous; a bare `from(`
  # is not — `Date.from_iso8601`, a docstring, a variable — and a structural test that
  # cries wolf is one somebody deletes.
  defp db_access(line) do
    cond do
      String.contains?(line, "import Ecto.Query") -> "import Ecto.Query"
      Regex.match?(~r/\bRepo\.\w/, line) -> "Repo."
      Regex.match?(~r/\bfrom\(\w+ in /, line) -> "from(x in ...)"
      true -> nil
    end
  end

  # Both halves of the statement are required, and that is not pedantry: the first
  # version matched `^\s*(?:import|from)\s+(\w+)`, so any DOCSTRING line beginning "from
  # its inputs is not a bake" was reported as an import of a module called `its`. A check
  # that fires on English prose gets satisfied by rewording the prose, which leaves the
  # boundary unguarded and the docs worse. Rule 8's shape again — verify the check fails
  # for the reason you think it does.
  defp imported_module(line) do
    from = Regex.run(~r/^\s*from\s+([a-zA-Z_]\w*)[\w.]*\s+import\s/, line)
    plain = Regex.run(~r/^\s*import\s+([a-zA-Z_]\w*)[\w.]*\s*(?:,|\s+as\s|$)/, line)

    case from || plain do
      [_, module] -> module
      _ -> nil
    end
  end

  defp numbered_lines(file) do
    file |> File.read!() |> String.split("\n") |> Enum.with_index(1)
  end

  # CODE, not prose. `modal_train_tibetan.py` carries a docstring explaining that a
  # fine-tuned embedder changes what is found and never what is cited — which is exactly
  # the right comment to have written, and the first version of this test forbade it.
  # A check that punishes someone for documenting the boundary is a check that teaches
  # people to stop documenting the boundary.
  defp code_lines(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, fn {line, number}, {kept, in_docstring?} ->
      quotes =
        line |> String.graphemes() |> Enum.chunk_every(3, 1) |> Enum.count(&(&1 == ~w(" " ")))

      now_inside? = if rem(quotes, 2) == 1, do: not in_docstring?, else: in_docstring?

      code = line |> String.split("#", parts: 2) |> hd()

      if in_docstring? or now_inside? or String.trim(code) == "" do
        {kept, now_inside?}
      else
        {[{code, number} | kept], now_inside?}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp relative(file), do: Path.relative_to(file, @root)

  # Whole-line comments dropped. Enough for this: every comment that mentions a function
  # by name in this codebase is on its own line, and a heuristic that also tried to strip
  # inline `#` would have to know which ones are inside strings and sigils.
  defp elixir_code(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.reject(&(&1 |> String.trim() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end
end
