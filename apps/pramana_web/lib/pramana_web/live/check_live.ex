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

  ## One overall status, with detailed evidence outcomes

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

  ## An owned, bounded check

  Verification and repair run outside the LiveView callback under one finite budget.
  `CheckRun` stops and observes its worker before this page accepts another check.
  Cancellation, timeout, capacity refusal and execution errors are lifecycle outcomes,
  not findings that a claim is false. A completed verification survives a later repair
  failure. The shared node-local report capacity is not unrestricted-public-hosting
  admission control.

  ## Counting, with the denominator

  The summary distinguishes verified, failed, incomplete and no checkable evidence. It also
  says how many citations were byte-compared, how many
  were only checked for **existence** because no quotation was attached, and how many
  quotations were of a *translation* rather than of the text. Three citations verified across
  three renderings of one Pāli line is a very different claim from three verified quotes of
  scripture, and a summary that does not distinguish them overstates what was checked —
  rules 22, 44 and 54, on the screen where a reader will act on the number.
  """
  use PramanaWeb, :live_view

  alias Pramana.EvidenceInput
  alias PramanaWeb.CheckRun
  alias PramanaWeb.MCP.ReplayExecutor

  # A report is untrusted input and every replay record in it is a query against the
  # corpus. `Report.verify/2` already caps how many it will execute; this caps the paste
  # itself, because the citation scan and the figure heuristic are regex passes over the
  # whole document and neither is capped by that. Refused with a message rather than
  # truncated — a silently shortened report would be reported as verified on the half that
  # was read, which is rule 4 in the place it would do the most damage.
  #
  # The endpoint already caps WebSocket frames at 512,000 bytes. That is not
  # the decoded-report limit, nor proof of bounds for every transport/service.

  # Held as a string rather than written into the template: HEEx reads `{` as
  # interpolation, and a JSON example is mostly braces.
  @replay_example ~s|```pramana-replay
{"tool": "survey_corpus",
 "arguments": {"query": "一切眾生"},
 "bake_id": "b143d7f3…",
 "release_id": "retrieval-release-id…",
 "assert": {"total_segments": 36775, "distinct_works": 1904}}
```|

  @impl true
  def mount(_params, _session, socket) do
    # Only trusted application configuration, never session/form parameters. The
    # callbacks are injectable for deterministic lifecycle tests without models.
    opts = Application.get_env(:pramana_web, __MODULE__, [])

    {:ok,
     socket
     |> put_private(:check_options, opts)
     |> assign(
       page_title: "Check a report",
       form: to_form(%{"report" => ""}),
       result: nil,
       repair: nil,
       error: nil,
       check_run: nil,
       check_state: :idle,
       check_timeout_ms: CheckRun.timeout_ms(opts)
     )}
  end

  @impl true
  def handle_event("check", _params, %{assigns: %{check_run: run}} = socket)
      when not is_nil(run),
      do: {:noreply, socket}

  def handle_event("check", %{"report" => report}, socket) when is_binary(report) do
    socket = reset_check(socket, report)

    case EvidenceInput.check(report) do
      :ok ->
        if String.trim(report) == "",
          do: {:noreply, socket},
          else: {:noreply, start_check(socket, report)}

      {:error, %{code: :input_too_large, max_bytes: max}} ->
        {:noreply,
         assign(socket,
           error:
             "That report is #{div(byte_size(report), 1000)} KB and the limit is " <>
               "#{div(max, 1000)} KB. Nothing was checked — split it rather than " <>
               "trusting a partial pass."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> reset_check("")
         |> assign(error: "Enter valid UTF-8 report text. Nothing was checked.")}
    end
  end

  def handle_event("check", _params, socket),
    do:
      {:noreply,
       socket |> reset_check("") |> assign(error: "Enter report text. Nothing was checked.")}

  def handle_event("cancel", _params, %{assigns: %{check_run: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("cancel", _params, socket) do
    # Keep the admission slot until handle_async: CheckRun acknowledges worker
    # death before returning. A disabled button alone cannot prevent overlap.
    {:noreply,
     socket
     |> assign(check_state: :cancelling)
     |> cancel_async({:check, socket.assigns.check_run}, {:shutdown, :cancel})}
  end

  @impl true
  def handle_info({:check_verified, id, result}, socket) do
    if socket.assigns.check_run == id and socket.assigns.check_state == :verifying,
      do: {:noreply, assign(socket, result: result, check_state: :repairing)},
      else: {:noreply, socket}
  end

  @impl true
  def handle_async({:check, id}, reply, %{assigns: %{check_run: id}} = socket) do
    outcome =
      case reply do
        {:ok, outcome} -> outcome
        {:exit, _reason} -> %{execution: :error, result: socket.assigns.result, repair: nil}
      end

    outcome =
      if socket.assigns.check_state == :cancelling,
        # Cancellation's boundary is what the page had already observed.
        # A queued completion must not resurrect a verdict after cancel was accepted.
        do: %{outcome | execution: :cancelled, result: socket.assigns.result, repair: nil},
        else: outcome

    {:noreply,
     assign(socket,
       check_run: nil,
       check_state: outcome.execution,
       result: outcome.result || socket.assigns.result,
       repair: outcome.repair
     )}
  end

  def handle_async({:check, _old_id}, _reply, socket), do: {:noreply, socket}

  defp reset_check(socket, report) do
    assign(socket,
      form: to_form(%{"report" => report}),
      result: nil,
      repair: nil,
      error: nil,
      check_state: :idle
    )
  end

  defp start_check(socket, report) do
    id = make_ref()
    owner = self()
    deadline = System.monotonic_time(:millisecond) + socket.assigns.check_timeout_ms
    opts = socket.private.check_options

    socket
    |> assign(check_run: id, check_state: :verifying)
    |> start_async({:check, id}, fn -> CheckRun.run(owner, id, report, deadline, opts) end)
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
          block is checked. Replays with matching recorded inputs are re-executed;
          unavailable evidence is not called false. Nothing here asks you to trust a model.
        </p>
      </section>

      <.form for={@form} id="report-check-form" phx-submit="check" class="space-y-3">
        <.input
          field={@form[:report]}
          type="textarea"
          rows="12"
          readonly={@check_run != nil}
          placeholder="Paste a report, an answer, an essay — markdown, with URNs in it."
          class="textarea textarea-bordered w-full font-mono text-sm"
        />
        <div class="flex items-center gap-3">
          <button id="check-submit" type="submit" class="btn btn-primary" disabled={@check_run != nil}>
            Check
          </button>
          <button
            :if={@check_run != nil}
            id="check-cancel"
            type="button"
            phx-click="cancel"
            class="btn btn-ghost"
            disabled={@check_state == :cancelling}
          >
            Cancel
          </button>
          <span class="text-xs text-base-content/60">
            Runnable in a replay block: {Enum.join(ReplayExecutor.tools(), " · ")}
          </span>
        </div>
      </.form>

      <p class="text-xs text-base-content/60">
        Verification and repair share a {@check_timeout_ms / 1_000}-second execution budget.
        Cancelling stops remaining work, not a claim's truth or falsehood.
      </p>
      <div
        :if={@check_state != :idle}
        id="check-execution"
        data-state={@check_state}
        role="status"
        aria-live="polite"
        class="rounded border border-base-300 p-3 text-sm"
      >
        {execution_message(@check_state, @result)}
      </div>

      <.format_help />

      <div :if={@error} class="alert alert-warning text-sm">{@error}</div>

      <div :if={@result} class="space-y-6">
        <.verdict result={@result} />
        <.foreign found={Map.get(@result, :foreign, [])} />
        <.citations citations={@result.citations} />
        <.replays replays={@result.replays} />
        <.malformed entries={@result.malformed} skipped={@result.skipped} />
        <.unsourced figures={@result.unsourced_figures} />
        <.repair :if={@repair} repair={@repair} />

        <p class="font-mono text-xs text-base-content/50">
          checked against bake {String.slice(@result.checked_identity.bake_id || "none", 0, 12)} · selected release {String.slice(
            @result.checked_identity.release_id || "none",
            0,
            12
          )}
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp execution_message(:verifying, _), do: "Checking report… No verification verdict yet."
  defp execution_message(:repairing, _), do: "Verification finished; preparing suggested repairs…"
  defp execution_message(:cancelling, _), do: "Stopping remaining work…"
  defp execution_message(:completed, _), do: "Check finished. Inspect the evidence verdict below."

  defp execution_message(:busy, nil),
    do: "Report-check capacity is busy. Verification did not start and no verdict was produced."

  defp execution_message(:cancelled, nil),
    do: "Check cancelled before verification finished. No verdict was produced."

  defp execution_message(:cancelled, _),
    do: "Repair cancelled. The completed verification verdict is unchanged."

  defp execution_message(:timed_out, nil),
    do: "Check timed out before verification finished. This is neither a pass nor a refutation."

  defp execution_message(:timed_out, _),
    do: "Repair timed out. The completed verification verdict is unchanged."

  defp execution_message(:error, nil),
    do: "Check could not finish. No verification verdict was produced."

  defp execution_message(:error, _),
    do: "Repair could not finish. The completed verification verdict is unchanged."

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
          beside <code class="text-xs">bake_id</code>
          and <code class="text-xs">release_id</code>.
          Copy both identities from the original response, not from today's selection:
        </p>
        <pre class="overflow-x-auto rounded bg-base-200 p-3 text-xs"><code>{@example}</code></pre>
        <p>
          <code class="text-xs">assert</code>
          names response keys and the values the report claims for them; a dotted path
          reaches into nested maps. Omit it and the call is still re-run, which at least
          proves only that the retrieval executes. A different or unavailable named bake or
          release makes the replay unverifiable, not false. Older records without
          <code class="text-xs">release_id</code>
          still work, but check current values
          without establishing historical index equivalence. Matching ids do not freeze
          historical rows, retrieval code or defaults.
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
    <section
      id="verification-result"
      data-status={@result.status}
      class={[
        "rounded-lg p-4 border",
        @result.status == :verified && "bg-success/10 border-success/30",
        @result.status == :failed && "bg-error/10 border-error/30",
        @result.status in [:incomplete, :no_checkable_evidence] && "bg-warning/10 border-warning/30"
      ]}
    >
      <div class="font-semibold">{@result.summary}</div>
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

  attr :found, :list, required: true

  # Scholars cite the Taishō as `T. 262, 6a23`, not as a URN. Before this the guard saw no
  # citation at all and the screen said nothing was wrong — an absence of findings
  # rendering as a clean bill of health, which is the one thing a checker must never do.
  defp foreign(assigns) do
    ~H"""
    <section :if={@found != []} class="space-y-2">
      <h2 class="font-semibold">Citations in another scheme</h2>
      <p class="text-xs text-base-content/60">
        Recognised and resolved against this corpus before checking. A citation that could
        not be placed is listed rather than dropped — it is checked as nothing otherwise.
      </p>
      <ul class="space-y-1 text-sm">
        <li :for={f <- @found} class="flex flex-wrap items-baseline gap-2">
          <span class={["badge badge-sm", if(f.urn, do: "badge-success", else: "badge-warning")]}>
            {f.scheme}
          </span>
          <code class="text-xs">{f.matched}</code>
          <span :if={f.urn} class="text-base-content/50">→</span>
          <.link
            :if={f.urn}
            navigate={~p"/passage?#{[urn: f.urn]}"}
            class="link link-hover font-mono text-xs"
          >
            {f.urn}
          </.link>
          <span :if={is_nil(f.urn)} class="text-xs text-base-content/70">
            could not be placed in this bake
          </span>
        </li>
      </ul>
    </section>
    """
  end

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
      <h2 class="font-semibold">Retrieval claim checks</h2>
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
          <p class="mt-1 text-xs text-base-content/60">{replay.identity_note}</p>
        </li>
      </ul>
    </section>
    """
  end

  # `unverifiable` gets its own colour and never the failure colour. The corpus changed;
  # the claim is not refuted and it does not pass either, and collapsing those two into one
  # red badge is precisely the mistake `Pramana.Report` was written to avoid.
  defp replay_class(:verified), do: "border-base-300"

  defp replay_class(status) when status in [:unverifiable, :executed, :error],
    do: "border-warning/40 bg-warning/5"

  defp replay_class(_), do: "border-error/40 bg-error/5"

  defp replay_badge(:verified), do: "badge-success"
  defp replay_badge(status) when status in [:unverifiable, :executed, :error], do: "badge-warning"
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

  attr :repair, :map, default: nil

  # Diagnosis serves a reader who checks. This serves the one who does not — and the state
  # vocabulary is what keeps that honest: a repaired document that did not say WHICH
  # citations were rewritten, and which were removed for want of any source, would be a
  # more confident version of the document that came in.
  defp repair(assigns) do
    ~H"""
    <section :if={@repair && @repair.actions != []} class="space-y-2">
      <h2 class="font-semibold">What could be repaired</h2>
      <p class="text-xs text-base-content/60">
        Every change here is a substitution of something the corpus already said — a line's
        own words over a paraphrase of them, or the URN where the quoted text was found.
        Nothing is generated. Where the corpus could not settle it, the citation is left
        alone and named.
      </p>
      <ul class="space-y-1 text-sm">
        <li :for={a <- @repair.actions} class="flex flex-wrap items-baseline gap-2">
          <span class={["badge badge-sm", repair_badge(a.state)]}>{a.state}</span>
          <code class="font-mono text-xs">{a.urn}</code>
          <span class="text-xs text-base-content/50">byte {a.source_offset}</span>
          <span :if={a.detail} class="text-xs text-base-content/70">{a.detail}</span>
        </li>
      </ul>
      <details :if={@repair.repaired?} class="rounded border border-base-300 p-3">
        <summary class="cursor-pointer text-sm font-medium">The repaired text</summary>
        <pre class="mt-2 overflow-x-auto whitespace-pre-wrap text-xs">{@repair.text}</pre>
      </details>
    </section>
    """
  end

  defp repair_badge(:verified), do: "badge-success"
  defp repair_badge(:quote_relaxed), do: "badge-info"
  defp repair_badge(:citation_corrected), do: "badge-info"
  defp repair_badge(:no_sources), do: "badge-error"
  defp repair_badge(_), do: "badge-warning"

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
