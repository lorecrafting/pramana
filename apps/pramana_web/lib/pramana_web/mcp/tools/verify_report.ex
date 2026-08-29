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
  beside `bake_id`, so this is copying a field:

      ```pramana-replay
      {"tool": "survey_corpus",
       "arguments": {"query": "一切眾生"},
       "bake_id": "b143d7f3…",
       "assert": {"total": 36775, "works": 1904}}
      ```

  `assert` names response keys and the values the report claims for them; a dotted path
  reaches into nested maps. Omit `assert` and the call is still re-run, which proves the
  retrieval named still executes and still returns something.

  ## What the verdicts mean, and the one that matters most

  - `verified` — re-executed and every asserted value re-derived.
  - `failed` — a value differs, and both numbers are named.
  - **`unverifiable`** — the record names a different `bake_id`. The corpus has changed and
    the claim **cannot be re-run here**. It is not refuted, and it does not pass either.
    Reporting a changed corpus as a false report is how a checker teaches people to ignore
    it.
  - `error` — the tool is unknown or raised.

  `unsourced_figures` is a **heuristic warning list, never a verdict**: paragraphs carrying a
  number with no citation and no replay record. It reads, it does not judge — a check that
  failed on any prose containing a page number would be unusable.

  ## What it does not do

  It does not judge whether a citation *supports* the claim attached to it. That is
  interpretation; this answers only the mechanical question. And it does not fix anything —
  the MCP surface is read-only (invariant #7), so this reports and stops.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Report
  alias PramanaWeb.MCP.ReplayExecutor
  alias PramanaWeb.MCP.Reply

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
    result = Report.verify(markdown, executor: ReplayExecutor.executor())

    payload =
      result
      |> Map.put(:runnable_tools, ReplayExecutor.tools())
      |> Map.put(:note, note(result))

    {:reply, Reply.json("verify_report", params, payload), frame}
  end

  # The note leads with what was NOT established. A report can be free of failures and still
  # unverified — every replay `unverifiable` against an older corpus, or no evidence at all —
  # and a summary that opens with "0 failures" invites exactly that misreading.
  # WHY the citations failed, in the note, because the reason changes what the author does
  # next. `:wrong_address` means the words are real and the URN is not — a reference to
  # correct. `:absent_from_corpus` is the only one of the five that is a fabrication.
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

  defp note(result) do
    counts = Enum.frequencies_by(result.replays, & &1.status)
    unverifiable = Map.get(counts, :unverifiable, 0)

    [
      if(result.citations.checked == 0 and result.replays == [],
        do:
          "Nothing in this report was checkable: no citations and no replay records. That " <>
            "is not a pass — it is an unsourced document."
      ),
      if(unverifiable > 0,
        do:
          "#{unverifiable} replay record(s) name a different bake and could not be re-run. " <>
            "Those claims are neither confirmed nor refuted; re-run against that bake to " <>
            "settle them."
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
    |> case do
      [] -> "Every citation byte-compared and every replay record re-derived against this bake."
      lines -> Enum.join(lines, " ")
    end
  end
end
