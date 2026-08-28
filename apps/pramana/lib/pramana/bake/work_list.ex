defmodule Pramana.Bake.WorkList do
  @moduledoc """
  The list of **works** to bake, derived from the lockfile's list of **files**.

  Those are not the same list, and the difference is a whole class of silent data loss.
  `Loader.load/2` replaces a work's segments rather than appending to them, so if one
  work arrives as two files and each is baked on its own, the second erases the first
  and nothing anywhere reports it: the text still resolves, still verifies against the
  file it happens to hold, and still reports a plausible length.

  Six CBETA X works do exactly this — X0240, X0367, X0714, X0822, X1568 and X1571 each
  appear in two volume files. The Taishō does not, because CBETA gives its split works
  distinct ids (`T0220a`, `T0220b`), and that is why a bake of 2,471 Taishō works could
  run on a per-file work list and look correct.

  Both bake paths read this module, so `mix pramana.bake --work X0240` and
  `mix pramana.bake_all` cannot disagree about what X0240 is. They have disagreed
  before: the single-work path used a static witness `"T"` from the registry and baked
  an X work as `pramana:cbeta.T:X1508`, which resolves and is wrong.
  """

  alias Pramana.Acquire.Lockfile

  @type entry :: %{
          canon: String.t(),
          number: String.t(),
          work_id: String.t(),
          volumes: [pos_integer()],
          # The paths as the lockfile records them, in the same order as `volumes`.
          # CARRIED, never rebuilt from `canon` and `volume` — see `paths` below.
          paths: [String.t()]
        }

  # THE PATH IS CARRIED, NOT REBUILT.
  #
  # `Acquire.CBETA.work_path/3` reconstructs a path from canon, volume and number, padding
  # the volume to two digits — and the width is a property of the EDITION, not a constant:
  # T, X, J, K, S and M use two (`T01`), while A, P, L and U use three (`A091`). Volumes
  # above 99 survive the mistake by accident; `A091` does not, and two works failed to bake
  # with `:enoent` on a file the lockfile correctly recorded.
  #
  # Parsing `A/A091/A091n1057.xml` into volume 91 and formatting it back is destroying
  # information and then guessing at it. The integer is still carried, because the
  # provenance rules key on it, but the path the file actually has travels alongside.
  #
  # T/T01/T01n0001.xml — canon, volume, work number. The canon is back-referenced so a
  # path can never be read as belonging to a collection its directory does not name.
  @path_pattern ~r{^(?<canon>[A-Z]+)/\k<canon>(?<vol>\d+)/\k<canon>\k<vol>n(?<number>[A-Za-z0-9]+)\.xml$}

  @doc """
  Every work in the lockfile for `source`, optionally restricted to some canons.

  `canon` takes one name or several: `"T"`, or `"K,A,P,L"`. Several because acquisition
  takes several — `mix pramana.acquire_all --canon K,A,P,L,U,S,M` fetches seven
  collections in one download — and a bake that could not be told the same thing would
  need seven runs to load what one run acquired.

  That asymmetry existed for about an hour and was caught by the census: teaching only the
  catalogue about lists made `mix pramana.bake_all --canon K,A,P,L,U,S,M` compare the whole
  string to each canon, match nothing, and report `enqueueing 0 work(s) from 0 file(s)`.
  Loudly, which is the census doing its job — the same shape of defect as an option one
  retriever honours and the other ignores.

  Ordered by canon, then by the volume the work opens in, then by number — printed
  order, so a bake progresses through the edition rather than through a hash table.
  """
  @spec from_lockfile(String.t(), String.t() | nil) :: [entry()]
  def from_lockfile(source, canon \\ nil) do
    {:ok, entry} = Lockfile.get_source(source)

    entry["files"]
    |> Enum.flat_map(&files_from_path/1)
    |> filter_canon(canon)
    |> group_by_work()
  end

  @doc """
  The one work with this id, or `nil` if the lockfile has no file for it.
  """
  @spec find(String.t(), String.t()) :: entry() | nil
  def find(source, work_id) do
    source
    |> from_lockfile(nil)
    |> Enum.find(&(&1.work_id == work_id))
  end

  @doc """
  How many files the lockfile holds against how many works they make.

  The census that catches the defect this module exists to prevent. It has to be taken
  from the SOURCE, before parsing: `mix pramana.verify` re-normalizes the file a text
  records and compares, so a text holding one of its two volumes re-derives from that
  volume and passes. Reproducibility is not fidelity. Files 1,236 against works 1,230
  is what found it.
  """
  @spec census(String.t(), String.t() | nil) :: %{
          files: non_neg_integer(),
          works: non_neg_integer(),
          multi_volume: [entry()]
        }
  def census(source, canon \\ nil) do
    works = from_lockfile(source, canon)

    %{
      files: works |> Enum.map(&length(&1.volumes)) |> Enum.sum(),
      works: length(works),
      multi_volume: Enum.filter(works, &(length(&1.volumes) > 1))
    }
  end

  defp files_from_path(%{"path" => path}) do
    case Regex.named_captures(@path_pattern, path) do
      nil ->
        []

      %{"canon" => canon, "vol" => vol, "number" => number} ->
        [
          %{
            canon: canon,
            volume: String.to_integer(vol),
            number: number,
            work_id: "#{canon}#{number}",
            path: path
          }
        ]
    end
  end

  defp filter_canon(files, nil), do: files

  defp filter_canon(files, canon) when is_binary(canon) do
    case String.split(canon, ",", trim: true) do
      [] ->
        files

      canons ->
        wanted = MapSet.new(canons, &String.trim/1)
        Enum.filter(files, &MapSet.member?(wanted, &1.canon))
    end
  end

  # Volumes sorted ASCENDING, which is printed order for CBETA: a work's later fascicles
  # sit in the later volume. `IR.concat/1` trusts this order and does not re-sort,
  # because printed order is a property of the edition, not of the file names.
  defp group_by_work(files) do
    files
    |> Enum.group_by(& &1.work_id)
    |> Enum.map(fn {work_id, group} ->
      [first | _] = group = Enum.sort_by(group, & &1.volume)

      %{
        canon: first.canon,
        number: first.number,
        work_id: work_id,
        volumes: Enum.map(group, & &1.volume),
        paths: Enum.map(group, & &1.path)
      }
    end)
    |> Enum.sort_by(&{&1.canon, hd(&1.volumes), &1.number})
  end
end
