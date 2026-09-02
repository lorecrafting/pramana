defmodule Pramana.Report do
  @moduledoc """
  Verifies a **sourced report**, not just the quotations inside it.

  `Pramana.Guard` re-resolves every URN and byte-compares the quoted span, which makes a
  fabricated passage impossible to pass off. It says nothing about the claims that actually
  carry a report:

  | claim | guard | what checks it |
  |---|---|---|
  | "T0262 says X" | ✅ byte-compare | `Guard.check_output/1` |
  | "X appears 36,775 times across 1,904 works" | ✗ | re-run the survey and compare |
  | "no Japanese-composed text uses X" | ✗ | re-run the search and confirm it is still empty |

  The second and third are where a report goes wrong in the way that matters, because a
  frequency claim generalised from twenty ranked hits reads exactly like one counted over
  twelve million segments.

  ## This is not an agent, and that is the design

  `CLAUDE.md` makes the model a swappable reader and invariant #7 keeps the MCP surface
  read-only. An agent living inside the server would contradict both. What ships instead is
  the thing that makes **any** agent's report checkable — the same move the citation guard
  already made one level down.

  ## The format: a fenced block beside the claim

  A report is ordinary markdown. Where a claim rests on a retrieval rather than on a quote,
  it carries the call that produced it:

      ```pramana-replay
      {"tool": "survey_corpus",
       "arguments": {"query": "一切眾生"},
       "bake_id": "b143d7f3…",
       "assert": {"total": 36775, "works": 1904}}
      ```

  Every tool response already emits `replay: {tool, arguments}` beside `bake_id`, so writing
  one of these is copying a field rather than composing anything. `assert` names response
  keys and the values the report claims for them; dotted paths reach into nested maps.

  ## Three refusals, and each is the point

  1. **A replay against a different `bake_id` is `:unverifiable`, never `:failed`.** The
     corpus changed; the claim may well have been true when it was made. Reporting that as a
     falsehood would teach people to ignore the checker, which is exactly how `integrity`
     lost its audience while crying wolf over 1,228 X texts.
  2. **A figure with no quote and no replay is reported as unsourced.** Counting only what
     it can check, and publishing a pass rate over that denominator, is rule 44 in the one
     place it would be most embarrassing. This one is a **heuristic** — it looks for numerals
     in a paragraph carrying no citation — so it is a warning list, never a verdict.
  3. **It does not judge whether a citation supports its claim.** `Guard` draws that line
     already and it holds here: mechanical warrant, never interpretation.

  ## Why not a panel of skeptic models

  The verification pattern in circulation is N independent models voting on whether a
  finding survives. Invariant #5 puts that behind anything deterministic — and here there is
  nothing left over: re-running a survey is arithmetic over the bake, and a majority vote is
  strictly weaker than a recount. Adversarial verification earns its place on questions with
  no deterministic check, such as whether a commentary alignment is real. It has no place on
  *how often*.
  """

  alias Pramana.Bake
  alias Pramana.Citation
  alias Pramana.Guard

  @typedoc """
  Executes one replay record. Supplied by the caller because the tools it names live on the
  MCP surface in `pramana_web`, and this application has no web dependency.
  """
  @type executor :: (String.t(), map() -> {:ok, map()} | {:error, term()})

  @type replay :: %{
          tool: String.t(),
          arguments: map(),
          bake_id: String.t() | nil,
          assert: map(),
          line: pos_integer()
        }

  @fence ~r/```pramana-replay\s*\n(.*?)\n```/s

  # Every replay is a query against the corpus, and a report is untrusted input.
  @max_replays 25

  @doc """
  Pulls every replay record out of a report, with the line each was found on.

  A malformed block is returned as an `:error` entry rather than skipped: a record nobody can
  parse is a claim nobody checked, and silently dropping it would let a report look fully
  verified because its evidence was unreadable.
  """
  @spec parse(String.t()) :: %{
          replays: [replay()],
          malformed: [%{line: pos_integer(), reason: term()}]
        }
  def parse(markdown) when is_binary(markdown) do
    @fence
    |> Regex.scan(markdown, return: :index)
    |> Enum.map(fn [{whole_start, _}, {body_start, body_len}] ->
      {line_of(markdown, whole_start), binary_part(markdown, body_start, body_len)}
    end)
    |> Enum.reduce(%{replays: [], malformed: []}, fn {line, json}, acc ->
      case decode(json, line) do
        {:ok, replay} -> %{acc | replays: [replay | acc.replays]}
        {:error, reason} -> %{acc | malformed: [%{line: line, reason: reason} | acc.malformed]}
      end
    end)
    |> then(&%{replays: Enum.reverse(&1.replays), malformed: Enum.reverse(&1.malformed)})
  end

  defp decode(json, line) do
    with {:ok, map} <- Jason.decode(json),
         %{"tool" => tool, "arguments" => args} when is_binary(tool) and is_map(args) <- map do
      {:ok,
       %{
         tool: tool,
         arguments: args,
         bake_id: map["bake_id"],
         assert: map["assert"] || %{},
         line: line
       }}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      _ -> {:error, :missing_tool_or_arguments}
    end
  end

  defp line_of(text, byte_offset) do
    text |> binary_part(0, byte_offset) |> String.split("\n") |> length()
  end

  @doc """
  Verifies a report: quotations through `Guard`, replay records by re-execution.

  `executor` receives `{tool, arguments}` and returns the tool's payload. Pass
  `bake_id:` to override what the replays are compared against; it defaults to the
  current bake.
  """
  @spec verify(String.t(), keyword()) :: map()
  def verify(markdown, opts \\ []) when is_binary(markdown) do
    executor = Keyword.fetch!(opts, :executor)
    current_bake = Keyword.get(opts, :bake_id, Bake.current_id())

    %{replays: all_replays, malformed: malformed} = parse(markdown)
    # A REPORT IS UNTRUSTED INPUT AND EVERY REPLAY IS A QUERY. A document carrying ten
    # thousand fenced blocks would otherwise turn a verification request into a denial of
    # service against the corpus. Excess records are reported as skipped rather than
    # silently dropped, and their presence prevents `ok?` — a report whose evidence was not
    # all examined has not been verified.
    max = Keyword.get(opts, :max_replays, @max_replays)
    {replays, skipped} = Enum.split(all_replays, max)

    # DIAGNOSED, not merely counted. A report telling an author "one citation failed" sends
    # them looking for a fabrication; telling them the quotation runs into the next line
    # sends them to fix a range. Same finding, opposite afternoon.
    # FOREIGN CITATIONS FIRST, or most of them are not checked at all. `Guard` scans for
    # `pramana:` URNs, and a report citing the Taishō the way an article cites it —
    # `T. 262, 6a23` — contains none. The guard then reports zero citations checked and a
    # reader sees a document with nothing wrong with it. An absence of findings and a
    # clean bill of health must not render the same.
    #
    # Done HERE and not inside `Guard.check_output/1` on purpose: that function is also
    # the MCP `verify_citation` tool and the path 601 eval cases run through, and this
    # needs to change what a REPORT check sees without touching either.
    {resolved, foreign} = Citation.rewrite(markdown)

    citations =
      resolved
      |> Guard.check_output()
      |> Map.update!(:findings, fn findings -> Enum.map(findings, &Guard.diagnose/1) end)

    results = Enum.map(replays, &check_replay(&1, executor, current_bake))

    %{
      citations: citations,
      replays: results,
      # What was recognised in somebody else's scheme, and what could not be placed. A
      # citation this corpus cannot resolve is reported rather than dropped: it is
      # precisely what a reader needs told.
      foreign: foreign,
      malformed: malformed,
      skipped: length(skipped),
      # From the ORIGINAL text: rewriting a citation does not change which paragraphs
      # carry a number with nothing behind it, and scanning the rewritten copy would
      # report URNs this module had just written into it.
      unsourced_figures: unsourced_figures(markdown),
      bake_id: current_bake,
      # `ok?` requires the citations to hold AND every replay to verify. An `:unverifiable`
      # replay does NOT pass: the report is not shown to be wrong, and it is also not shown
      # to be right, which is the whole distinction this module exists to preserve.
      ok?:
        citations.ok? and malformed == [] and skipped == [] and
          Enum.all?(results, &(&1.status == :verified))
    }
  end

  defp check_replay(replay, executor, current_bake) do
    base = Map.take(replay, [:tool, :arguments, :bake_id, :line])

    if replay.bake_id && current_bake && replay.bake_id != current_bake do
      Map.merge(base, %{
        status: :unverifiable,
        detail:
          "recorded against bake #{short(replay.bake_id)}; this corpus is " <>
            "#{short(current_bake)}. The claim is not refuted — it cannot be re-run here."
      })
    else
      execute_and_compare(base, replay, executor)
    end
  end

  defp execute_and_compare(base, replay, executor) do
    case executor.(replay.tool, replay.arguments) do
      {:ok, payload} -> Map.merge(base, compare(replay.assert, payload))
      {:error, reason} -> Map.merge(base, %{status: :error, detail: inspect(reason)})
    end
  end

  # An empty `assert` still re-runs the call. That is worth doing on its own: it proves the
  # retrieval the report names still executes and still returns something, which is the
  # minimum a citation-of-a-retrieval has to mean.
  defp compare(asserted, _payload) when map_size(asserted) == 0,
    do: %{status: :verified, detail: "re-executed; no value asserted"}

  defp compare(asserted, payload) do
    mismatches =
      for {path, expected} <- asserted,
          actual = dig(payload, String.split(path, ".")),
          actual != expected,
          do: "#{path}: report says #{inspect(expected)}, corpus says #{inspect(actual)}"

    if mismatches == [],
      do: %{status: :verified, detail: "#{map_size(asserted)} value(s) re-derived"},
      else: %{status: :failed, detail: Enum.join(mismatches, "; ")}
  end

  defp dig(payload, path) do
    Enum.reduce_while(path, payload, fn key, acc ->
      case acc do
        %{} = map -> {:cont, Map.get(map, key, Map.get(map, safe_atom(key)))}
        _ -> {:halt, nil}
      end
    end)
  end

  # `to_existing_atom` because a report is untrusted input and a path of arbitrary strings
  # must not be able to grow the atom table.
  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  # HEURISTIC, and labelled as one everywhere it surfaces. A paragraph carrying a figure but
  # no URN and no replay is *probably* an unsourced quantitative claim — the exact shape a
  # frequency claim takes when it was generalised from a ranked sample. It is a list to read,
  # never a verdict.
  @figure ~r/\b\d[\d,.]*\b/
  @citation ~r/pramana:[a-z0-9\-.]+:/i

  defp unsourced_figures(markdown) do
    markdown
    |> String.split(~r/\n\s*\n/)
    |> Enum.reject(&String.contains?(&1, "pramana-replay"))
    |> Enum.filter(&(Regex.match?(@figure, &1) and not Regex.match?(@citation, &1)))
    |> Enum.map(&(&1 |> String.trim() |> String.slice(0, 120)))
  end

  # No `nil` clause: this is only reached inside the branch that already required both bake
  # ids to be present, so a defensive one is unreachable code dialyzer would refuse.
  defp short(id), do: String.slice(id, 0, 12)
end
