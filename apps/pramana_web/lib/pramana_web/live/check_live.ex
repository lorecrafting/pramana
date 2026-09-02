defmodule PramanaWeb.CheckLive do
  @moduledoc """
  Paste a report; find out which of its claims survive.

  `Pramana.Report.verify/2` shipped on 2026-08-28 and for three days the only way to
  reach it was an MCP call, which is rule 60: **a capability a person cannot reach has
  not shipped.** This is that surface — one textarea and a verdict list.

  ## Why this screen and not a chat box

  Every other screen here helps you find something. This one helps you disbelieve
  something, and it is the only thing in this space that does. `verify_citation` and
  fojin's `/api/verify/quote` check a single quotation; this checks a **whole document,
  including its arithmetic** — because the claims that carry a report are not the quotes:

      "T0262 says X"                              -> byte-compared, and always could be
      "X appears 36,775 times across 1,904 works" -> needs the survey re-run
      "no Japanese-composed text uses X"          -> needs the search re-run, still empty

  A frequency generalised from twenty ranked hits reads exactly like one counted over
  twelve million segments. That is the failure this page makes visible, and it is live in
  the world right now: people are getting fluent, confident, invented Dharma from general
  assistants, and there is nowhere to take it. **Nothing here asks you to trust a model of
  ours** — the checks are byte comparisons and re-executed counts.

  ## Three verdicts, not two, and the third is the reason this is worth building

  `failed` and `unverifiable` are rendered differently and must never be collapsed. A
  replay recorded against another `bake_id` **cannot be re-run here**; the corpus changed,
  and the claim may well have been true when it was made. Reporting that as a falsehood is
  how a checker teaches people to ignore it — which is exactly how `mix pramana.integrity`
  lost its audience by crying wolf over 1,228 X texts.

  ## What it refuses to do

  It does not judge whether a citation **supports** the claim attached to it. `Pramana.Guard`
  draws that line and this page holds it: mechanical warrant, never interpretation. And
  `unsourced figures` is a heuristic warning list — a number in a paragraph with no citation
  — displayed as a prompt to look, never as a verdict.

  ## A known limit, stated rather than discovered

  The check runs **synchronously in the LiveView process**, so a report carrying the full
  25 replay records holds the socket for as long as those 25 retrievals take — a survey
  over 12.5M segments is ~1.2 s, so tens of seconds is reachable. Bounded, not free. It is
  sync because this is a self-hosted reader with one person in front of it, and moving to
  `start_async` buys responsiveness at the cost of a second state machine on a screen whose
  whole value is that its verdicts are simple. Revisit it if this is ever served to
  strangers, where the paste box is also the obvious way to make the corpus do work on
  someone else's behalf.

  ## Counting, with the denominator

  The summary never says "verified". It says how many citations were byte-compared, how many
  were only checked for **existence** because no quotation was attached, and how many
  quotations were of a *translation* rather than of the text. Three citations verified across
  three renderings of one Pāli line is a very different claim from three verified quotes of
  scripture, and a summary that does not distinguish them overstates what was checked —
  rules 22, 44 and 54, on the screen where a reader will act on the number.
  """
  use PramanaWeb, :live_view

  alias Pramana.Report
  alias PramanaWeb.MCP.ReplayExecutor

  # A report is untrusted input and every replay record in it is a query against the
  # corpus. `Report.verify/2` already caps how many it will execute; this caps the paste
  # itself, because the citation scan and the figure heuristic are regex passes over the
  # whole document and neither is capped by that. Refused with a message rather than
  # truncated — a silently shortened report would be reported as verified on the half that
  # was read, which is rule 4 in the place it would do the most damage.
  #
  # **This is the only limit there is.** Phoenix's `:max_frame_size` defaults to
  # `:infinity` and the endpoint does not set it, so nothing at the transport bounds a
  # paste before it arrives here. Checked rather than assumed.
  @max_bytes 200_000

  # Held as a string rather than written into the template: HEEx reads `{` as
  # interpolation, and a JSON example is mostly braces.
  @replay_example ~s|```pramana-replay
{"tool": "survey_corpus",
 "arguments": {"query": "一切眾生"},
 "bake_id": "b143d7f3…",
 "assert": {"total": 36775, "works": 1904}}
```|

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Check a report",
       report: "",
       result: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("check", %{"report" => report}, socket) do
    cond do
      String.trim(report) == "" ->
        {:noreply, assign(socket, result: nil, error: nil, report: report)}

      byte_size(report) > @max_bytes ->
        {:noreply,
         assign(socket,
           report: report,
           result: nil,
           error:
             "That report is #{div(byte_size(report), 1000)} KB and the limit is " <>
               "#{div(@max_bytes, 1000)} KB. Nothing was checked — split it rather than " <>
               "trusting a partial pass."
         )}

      true ->
        result = Report.verify(report, executor: ReplayExecutor.executor())
        {:noreply, assign(socket, report: report, result: result, error: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-1">
        <h1 class="text-xl font-semibold">Check a report</h1>
        <p class="text-sm text-base-content/70">
          Paste anything that cites this corpus. Every quotation is re-resolved and
          byte-compared, and every retrieval claim carrying a
          <code class="text-xs">pramana-replay</code>
          block is re-executed. Nothing here asks you to trust a model.
        </p>
      </section>

      <form phx-submit="check" class="space-y-3">
        <textarea
          name="report"
          rows="12"
          placeholder="Paste a report, an answer, an essay — markdown, with URNs in it."
          class="textarea textarea-bordered w-full font-mono text-sm"
        >{@report}</textarea>
        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary" phx-disable-with="Checking…">Check</button>
          <span class="text-xs text-base-content/60">
            Runnable in a replay block: {Enum.join(ReplayExecutor.tools(), " · ")}
          </span>
        </div>
      </form>

      <.format_help />

      <div :if={@error} class="alert alert-warning text-sm">{@error}</div>

      <div :if={@result} class="space-y-6">
        <.verdict result={@result} />
        <.citations citations={@result.citations} />
        <.replays replays={@result.replays} />
        <.malformed entries={@result.malformed} skipped={@result.skipped} />
        <.unsourced figures={@result.unsourced_figures} />

        <p class="font-mono text-xs text-base-content/50">
          checked against bake {String.slice(@result.bake_id || "none", 0, 12)}
        </p>
      </div>
    </Layouts.app>
    """
  end

  # THE BARRIER IS NOT TRUST, IT IS SYNTAX. Quotations need nothing — paste prose with URNs
  # in it and they are found. But nobody arriving here knows what a replay block looks like,
  # and a screen whose distinctive feature is unreachable without documentation has the rule
  # 60 problem one level in. Shown as static help rather than a button that fills the box:
  # an example built from URNs that may not be in this bake would demonstrate the format by
  # failing, which teaches the wrong thing on first use.
  defp format_help(assigns) do
    assigns = assign(assigns, example: @replay_example)

    ~H"""
    <details class="rounded border border-base-300 p-3 text-sm">
      <summary class="cursor-pointer font-medium">What can I paste?</summary>
      <div class="mt-3 space-y-3 text-base-content/80">
        <p>
          <strong>Quotations need no markup.</strong>
          Any URN in the prose is found, and a quotation next to it is byte-compared against
          the passage it names.
        </p>
        <p>
          <strong>A claim about how often, or about an absence, carries the call that
            produced it.</strong>
          Every tool response already returns <code class="text-xs">replay</code>
          beside <code class="text-xs">bake_id</code>, so writing one of these is copying a
          field rather than composing anything:
        </p>
        <pre class="overflow-x-auto rounded bg-base-200 p-3 text-xs"><code>{@example}</code></pre>
        <p>
          <code class="text-xs">assert</code>
          names response keys and the values the report claims for them; a dotted path
          reaches into nested maps. Omit it and the call is still re-run, which at least
          proves the retrieval still executes and still returns something. Omit
          <code class="text-xs">bake_id</code>
          and it is checked against this corpus without asking whether that is the corpus it
          was written against.
        </p>
      </div>
    </details>
    """
  end

  attr :result, :map, required: true

  # THE HEADLINE STATES ITS DENOMINATOR. "Everything checks out" over a document whose
  # single citation carried no quotation is true and misleading; the counts below it are
  # what a reader should act on.
  defp verdict(assigns) do
    ~H"""
    <section class={[
      "rounded-lg p-4",
      @result.ok? && "bg-success/10 border border-success/30",
      !@result.ok? && "bg-error/10 border border-error/30"
    ]}>
      <div class="font-semibold">
        {if @result.ok?,
          do: "Every claim this can check held.",
          else: "Something did not hold."}
      </div>
      <p class="mt-1 text-sm text-base-content/70">{summary(@result)}</p>
      <p class="mt-2 text-xs text-base-content/60">
        This checks warrant, not meaning: whether a passage says what was quoted and whether
        a count re-derives. It does not judge whether a citation supports the claim attached
        to it.
      </p>
    </section>
    """
  end

  defp summary(%{citations: c, replays: r}) do
    replay_note =
      case {Enum.count(r, &(&1.status == :verified)), length(r)} do
        {_, 0} -> "no retrieval claims carried a replay block"
        {ok, n} -> "#{ok} of #{n} retrieval claim(s) re-executed and re-derived"
      end

    [
      "#{c.checked} citation(s) found",
      "#{c.verified_quotes} byte-compared against the text",
      existence_note(c.existence_only),
      translation_note(c.translations),
      replay_note
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp existence_note(0), do: nil

  defp existence_note(n),
    do: "#{n} checked only for EXISTENCE — no quotation was attached to compare"

  defp translation_note(0), do: nil

  defp translation_note(n),
    do: "#{n} quoted a translation rather than the source text"

  attr :citations, :map, required: true

  defp citations(assigns) do
    ~H"""
    <section :if={@citations.checked > 0} class="space-y-2">
      <h2 class="font-semibold">Citations</h2>
      <ul class="space-y-2">
        <li
          :for={finding <- @citations.findings}
          class={[
            "rounded border p-3 text-sm",
            finding.verdict == :ok && "border-base-300",
            finding.verdict != :ok && "border-error/40 bg-error/5"
          ]}
        >
          <div class="flex flex-wrap items-baseline gap-2">
            <span class={[
              "badge badge-sm",
              finding.verdict == :ok && "badge-success",
              finding.verdict != :ok && "badge-error"
            ]}>
              {finding.verdict}
            </span>
            <.link
              navigate={~p"/passage?#{[urn: finding.urn]}"}
              class="link link-hover font-mono text-xs"
            >
              {finding.urn}
            </.link>
            <span :if={finding.layer == "translation"} class="badge badge-sm badge-outline">
              translation, not source
            </span>
          </div>

          <div :if={finding.verdict != :ok and finding.quoted} class="mt-2 space-y-1">
            <div><span class="text-base-content/50">quoted</span> {finding.quoted}</div>
            <div :if={finding.actual}>
              <span class="text-base-content/50">the corpus has</span> {finding.actual}
            </div>
          </div>

          <p :if={Map.get(finding, :explanation)} class="mt-2 text-xs text-base-content/70">
            {finding.explanation}
          </p>
        </li>
      </ul>
    </section>
    """
  end

  attr :replays, :list, required: true

  defp replays(assigns) do
    ~H"""
    <section :if={@replays != []} class="space-y-2">
      <h2 class="font-semibold">Retrieval claims, re-executed</h2>
      <ul class="space-y-2">
        <li
          :for={replay <- @replays}
          class={["rounded border p-3 text-sm", replay_class(replay.status)]}
        >
          <div class="flex flex-wrap items-baseline gap-2">
            <span class={["badge badge-sm", replay_badge(replay.status)]}>{replay.status}</span>
            <span class="font-mono text-xs">{replay.tool}</span>
            <span class="text-xs text-base-content/50">line {replay.line}</span>
          </div>
          <p :if={Map.get(replay, :detail)} class="mt-1 text-xs text-base-content/70">
            {replay.detail}
          </p>
        </li>
      </ul>
    </section>
    """
  end

  # `unverifiable` gets its own colour and never the failure colour. The corpus changed;
  # the claim is not refuted and it does not pass either, and collapsing those two into one
  # red badge is precisely the mistake `Pramana.Report` was written to avoid.
  defp replay_class(:verified), do: "border-base-300"
  defp replay_class(:unverifiable), do: "border-warning/40 bg-warning/5"
  defp replay_class(_), do: "border-error/40 bg-error/5"

  defp replay_badge(:verified), do: "badge-success"
  defp replay_badge(:unverifiable), do: "badge-warning"
  defp replay_badge(_), do: "badge-error"

  attr :entries, :list, required: true
  attr :skipped, :integer, required: true

  defp malformed(assigns) do
    ~H"""
    <section :if={@entries != [] or @skipped > 0} class="space-y-2">
      <h2 class="font-semibold">Evidence that could not be read</h2>
      <p class="text-xs text-base-content/60">
        A record nobody can parse is a claim nobody checked, so these prevent a pass rather
        than being dropped.
      </p>
      <ul class="space-y-1 text-sm">
        <li :for={entry <- @entries} class="text-error">
          line {entry.line}: {entry.reason}
        </li>
        <li :if={@skipped > 0} class="text-error">
          {@skipped} further replay block(s) were not executed — this report carries more
          than the per-request cap.
        </li>
      </ul>
    </section>
    """
  end

  attr :figures, :list, required: true

  defp unsourced(assigns) do
    ~H"""
    <section :if={@figures != []} class="space-y-2">
      <h2 class="font-semibold">Figures with nothing behind them</h2>
      <p class="text-xs text-base-content/60">
        A heuristic, never a verdict: these paragraphs carry a number and no citation and no
        replay block. Some will be page numbers and dates. It reads; it does not judge.
      </p>
      <ul class="space-y-1 text-sm text-base-content/70">
        <li :for={figure <- @figures} class="border-l-2 border-base-300 pl-3">{figure}</li>
      </ul>
    </section>
    """
  end
end
