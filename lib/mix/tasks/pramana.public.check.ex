defmodule Mix.Tasks.Pramana.Public.Check do
  @shortdoc "Says whether this database is safe to expose publicly"

  @moduledoc """
  What a public deployment of *this* database would serve, and under whose licence.

      mix pramana.public.check
      PRAMANA_DATABASE=pramana_public mix pramana.public.check

  A renderer over `Pramana.Publishing.audit/0`, which `mix pramana.public.bake` also runs
  as its final step. One implementation, because two surfaces answering "may we publish
  this" differently is the worst possible place for them to disagree.

  Read-only, and **not a deployment gate on its own**. A database holding restricted text
  is the normal case for local research; this only says you cannot point the public at it.
  """

  use Mix.Task

  alias Pramana.Publishing

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")
    audit = Publishing.audit()

    section("SAFE TO SERVE PUBLICLY", audit.servable)
    section("FORBIDDEN BY LICENCE — a public bake must not contain these", audit.forbidden)
    section("WITHHELD BY UNCERTAINTY — permissively licensed, not confirmed", audit.withheld)

    verdict(audit)
  end

  defp section(title, rows) do
    Mix.shell().info("\n  #{title}\n")

    if rows == [] do
      Mix.shell().info("    (nothing)")
    else
      Enum.each(rows, fn r ->
        Mix.shell().info(
          "    #{String.pad_trailing(r.id, 18)} #{String.pad_leading("#{r.rows}", 7)} row(s)  " <>
            "#{String.pad_trailing(r.spdx || "—", 24)} #{r.name}"
        )
      end)
    end
  end

  defp verdict(%{safe?: true} = audit) do
    Mix.shell().info("""

      ✓ SAFE. Nothing here is forbidden by its licence (#{Publishing.total(audit.servable)} rows servable).
    """)

    unclaimed(audit.withheld)
  end

  defp verdict(audit) do
    all =
      Publishing.total(audit.servable) + Publishing.total(audit.forbidden) +
        Publishing.total(audit.withheld)

    Mix.shell().info("""

      ✗ NOT SAFE TO EXPOSE. #{Publishing.total(audit.forbidden)} of #{all} rows come from #{length(audit.forbidden)} source(s)
        whose licence forbids redistribution.

        This is the normal state for local research and is not a defect. It means a
        public deployment must run against a SEPARATE bake — `mix pramana.public.bake` —
        not against this one behind a query filter. A filter is something a caller can
        forget to pass, and `Corpus.resolve/1` takes no filter at all: a public URN
        endpoint over this database serves every text in it.
    """)

    unclaimed(audit.withheld)
  end

  defp unclaimed([]), do: :ok

  defp unclaimed(withheld) do
    Mix.shell().info("""
        #{Publishing.total(withheld)} further rows carry a permissive licence and are still withheld,
        because the ingest inferred that licence rather than matching it to a publication
        record and stored the safe answer. Nothing legal is blocking those.
    """)
  end
end
