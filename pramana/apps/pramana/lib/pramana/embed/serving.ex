defmodule Pramana.Embed.Serving do
  @moduledoc """
  A long-lived, supervised `Nx.Serving` for embedding queries.

  Loading BGE-M3 costs ~80 seconds and 2.2 GB of RAM, so it must be started once and
  shared — building one per request would make semantic search unusable.

  ## Opt-in, deliberately

  Disabled by default. Tests must never load a 2.2 GB model, and neither should a
  developer who only wants lexical search or is running migrations. Enable with:

      config :pramana, :embedding_serving, true      # or PRAMANA_EMBEDDING=1

  When it is not running, `available?/0` returns false and hybrid retrieval degrades to
  lexical **and says so** in its `retrievers` field. That is the point: an answer built
  on half the intended evidence should announce it rather than look complete.
  """

  @name __MODULE__

  @doc """
  Child spec for the supervision tree, or `nil` when disabled.

  Returns nil rather than a no-op child so the supervisor's children list reflects what
  is actually running.
  """
  @spec child_spec_if_enabled() :: Supervisor.child_spec() | nil
  def child_spec_if_enabled do
    if enabled?() do
      # Preserve Nx.Serving's supervisor identity and shutdown semantics, but do
      # not build a model while the application's child list is being assembled.
      %{id: @name, start: {__MODULE__, :start_link, []}, type: :supervisor}
    end
  end

  @doc false
  @spec start_link() :: Supervisor.on_start()
  def start_link do
    Nx.Serving.start_link(
      serving: Pramana.Embed.build_query_serving([]),
      name: @name,
      batch_timeout: 100
    )
  end

  @doc "Whether the serving is configured to run."
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:pramana, :embedding_serving, false) or
      System.get_env("PRAMANA_EMBEDDING") == "1"
  end

  @doc """
  Whether a serving is actually running right now.

  Checked at call time rather than trusting config: enabling the flag but failing to
  start the model should degrade to lexical, not crash a search.
  """
  @spec available?() :: boolean()
  def available?, do: is_pid(Process.whereis(@name))

  @doc """
  The serving name, for passing as `:serving` — or `nil` when unavailable.

  `Nx.Serving.batched_run/2` accepts the registered name, so callers pass this straight
  through and the retrieval layer's existing "no serving means lexical only" path
  handles the nil case.
  """
  @spec name() :: atom() | nil
  def name, do: if(available?(), do: @name)
end
