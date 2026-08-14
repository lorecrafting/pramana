defmodule Mix.Tasks.Pramana.Provenance do
  @shortdoc "Populates provenance axes from the Taishō division table"

  @moduledoc """
  Backfills `division`, `composition_origin` and `text_role` on works.

      mix pramana.provenance --check    # validate the division table only
      mix pramana.provenance            # validate, then backfill
      mix pramana.provenance --report   # show coverage by origin and role

  The check runs first and refuses to write on failure. A transcription error in the
  division table would mislabel a swathe of the canon, and a confidently wrong
  provenance label is worse than none — so it is validated against the corpus before
  it is trusted.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Taisho.Divisions

  @switches [check: :boolean, report: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    cond do
      opts[:report] ->
        report()

      opts[:check] ->
        check!()

      true ->
        # Sequencing, not a boolean test: check!/0 either raises or returns. Writing
        # this as `check!() && backfill()` implies a falsy branch that cannot happen.
        check!()
        backfill()
    end
  end

  # Every observed {number, volume} pair must sit inside its division's stated volumes.
  defp check! do
    observed =
      Repo.all(
        from t in Text,
          join: w in Work,
          on: w.id == t.work_id,
          where: t.witness_id == "T" and not is_nil(t.volume),
          select: {w.id, t.volume}
      )
      |> Enum.map(fn {work_id, volume} ->
        {String.replace_prefix(work_id, "T", ""), String.to_integer(volume)}
      end)

    case Divisions.check_against(observed) do
      {:ok, n} ->
        Mix.shell().info("division table checks out against #{n} works")
        :ok

      {:error, problems} ->
        for p <- Enum.take(problems, 12), do: Mix.shell().error("  #{inspect(p)}")

        Mix.raise("""
        Division table disagrees with the corpus on #{length(problems)} work(s).

        Refusing to write. A wrong boundary mislabels provenance, which is the exact
        failure this project exists to prevent. Fix Pramana.Taisho.Divisions first.
        """)
    end
  end

  defp backfill do
    works = Repo.all(from w in Work, where: like(w.id, "T%"))
    Mix.shell().info("backfilling #{length(works)} work(s)...")

    {updated, skipped} =
      Enum.reduce(works, {0, 0}, fn work, {up, skip} ->
        number = String.replace_prefix(work.id, "T", "")

        case Divisions.provenance_for_number(number) do
          empty when map_size(empty) == 0 ->
            {up, skip + 1}

          attrs ->
            work
            |> Ecto.Changeset.change(attrs)
            |> Repo.update!()

            {up + 1, skip}
        end
      end)

    Mix.shell().info("updated #{updated}, left unattributed #{skipped}")
    report()
  end

  defp report do
    by_origin =
      Repo.all(
        from w in Work,
          group_by: w.composition_origin,
          select: {w.composition_origin, count(w.id)},
          order_by: [desc: count(w.id)]
      )

    by_role =
      Repo.all(
        from w in Work,
          group_by: w.text_role,
          select: {w.text_role, count(w.id)},
          order_by: [desc: count(w.id)]
      )

    top_divisions =
      Repo.all(
        from w in Work,
          where: not is_nil(w.division),
          group_by: [w.division, w.division_en],
          select: {w.division, w.division_en, count(w.id)},
          order_by: [desc: count(w.id)],
          limit: 8
      )

    Mix.shell().info("\ncomposition_origin:")
    for {k, n} <- by_origin, do: Mix.shell().info("  #{pad(k)} #{n}")

    Mix.shell().info("\ntext_role:")
    for {k, n} <- by_role, do: Mix.shell().info("  #{pad(k)} #{n}")

    Mix.shell().info("\nlargest divisions:")

    for {zh, en, n} <- top_divisions,
        do: Mix.shell().info("  #{String.pad_trailing(zh, 8)} #{pad(en)} #{n}")
  end

  defp pad(nil), do: String.pad_trailing("(unattributed)", 26)
  defp pad(s), do: String.pad_trailing(s, 26)
end
