defmodule PramanaWeb.InventoryLive do
  @moduledoc """
  What is in this bake, and what is not — the page a reader should see before searching.

  Someone opening a search box has no way to know whether an empty result means the canon
  is silent or the shelf is short. Every other surface answers that per query, in a note
  attached to results they have already asked for; this answers it once, before they ask.

  `Pramana.Inventory.snapshot/0` supplies every number. Its moduledoc has anticipated this
  page since Phase 3 — *"Phase 8 will want the same numbers for the reader, and a second
  implementation is how two surfaces start disagreeing about what the corpus contains"* —
  so this view computes nothing and simply renders it.

  ## It leads with the gaps, not the totals

  17,061 texts is an impressive number and an uninformative one. **Ten of CBETA's 26
  collections**, and **Taishō volumes 56–84 entirely absent**, is what a reader actually
  needs before deciding whether this corpus can answer their question. The totals are
  underneath.
  """
  use PramanaWeb, :live_view

  alias Pramana.Inventory
  alias Pramana.Provenance

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "What is here", snapshot: Inventory.snapshot())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-1">
        <h1 class="text-xl font-semibold">What is in this bake</h1>
        <p class="text-sm text-base-content/70">
          And what is not — because an empty search result cannot tell you which.
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="font-semibold">Not loaded</h2>

        <div class="alert alert-warning alert-soft text-sm">
          <div class="space-y-2">
            <p>{@snapshot.cbeta_coverage.note}</p>
            <p>{@snapshot.taisho_coverage.note}</p>
            <p :if={@snapshot.tibetan_coverage.note}>{@snapshot.tibetan_coverage.note}</p>
            <p>{@snapshot.parallel_coverage.note}</p>
            <p :if={@snapshot.role_coverage.note}>{@snapshot.role_coverage.note}</p>
          </div>
        </div>

        <details class="text-sm">
          <summary class="cursor-pointer font-medium">
            All {length(@snapshot.cbeta_coverage.missing)} absent CBETA collections
          </summary>
          <ul class="mt-2 space-y-1">
            <li :for={c <- @snapshot.cbeta_coverage.missing} class="flex items-baseline gap-2">
              <span class="w-10 font-mono text-xs">{c.id}</span>
              <span class="w-14 text-right font-mono text-xs">{c.works}</span>
              <span>{c.name}</span>
              <span class="text-base-content/60">{c.name_en}</span>
            </li>
          </ul>
          <p class="mt-2 text-xs text-base-content/60">
            Names are CBETA's own, from <code>canons.json</code>
            at the pinned commit — not expanded from the code, because <code>YP</code>
            reads as 永樂北藏 and is 演培法師全集, while 永樂北藏 is <code>P</code>.
          </p>
        </details>
      </section>

      <section class="space-y-2">
        <h2 class="font-semibold">Loaded</h2>
        <div class="flex flex-wrap gap-6 rounded-lg bg-base-200/40 p-4">
          <.stat label="texts" value={@snapshot.corpus["texts"]} />
          <.stat label="citable segments" value={@snapshot.corpus["segments"]} />
          <.stat label="characters" value={@snapshot.corpus["chars"]} />
          <.stat label="vectors" value={@snapshot.embedding_coverage.embedded} />
        </div>
        <p class="text-xs text-base-content/60">
          {@snapshot.embedding_coverage.reachable_percent}% of texts are chunked and {@snapshot.embedding_coverage.percent}% of those chunks carry a vector.
          <span :if={@snapshot.embedding_coverage.note}>
            {@snapshot.embedding_coverage.note}
          </span>
        </p>
      </section>

      <div class="grid gap-6 sm:grid-cols-2">
        <.breakdown
          title="Where these texts were composed"
          note="Not what language they are written in — a Chinese-language sūtra translated from an Indic original is Indic-composed."
          rows={@snapshot.by_composition_origin}
          label_fun={&Provenance.origin_label/1}
        />
        <.breakdown
          title="What they are"
          note={
            "Scripture, treatise, commentary, or a text the canon itself marks doubtful — " <>
              "for the #{@snapshot.role_coverage.texts - @snapshot.role_coverage.without_role} texts that carry a role at all."
          }
          rows={@snapshot.by_text_role}
          label_fun={&Provenance.role_label/1}
        />
      </div>

      <section class="space-y-1 text-xs text-base-content/60">
        <p class="font-mono">
          bake {String.slice(@snapshot.bake_id || "", 0, 16)} · pipeline v{@snapshot.pipeline_version}
        </p>
        <p>
          Two bakes with the same id hold byte-identical corpora. Cite it beside a URN and
          the citation is reproducible years later.
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div>
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class="text-2xl font-semibold">{delimit(@value)}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :note, :string, required: true
  attr :rows, :map, required: true
  attr :label_fun, :any, required: true

  defp breakdown(assigns) do
    total = assigns.rows |> Map.values() |> Enum.sum()
    assigns = assign(assigns, total: total)

    ~H"""
    <section class="space-y-2">
      <h2 class="font-semibold">{@title}</h2>
      <p class="text-xs text-base-content/60">{@note}</p>
      <ul class="space-y-1 text-sm">
        <li :for={{key, n} <- Enum.sort_by(@rows, &elem(&1, 1), :desc)} class="flex gap-2">
          <span class="w-16 text-right font-mono text-xs">{delimit(n)}</span>
          <span class="w-12 text-right font-mono text-xs text-base-content/50">
            {percent(n, @total)}
          </span>
          <span>{@label_fun.(key)}</span>
        </li>
      </ul>
    </section>
    """
  end

  defp percent(_n, 0), do: "—"
  defp percent(n, total), do: "#{Float.round(100 * n / total, 1)}%"

  # 12041579 is unreadable and 12,041,579 is not, and this page exists to be read.
  defp delimit(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp delimit(other), do: to_string(other)
end
