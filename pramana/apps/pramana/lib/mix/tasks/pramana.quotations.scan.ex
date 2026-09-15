defmodule Mix.Tasks.Pramana.Quotations.Scan do
  @shortdoc "Finds verbatim text reuse across works and stores the quotation graph"

  @moduledoc """
  Runs the Rust scanner over the corpus and stores what it finds.

      mix pramana.quotations.scan --division 阿含部
      mix pramana.quotations.scan --source cbeta --min-length 25
      mix pramana.quotations.scan --dry-run

  Build the scanner first:

      cd native/quotations && cargo build --release

  ## Why a port and not a NIF

  85.9M characters of Literary Chinese is a working set over a gigabyte, and a NIF
  holding that inside the BEAM would put a large allocation and a long CPU-bound loop
  inside a scheduler built for neither (`docs/ELIXIR.md`, exception 2). It runs once per
  bake, so a process boundary costs nothing and buys isolation.

  Text goes out as JSONL and matches come back as JSONL — the same shape as the
  embedding round trip, which has already proved the pattern. Postgres stays on this
  side, in one language.

  ## Scope it before running it whole

  Reuse is quadratic in the works compared, so `--division` exists to get an answer, and
  a cost, before committing to the canon. 阿含部 is the honest first target: 155 works
  that share stock passages, so a scan that finds nothing there is broken rather than
  merely unlucky.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Quotations
  alias Pramana.Repo

  @switches [
    division: :string,
    source: :string,
    min_length: :integer,
    dry_run: :boolean,
    work: :string
  ]

  @binary "native/quotations/target/release/pramana-quotations"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    do_run(argv)
  catch
    :done -> :ok
  end

  defp do_run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    # Absolute: `System.cmd/3` resolves a bare name against PATH and does NOT resolve a
    # relative path, so "native/..." fails with :enoent even though File.exists? just
    # said otherwise.
    binary = Pramana.Paths.project(@binary)

    unless File.exists?(binary) do
      Mix.raise("scanner not built — run: cd native/quotations && cargo build --release")
    end

    if path = opts[:from] do
      Mix.shell().info("loading matches from #{path}")
      matches = path |> File.stream!() |> Stream.map(&Jason.decode!/1) |> Enum.to_list()
      {:ok, result} = Quotations.store(matches, bake_id: Pramana.Bake.current_id())
      report(result, 0)
      exit_normally()
    end

    texts = texts(opts)
    if texts == [], do: Mix.raise("no texts matched")

    chars = texts |> Enum.map(&String.length(&1.body)) |> Enum.sum()
    Mix.shell().info("scanning #{length(texts)} text(s), #{chars} characters")

    min_length = Keyword.get(opts, :min_length, 20)
    started = System.monotonic_time(:millisecond)
    matches = scan(binary, texts, min_length)
    elapsed = div(System.monotonic_time(:millisecond) - started, 1000)

    Mix.shell().info("  scanner returned #{length(matches)} match(es) in #{elapsed}s")

    if opts[:dry_run] do
      preview(matches)
    else
      {:ok, result} = Quotations.store(matches, bake_id: Pramana.Bake.current_id())
      report(result, elapsed)
    end
  end

  defp exit_normally, do: throw(:done)

  defp texts(opts) do
    from(t in Text, select: %{id: t.id, work_id: t.work_id, body: t.body})
    |> then(fn q ->
      if opts[:source], do: where(q, [t], t.source_id == ^opts[:source]), else: q
    end)
    |> then(fn q -> if opts[:work], do: where(q, [t], t.work_id == ^opts[:work]), else: q end)
    |> then(fn q ->
      if opts[:division] do
        join(q, :inner, [t], w in Work, on: w.id == t.work_id)
        |> where([t, w], w.division == ^opts[:division])
      else
        q
      end
    end)
    |> Repo.all()
    |> Enum.reject(&(&1.body in [nil, ""]))
  end

  # The scanner is keyed by TEXT id, not work id: offsets are into `texts.body`, and a
  # work with two witnesses has two bodies whose offsets mean different things.
  #
  # Files rather than pipes. `System.cmd/3` has no stdin option, the payload runs to
  # hundreds of megabytes, and a file left behind can be inspected when a run surprises
  # you — the same reasoning as the embedding round trip.
  defp scan(binary, texts, min_length) do
    dir = Path.join(System.tmp_dir!(), "pramana-quotations")
    File.mkdir_p!(dir)
    input_path = Path.join(dir, "corpus.jsonl")
    output_path = Path.join(dir, "matches.jsonl")

    File.write!(
      input_path,
      Enum.map_join(texts, "\n", fn t ->
        Jason.encode!(%{work: Integer.to_string(t.id), text: t.body})
      end)
    )

    args = [Integer.to_string(min_length), input_path, output_path]

    case System.cmd(binary, args, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        output_path |> File.stream!() |> Enum.map(&Jason.decode!/1)

      {_, code} ->
        Mix.raise("scanner exited #{code} — input left at #{input_path}")
    end
  end

  defp preview(matches) do
    Mix.shell().info("\n  DRY RUN — longest matches:\n")

    matches
    |> Enum.sort_by(& &1["length"], :desc)
    |> Enum.take(5)
    |> Enum.each(fn m ->
      Mix.shell().info("    #{m["length"]} chars: #{String.slice(m["text"], 0, 60)}")
    end)
  end

  defp report(result, elapsed) do
    stats = Quotations.stats()

    Mix.shell().info("""

    quotation graph
      matches found:      #{result.total}
      stored:             #{result.written}
      unresolvable:       #{result.unresolved}  (character range did not map to segments)
      elapsed:            #{elapsed}s

      graph total:        #{stats.quotations} quotation(s)
      longest:            #{stats.longest} characters
    """)
  end
end
