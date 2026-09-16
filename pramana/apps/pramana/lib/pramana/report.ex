defmodule Pramana.Report do
  @moduledoc """
  Verifies a **sourced report**, not just the quotations inside it.

  `Pramana.Guard` re-resolves every URN and byte-compares the quoted span, which makes a
  mismatched quotation detectable at a recognized address. It says nothing about claims that actually
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

  @type status :: :verified | :failed | :incomplete | :no_checkable_evidence

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

  @opening ~r/^ {0,3}```pramana-replay[ \t]*\r?$/
  @closing ~r/^ {0,3}```[ \t]*\r?$/

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
    markdown |> parse_document() |> Map.take([:replays, :malformed])
  end

  @doc "Masks replay fences with equal-length bytes for prose citation scanning; original offsets survive."
  @spec mask_replays(String.t()) :: String.t()
  def mask_replays(markdown) when is_binary(markdown),
    do: markdown |> parse_document() |> Map.fetch!(:citation_text)

  defp parse_document(markdown) do
    parsed =
      markdown
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce(%{replays: [], malformed: [], open: nil, prose: []}, &parse_line/2)
      |> close_unterminated()

    %{
      replays: Enum.reverse(parsed.replays),
      malformed: Enum.reverse(parsed.malformed),
      citation_text: parsed.prose |> Enum.reverse() |> Enum.join("\n")
    }
  end

  defp parse_line({text, line}, acc) do
    opening? = Regex.match?(@opening, text)
    acc = record_prose(acc, text, opening?)

    cond do
      opening? ->
        acc = close_unterminated(acc)
        %{acc | open: %{line: line, body: []}}

      acc.open && Regex.match?(@closing, text) ->
        json = acc.open.body |> Enum.reverse() |> Enum.join("\n")

        case decode(json, acc.open.line) do
          {:ok, replay} ->
            %{acc | replays: [replay | acc.replays], open: nil}

          {:error, reason} ->
            %{
              acc
              | malformed: [%{line: acc.open.line, reason: reason} | acc.malformed],
                open: nil
            }
        end

      acc.open ->
        put_in(acc, [:open, :body], [text | acc.open.body])

      true ->
        acc
    end
  end

  # Replay arguments and asserted values are data, not additional prose citations.
  # Mask bytes, not graphemes, so every following citation keeps its exact offset.
  defp record_prose(acc, text, opening?) do
    prose = if opening? or acc.open != nil, do: String.duplicate(" ", byte_size(text)), else: text
    %{acc | prose: [prose | acc.prose]}
  end

  defp close_unterminated(%{open: nil} = acc), do: acc

  defp close_unterminated(acc) do
    %{
      acc
      | malformed: [%{line: acc.open.line, reason: :unterminated_replay} | acc.malformed],
        open: nil
    }
  end

  defp decode(json, line) do
    with {:ok, map} <- Jason.decode(json),
         %{"tool" => tool, "arguments" => args} when is_binary(tool) and is_map(args) <- map,
         :ok <- validate_assertions(Map.get(map, "assert", %{})),
         :ok <- validate_bake_id(map["bake_id"]) do
      {:ok,
       %{
         tool: tool,
         arguments: args,
         bake_id: map["bake_id"],
         assert: Map.get(map, "assert", %{}),
         line: line
       }}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :missing_tool_or_arguments}
    end
  end

  defp validate_assertions(asserted) when is_map(asserted) do
    if Enum.all?(Map.keys(asserted), fn key ->
         is_binary(key) and Enum.all?(String.split(key, "."), &(String.trim(&1) != ""))
       end),
       do: :ok,
       else: {:error, :invalid_assertion_path}
  end

  defp validate_assertions(_), do: {:error, :invalid_assertions}
  defp validate_bake_id(nil), do: :ok
  defp validate_bake_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
  defp validate_bake_id(_), do: {:error, :invalid_bake_id}

  @doc """
  Verifies a report: quotations through `Guard`, replay records by re-execution.

  `executor` receives `{tool, arguments}` and returns the tool's payload. Pass
  `bake_id:` to override what the replays are compared against; it defaults to the
  current bake. `status` is authoritative and `ok?` is true only for `:verified`.
  Existence-only citations, unresolved foreign addresses, unasserted replays and
  unavailable evidence make a report incomplete. With no evidence it is not a pass.
  """
  @spec verify(String.t(), keyword()) :: map()
  def verify(markdown, opts \\ []) when is_binary(markdown) do
    executor = Keyword.fetch!(opts, :executor)
    current_bake = Keyword.get_lazy(opts, :bake_id, &Bake.current_id/0)

    %{replays: all_replays, malformed: malformed, citation_text: citation_text} =
      parse_document(markdown)

    # A REPORT IS UNTRUSTED INPUT AND EVERY REPLAY IS A QUERY. A document carrying ten
    # thousand fenced blocks would otherwise turn a verification request into a denial of
    # service against the corpus. Excess records are reported as skipped rather than
    # silently dropped, and their presence prevents `ok?` — a report whose evidence was not
    # all examined has not been verified.
    max = Keyword.get(opts, :max_replays, @max_replays)
    if not is_integer(max) or max < 0, do: raise(ArgumentError, "max_replays must be nonnegative")
    max = min(max, @max_replays)
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
    {resolved, foreign} = Citation.rewrite(markdown, scan_text: citation_text)

    citations =
      resolved
      |> mask_replays()
      |> Guard.check_output()
      |> Map.update!(:findings, fn findings -> Enum.map(findings, &Guard.diagnose/1) end)

    results = Enum.map(replays, &check_replay(&1, executor, current_bake))
    replay_counts = Enum.frequencies_by(results, & &1.status)

    counts = %{
      verified_quotes: citations.verified_quotes,
      existence_only: citations.existence_only,
      citation_failures: citations.failed,
      unresolved_foreign: Enum.count(foreign, &is_nil(&1.urn)),
      verified_replays: Map.get(replay_counts, :verified, 0),
      unasserted_replays: Map.get(replay_counts, :executed, 0),
      replay_failures: Map.get(replay_counts, :failed, 0),
      replay_errors: Map.get(replay_counts, :error, 0),
      unverifiable_replays: Map.get(replay_counts, :unverifiable, 0),
      malformed_replays: length(malformed),
      skipped_replays: length(skipped)
    }

    status = overall_status(counts)

    %{
      status: status,
      ok?: status == :verified,
      summary: summary(status),
      counts: counts,
      citations: Map.put(citations, :offset_basis, :resolved_text),
      resolved_text: resolved,
      foreign: foreign,
      replays: results,
      malformed: malformed,
      skipped: length(skipped),
      unsourced_figures: unsourced_figures(markdown),
      bake_id: current_bake
    }
  end

  defp overall_status(counts) do
    incomplete =
      counts.existence_only + counts.unresolved_foreign + counts.unasserted_replays +
        counts.replay_errors + counts.unverifiable_replays + counts.malformed_replays +
        counts.skipped_replays

    cond do
      counts.citation_failures + counts.replay_failures > 0 -> :failed
      incomplete > 0 -> :incomplete
      counts.verified_quotes + counts.verified_replays > 0 -> :verified
      true -> :no_checkable_evidence
    end
  end

  defp summary(:verified),
    do:
      "All checkable quotations and asserted replay values verified. " <>
        "This does not verify interpretation or corpus completeness."

  defp summary(:failed),
    do:
      "At least one citation or asserted replay value did not hold. Inspect the findings and any unchecked evidence."

  defp summary(:incomplete),
    do:
      "Verification is incomplete: some evidence was unresolved, unchecked, or checked only for existence or execution."

  defp summary(:no_checkable_evidence),
    do:
      "Nothing in this report was checkable: no recognized citations or replay assertions. This is not a pass."

  defp check_replay(replay, executor, current_bake) do
    base = Map.take(replay, [:tool, :arguments, :bake_id, :line])

    if replay.bake_id && replay.bake_id != current_bake do
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
      {:ok, payload} when is_map(payload) ->
        Map.merge(base, compare(replay.assert, payload))

      {:error, reason} ->
        Map.merge(base, %{status: :error, detail: inspect(reason)})

      _ ->
        Map.merge(base, %{status: :error, detail: "Replay did not return a structured payload."})
    end
  rescue
    _error ->
      Map.merge(base, %{
        status: :error,
        detail: "Replay execution failed; no assertion was checked."
      })
  end

  # Executing a query without an assertion verifies no claim about its result.
  defp compare(asserted, _payload) when map_size(asserted) == 0,
    do: %{status: :executed, detail: "re-executed; no value asserted", mismatches: []}

  defp compare(asserted, payload) do
    mismatches =
      asserted
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {path, expected} ->
        case dig(payload, String.split(path, ".")) do
          {:ok, actual} when actual == expected ->
            []

          {:ok, actual} ->
            [%{path: path, expected: expected, actual: actual, actual_present: true}]

          :error ->
            [%{path: path, expected: expected, actual: nil, actual_present: false}]
        end
      end)

    if mismatches == [] do
      %{status: :verified, detail: "#{map_size(asserted)} value(s) re-derived", mismatches: []}
    else
      detail = Enum.map_join(mismatches, "; ", &mismatch_description/1)

      %{status: :failed, detail: detail, mismatches: mismatches}
    end
  end

  defp mismatch_description(mismatch) do
    actual = if mismatch.actual_present, do: inspect(mismatch.actual), else: "<missing>"
    "#{mismatch.path}: report says #{inspect(mismatch.expected)}, corpus says #{actual}"
  end

  defp dig(value, []), do: {:ok, value}

  defp dig(payload, [key | rest]) when is_map(payload) do
    case fetch_key(payload, key) do
      {:ok, value} -> dig(value, rest)
      :error -> :error
    end
  end

  defp dig(_payload, _path), do: :error

  defp fetch_key(map, key) do
    case Map.fetch(map, key) do
      {:ok, _} = found -> found
      :error -> Map.fetch(map, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> :error
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

  defp short(nil), do: "unstamped"
  defp short(id), do: String.slice(id, 0, 12)
end
