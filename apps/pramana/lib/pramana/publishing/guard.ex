defmodule Pramana.Publishing.Guard do
  @moduledoc """
  Refuses to serve publicly from a database that holds content it may not publish.

  Runs once at boot when `PRAMANA_PUBLIC=1`, and **stops the node** if
  `Pramana.Publishing.audit/0` reports anything forbidden.

  ## Why a boot check and not documentation

  The public artefact is a separate bake into a separate database, which is the real
  protection. What that does not protect against is **one wrong environment variable**: a
  `DATABASE_URL` pointing at the research corpus starts a perfectly healthy node that
  serves CBETA to the public, and nothing anywhere reports it. The bake is careful and the
  deploy is one string.

  So the same audit the bake runs as its last step runs again at boot, against the database
  actually connected rather than the one someone intended. Refusing to start is the only
  outcome that cannot be missed — a log line at 3am is not a safeguard, and degrading to a
  filtered mode would mean trusting every query to remember a filter, which is the thing
  this whole design exists to avoid.

  ## Off by default

  A research node holds restricted text by design and must start normally. This is a
  deliberate declaration that *this* node is public, never a default anyone inherits.
  """

  require Logger

  alias Pramana.Publishing

  @doc """
  A child spec when this node declares itself public, `nil` otherwise.

  `nil` rather than a no-op process, so a research node's supervision tree does not carry
  a child whose purpose is to do nothing.
  """
  @spec child_spec_if_public() :: Supervisor.child_spec() | nil
  def child_spec_if_public do
    if public?() do
      %{id: __MODULE__, start: {__MODULE__, :verify_and_ignore, []}, restart: :temporary}
    end
  end

  @doc "Whether this node declares itself a public deployment."
  @spec public?() :: boolean()
  def public?, do: System.get_env("PRAMANA_PUBLIC") == "1"

  @doc false
  # `:ignore` so the supervisor records no child: the work is the check, and a process
  # that has done its job is not a thing to keep alive or restart.
  @spec verify_and_ignore() :: :ignore
  def verify_and_ignore do
    case verify() do
      :ok ->
        :ignore

      {:error, forbidden} ->
        Logger.emergency("""
        REFUSING TO START. PRAMANA_PUBLIC=1 but this database holds content that may not
        be redistributed:

        #{Enum.map_join(forbidden, "\n", &"  #{&1.id}  #{&1.rows} row(s)  #{&1.spdx}")}

        Almost certainly DATABASE_URL points at a research corpus rather than the one
        `mix pramana.public.bake` produced. Check it before anything else: a node that
        started would have served this.
        """)

        System.stop(1)
        :ignore
    end
  end

  @doc """
  `:ok`, or the forbidden rows that stop this node from serving publicly.

  Separate from the boot path so it can be called, and tested, without stopping anything.
  """
  @spec verify() :: :ok | {:error, [map()]}
  def verify do
    case Publishing.audit() do
      %{safe?: true} -> :ok
      %{forbidden: forbidden} -> {:error, forbidden}
    end
  end
end
