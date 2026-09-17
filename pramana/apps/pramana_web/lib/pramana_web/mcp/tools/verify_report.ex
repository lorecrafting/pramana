defmodule PramanaWeb.MCP.Tools.VerifyReport do
  @moduledoc """
  Checks a whole sourced report: its quotations, and the retrievals its figures rest on.

  `verify_citation` byte-compares one quotation. This does that for every citation in a
  document **and** re-executes the searches and surveys the document cites, because a
  citation guard structurally cannot reach the claims that carry a report:

      "T0262 says X"                                → byte-compared already
      "X appears 36,775 times across 1,904 works"   → needs the survey re-run
      "no Japanese-composed text uses X"            → needs the search re-run and still empty

  A frequency claim generalised from twenty ranked hits reads exactly like one counted over
  twelve million segments. This is how the difference becomes visible.

  ## Writing a report this can check

  Ordinary markdown. Where a claim rests on a retrieval rather than a quotation, include the
  call that produced it — every tool response already returns `replay: {tool, arguments}`
  beside `bake_id` and `release_id`. Copy both identities from that response:

      ```pramana-replay
      {"tool": "survey_corpus",
       "arguments": {"query": "一切眾生"},
       "bake_id": "b143d7f3…",
       "release_id": "retrieval-release-id…",
       "assert": {"total_segments": 36775, "distinct_works": 1904}}
      ```

  `assert` names response keys and the values the report claims for them; a dotted path
  reaches into nested maps. Omit `assert` and the call is still re-run, which proves the
  retrieval named still executes and still returns something.

  ## What the verdicts mean, and the one that matters most

  - `verified` — re-executed and every asserted value re-derived.
  - `failed` — a value differs, and both numbers are named.
  - **`unverifiable`** — a named bake or release differs or is unavailable. Release-bound
    records also require matching identities in the replay response before assertions
    are compared. The claim **cannot be checked against its recorded inputs here**. It is not refuted, and it does not pass either.
    Reporting a changed corpus as a false report is how a checker teaches people to ignore
    it.
  - `error` — the tool is unknown, its replay arguments were rejected, or execution failed.
  - `executed` — the call ran but no value was asserted; it does not verify a claim.

  The overall `status` is `verified`, `failed`, `incomplete`, or `no_checkable_evidence`.
  `ok?` is true only for `verified`; the summary and the reader use that same status.

  `unsourced_figures` is a **heuristic warning list, never a verdict**: paragraphs carrying a
  number with no citation and no replay record. It reads, it does not judge — a check that
  failed on any prose containing a page number would be unusable.

  Records without `release_id` remain compatible but carry an `identity_scope` and a note:
  a source-only or unrecorded replay checks current values, not the historical retrieval
  state. `checked_identity` preserves the identities read when verification began, distinct
  from the outer reply's later metadata. Matching ids do not freeze data, code or defaults.

  ## What it does not do

  It does not judge whether a citation *supports* the claim attached to it. That is
  interpretation; this answers only the mechanical question. And it does not fix anything —
  the MCP surface is read-only (invariant #7), so this reports and stops.
  """

  use Anubis.Server.Component, type: :tool

  alias PramanaWeb.CheckRun
  alias PramanaWeb.MCP.ReplayExecutor
  alias PramanaWeb.MCP.Reply

  # Execution policy, not a measured corpus-performance target. Leave a margin
  # beneath the HTTP transport's 30 s response wait. Queueing and reply delivery
  # have separate lifetimes; this budget begins when the component is invoked.
  @max_timeout_ms 25_000

  @doc false
  @spec timeout_ms(keyword()) :: pos_integer()
  def timeout_ms(opts \\ []) do
    timeout = CheckRun.timeout_ms(Keyword.put_new(opts, :timeout_ms, @max_timeout_ms))

    if timeout > @max_timeout_ms,
      do: raise(ArgumentError, "MCP report timeout_ms must not exceed #{@max_timeout_ms}")

    timeout
  end

  schema do
    field(:report, :string,
      required: true,
      description:
        "The report, as markdown. Citations are found anywhere in the prose; retrieval " <>
          "claims are read from ```pramana-replay fenced blocks."
    )
  end

  @impl true
  def execute(%{report: markdown} = params, frame) do
    opts = Application.get_env(:pramana_web, __MODULE__, [])
    opts = Keyword.put(opts, :timeout_ms, timeout_ms(opts))
    outcome = CheckRun.run(markdown, opts)
    {:reply, response(outcome, params), frame}
  end

  defp response(%{result: nil, execution: execution}, params) do
    {reason, message} = execution_error(execution)
    Reply.error("verify_report", params, reason, message)
  end

  defp response(%{result: result, repair: repair, execution: execution}, params) do
    payload =
      result
      |> Map.update!(:foreign, fn citations ->
        Enum.map(citations, fn found -> Map.update!(found, :reason, &wire_reason/1) end)
      end)
      |> Map.put(:runnable_tools, ReplayExecutor.tools())
      # DIAGNOSIS SERVES A CALLER WHO CHECKS; REPAIR SERVES THE ONE WHO DOES NOT, and that
      # is most of them. `docs/PLAN.md` L3. Nothing here writes to the corpus — it rewrites
      # the caller's own document — so invariant #7 is untouched.
      |> Map.put(:repair, repair)
      |> Map.put(:execution, execution)
      |> Map.put(:note, note(result) <> execution_note(execution))

    Reply.json("verify_report", params, payload)
  end

  defp execution_error(:timed_out),
    do:
      {:report_check_timed_out,
       "Report verification exceeded its execution budget; no verdict was completed."}

  defp execution_error(:cancelled),
    do: {:report_check_cancelled, "Report verification was cancelled; no verdict was completed."}

  defp execution_error(:error),
    do: {:report_check_failed, "Report verification could not complete; no verdict is available."}

  defp execution_note(:completed), do: ""

  defp execution_note(:timed_out),
    do:
      " Verification completed, but repair exceeded the shared execution budget and is unavailable."

  defp execution_note(:cancelled),
    do: " Verification completed, but repair was cancelled and is unavailable."

  defp execution_note(:error),
    do: " Verification completed, but repair failed and is unavailable."

  # The note leads with what was NOT established. A report can be free of failures and still
  # unverified — every replay `unverifiable` against an older corpus, or no evidence at all —
  # and a summary that opens with "0 failures" invites exactly that misreading.
  # WHY the citations failed, in the note, because the reason changes what the author does
  # next. `:wrong_address` means the words are real and the URN is not — a reference to
  # correct. A completed no-match search does not establish fabrication.
  defp reasons(findings) do
    counts =
      findings
      |> Enum.map(& &1[:reason])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    if counts == %{} do
      nil
    else
      "Failed citations by reason: " <>
        Enum.map_join(counts, ", ", fn {reason, n} -> "#{reason} #{n}" end) <> "."
    end
  end

  defp wire_reason(reason) when is_tuple(reason) do
    [code | details] = Tuple.to_list(reason)
    %{code: code, details: details}
  end

  defp wire_reason(reason), do: reason

  defp note(result) do
    counts = Enum.frequencies_by(result.replays, & &1.status)
    unverifiable = Map.get(counts, :unverifiable, 0)

    [
      result.summary,
      if(result.counts.unresolved_foreign > 0,
        do:
          "#{result.counts.unresolved_foreign} recognized citation(s) in another scheme could not be resolved."
      ),
      if(result.counts.unasserted_replays > 0,
        do:
          "#{result.counts.unasserted_replays} replay(s) executed without verifying any asserted value."
      ),
      if(unverifiable > 0,
        do:
          "#{unverifiable} replay record(s) lack matching recorded source or release evidence. " <>
            "Those claims are neither confirmed nor refuted. A stamp alone cannot restore " <>
            "the historical data or execution environment."
      ),
      if(Enum.any?(result.replays, &(&1.identity_scope != :retrieval_release)),
        do:
          "Some replay records have no retrieval release identity; they check current values " <>
            "without establishing historical index equivalence."
      ),
      if(result.skipped > 0,
        do:
          "#{result.skipped} replay record(s) beyond the per-report cap were not executed, " <>
            "so this report was not fully examined."
      ),
      reasons(result.citations.findings),
      if(result.citations.existence_only > 0,
        do:
          "#{result.citations.existence_only} citation(s) were checked for EXISTENCE only — " <>
            "no quoted text was found beside them, which is a materially weaker guarantee " <>
            "than a byte-compared quote."
      ),
      if(result.unsourced_figures != [],
        do:
          "#{length(result.unsourced_figures)} paragraph(s) carry a figure with no citation " <>
            "and no replay record. That is a heuristic, not a finding."
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
