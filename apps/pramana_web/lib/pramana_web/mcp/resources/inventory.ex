defmodule PramanaWeb.MCP.Resources.Inventory do
  @moduledoc """
  What is actually in this bake, as an MCP resource.

  Live counts rather than prose, so a model can tell the difference between "the canon
  does not say that" and "that part of the canon is not loaded yet."

  The counting lives in `Pramana.Inventory`; this module is transport only. `pramana_web`
  must not build queries — see the architecture review in `docs/CHECKS.md`.
  """

  # See `PramanaWeb.MCP.Resources.Guide` — the macro generates `name/0` from these
  # options and does not mark it overridable.
  use Anubis.Server.Component,
    type: :resource,
    uri: "pramana://inventory",
    name: "Corpus inventory",
    mime_type: "application/json"

  alias Anubis.Server.Response
  alias Pramana.Inventory

  @impl true
  def description,
    do: "Live counts for the current bake: works, segments, provenance, embedding coverage."

  @impl true
  def read(_params, frame) do
    {:reply, Response.json(Response.resource(), Inventory.snapshot()), frame}
  end
end
