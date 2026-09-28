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
       "release_id": "retrieval-release-id…",
       "assert": {"total_segments": 36775, "distinct_works": 1904}}
      ```

  Every tool response emits `replay: {tool, arguments}`, `bake_id` and `release_id`. Copy
  both identities from the response alongside the call; do not substitute today's stamp.
  `assert` names response keys and the values the report claims for them; dotted paths reach into nested maps.

  ## Three refusals, and each is the point

  1. **A different or unavailable recorded bake or release is `:unverifiable`, never
     `:failed`.** Named identities must match the current selection before execution. For
     a release-bound record they must also match the executor's returned receipt before
     assertions are compared. The source or retrieval state may have changed; the claim may
     well have been true when it was made. Reporting that as a
     falsehood would teach people to ignore the checker, which is exactly how `integrity`
     lost its audience while crying wolf over 1,228 X texts.
  2. **A figure with no quote and no replay is reported as unsourced.** Counting only what
     it can check, and publishing a pass rate over that denominator, is rule 44 in the one
     place it would be most embarrassing. This one is a **heuristic** — it looks for numerals
     in a paragraph carrying no citation — so it is a warning list, never a verdict.
  3. **It does not judge whether a citation supports its claim.** `Guard` draws that line
     already and it holds here: mechanical warrant, never interpretation.

  ## Compatibility and limits

  Release ids are opaque: historical coarse ids are not upgraded or reinterpreted. Records
  without a release id retain the older bake-only (or unrecorded) behavior, with an explicit
  `identity_scope` and limitation note. They check current values, not a historical index.
  A missing or malformed release receipt cannot verify a release-bound record.

  `checked_identity` records the selected identities read at the start of this check; it is
  not a transactional snapshot. No stamp, content scan, historical database reconstruction
  or retrieval-code/default pinning happens here. Even matching receipts cannot detect an
  unstamped edit or every concurrent mutation, and do not promise immutable replay.

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
  alias Pramana.EvidenceInput
  alias Pramana.Guard
  alias Pramana.Release
  alias Pramana.Report.ForeignEvidence

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
          release_id: String.t() | nil,
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

  @doc "Prose regions in original UTF-8 bytes. Replay fences, including malformed ones, are boundaries."
  @spec prose_regions(String.t()) :: [map()]
  def prose_regions(markdown) when is_binary(markdown),
    do: markdown |> parse_document() |> Map.fetch!(:regions)

  defp parse_document(markdown) do
    initial = %{replays: [], malformed: [], open: nil, regions: [], prose_start: 0, offset: 0}

    parsed =
      markdown
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce(initial, &parse_line/2)
      |> close_unterminated()
      |> close_prose(byte_size(markdown))

    %{
      replays: Enum.reverse(parsed.replays),
      malformed: Enum.reverse(parsed.malformed),
      regions: Enum.reverse(parsed.regions)
    }
  end

  defp parse_line({text, line}, acc) do
    next_offset = acc.offset + byte_size(text) + 1
    acc = consume_line(acc, text, line, next_offset)
    %{acc | offset: next_offset}
  end

  defp consume_line(acc, text, line, next_offset) do
    cond do
      Regex.match?(@opening, text) ->
        acc = acc |> close_prose(acc.offset) |> close_unterminated()
        %{acc | open: %{line: line, body: []}, prose_start: nil}

      acc.open != nil and Regex.match?(@closing, text) ->
        acc |> decode_block() |> Map.put(:prose_start, next_offset)

      acc.open != nil ->
        put_in(acc, [:open, :body], [text | acc.open.body])

      true ->
        acc
    end
  end

  defp decode_block(acc) do
    json = acc.open.body |> Enum.reverse() |> Enum.join("\n")

    case decode(json, acc.open.line) do
      {:ok, replay} ->
        %{acc | replays: [replay | acc.replays], open: nil}

      {:error, reason} ->
        %{acc | malformed: [%{line: acc.open.line, reason: reason} | acc.malformed], open: nil}
    end
  end

  defp close_prose(%{prose_start: nil} = acc, _last), do: acc

  defp close_prose(acc, last) do
    if acc.prose_start < last,
      do: %{acc | regions: [%{byte_start: acc.prose_start, byte_end: last} | acc.regions]},
      else: acc
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
         :ok <- validate_bake_id(map["bake_id"]),
         :ok <- validate_release_id(map["release_id"]) do
      {:ok,
       %{
         tool: tool,
         arguments: args,
         bake_id: map["bake_id"],
         release_id: map["release_id"],
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

  defp validate_release_id(nil), do: :ok

  defp validate_release_id(id) when is_binary(id) do
    if String.trim(id) != "", do: :ok, else: {:error, :invalid_release_id}
  end

  defp validate_release_id(_), do: {:error, :invalid_release_id}

  @doc """
  Verifies a report: quotations through `Guard`, replay records by re-execution.

  `executor` receives `{tool, arguments}` and returns the tool's payload. Pass
  `bake_id:` to override what the replays are compared against; it defaults to the
  current bake. `release_id:` similarly overrides the selected release for injected
  executors. A release-bound executor must return the recorded identity fields with its
  payload (string or atom keys), as the real MCP executor does. `status` is authoritative and `ok?` is true only for `:verified`.
  Existence-only citations, unresolved or unchecked foreign addresses, unasserted replays
  and unavailable evidence make a report incomplete. With no evidence it is not a pass.
  """
  @spec verify(String.t(), keyword()) :: map()
  def verify(markdown, opts \\ []) when is_binary(markdown) do
    case EvidenceInput.check(markdown) do
      :ok -> verify_bounded(markdown, opts)
      {:error, refusal} -> refused(markdown, refusal)
    end
  end

  defp verify_bounded(markdown, opts) do
    executor = Keyword.fetch!(opts, :executor)

    current = %{
      bake_id: Keyword.get_lazy(opts, :bake_id, &Bake.current_id/0),
      release_id: Keyword.get_lazy(opts, :release_id, &Release.current_id/0)
    }

    %{replays: all_replays, malformed: malformed, regions: regions} = parse_document(markdown)

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
    {resolved, foreign} = Citation.rewrite(markdown, regions: regions)

    citations =
      resolved
      |> Guard.check_output(regions: prose_regions(resolved))
      |> Map.update!(:findings, fn findings -> Enum.map(findings, &Guard.diagnose/1) end)

    foreign_evidence = ForeignEvidence.classify(foreign, resolved, citations.findings)
    foreign_counts = foreign_evidence.counts
    results = Enum.map(replays, &check_replay(&1, executor, current))
    replay_counts = Enum.frequencies_by(results, & &1.status)

    counts = %{
      verified_quotes: citations.verified_quotes,
      existence_only: citations.existence_only,
      citation_failures: citations.failed,
      unresolved_foreign: foreign_counts.unresolved,
      unchecked_foreign: foreign_counts.unchecked,
      literal_foreign: foreign_counts.literal,
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
      foreign: foreign_evidence.foreign,
      replays: results,
      malformed: malformed,
      skipped: length(skipped),
      unsourced_figures: unsourced_figures(markdown),
      bake_id: current.bake_id,
      checked_identity: current
    }
  end

  defp refused(markdown, refusal) do
    %{
      status: :incomplete,
      ok?: false,
      summary: "Report input refused; nothing was checked and no partial pass was produced.",
      refusal: refusal,
      counts: %{
        verified_quotes: 0,
        existence_only: 0,
        citation_failures: 0,
        unresolved_foreign: 0,
        unchecked_foreign: 0,
        literal_foreign: 0,
        verified_replays: 0,
        unasserted_replays: 0,
        replay_failures: 0,
        replay_errors: 0,
        unverifiable_replays: 0,
        malformed_replays: 0,
        skipped_replays: 0
      },
      citations: %{
        ok?: false,
        checked: 0,
        failed: 0,
        verified_quotes: 0,
        existence_only: 0,
        translations: 0,
        findings: [],
        offset_basis: :resolved_text
      },
      resolved_text: markdown,
      foreign: [],
      replays: [],
      malformed: [],
      skipped: 0,
      unsourced_figures: [],
      bake_id: nil,
      checked_identity: %{bake_id: nil, release_id: nil}
    }
  end

  defp overall_status(counts) do
    incomplete =
      counts.existence_only + counts.unresolved_foreign + counts.unchecked_foreign +
        counts.unasserted_replays + counts.replay_errors + counts.unverifiable_replays +
        counts.malformed_replays + counts.skipped_replays

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

  defp check_replay(replay, executor, current) do
    base =
      replay
      |> Map.take([:tool, :arguments, :bake_id, :release_id, :line])
      |> Map.put(:identity_scope, identity_scope(replay))
      |> Map.put(:identity_note, identity_note(replay))

    case identity_issue(replay, current, "current selection") do
      nil -> execute_and_compare(base, replay, executor)
      issue -> Map.merge(base, issue)
    end
  end

  defp identity_scope(%{release_id: id}) when is_binary(id), do: :retrieval_release
  defp identity_scope(%{bake_id: id}) when is_binary(id), do: :source_bake_only
  defp identity_scope(_), do: :unrecorded

  defp identity_note(%{release_id: nil}),
    do:
      "No retrieval release was recorded; this checks current results only, not a historical index."

  defp identity_note(_),
    do: "Matching recorded identities do not freeze historical rows, retrieval code or defaults."

  defp identity_issue(replay, current, context) do
    Enum.find_value([:bake_id, :release_id], fn key ->
      recorded = Map.fetch!(replay, key)
      actual = Map.get(current, key)

      if recorded && recorded != actual do
        %{
          status: :unverifiable,
          identity_field: key,
          detail:
            "recorded #{key} #{short(recorded)}; #{context} has #{short(actual)}. " <>
              "The claim is not refuted — " <> identity_limitation(context)
        }
      end
    end)
  end

  defp identity_limitation("current selection"),
    do: "it cannot be re-run here against the recorded inputs."

  defp identity_limitation("replay response"),
    do: "the response does not establish the recorded inputs."

  # A selection can change between the entry check and the tool's response. Do not compare
  # assertions against a visibly different (or absent) receipt. This is not snapshot isolation:
  # the tool itself can still observe unstamped or concurrent data changes under the same id.
  defp compare_receipt(%{release_id: nil} = replay, payload), do: compare(replay.assert, payload)

  defp compare_receipt(replay, payload) do
    receipt = Map.new([:bake_id, :release_id], &{&1, receipt_id(payload, &1)})
    identity_issue(replay, receipt, "replay response") || compare(replay.assert, payload)
  end

  defp receipt_id(payload, key) do
    case fetch_key(payload, Atom.to_string(key)) do
      {:ok, id} when is_binary(id) and byte_size(id) > 0 -> id
      _ -> nil
    end
  end

  defp execute_and_compare(base, replay, executor) do
    case executor.(replay.tool, replay.arguments) do
      {:ok, payload} when is_map(payload) ->
        Map.merge(base, compare_receipt(replay, payload))

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
