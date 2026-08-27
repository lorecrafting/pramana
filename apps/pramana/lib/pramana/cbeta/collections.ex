defmodule Pramana.Cbeta.Collections do
  @moduledoc """
  The collections CBETA publishes, and how large each one is.

  CBETA is not one canon. It is **26 collections** under one repository, and holding two
  of them is not "having CBETA" — it is having the Taishō and the 卍續藏 and nothing
  else. A reader who searches for a 嘉興藏 text today gets an empty result, and an empty
  result reads as *the tradition is silent* unless something says otherwise. That is the
  same failure `Pramana.Coverage` exists to prevent for Taishō 56–84, one level up: there
  the gap is volumes inside a collection, here it is whole collections.

  ## Where these numbers come from, and what is deliberately missing

  The work counts are **measured**, not asserted: one recursive git-tree call over the
  pinned CBETA repository at `#{"2b8ab8d5e4fe957a9b94f2cde01cb0d2e2dcd2b9"}` — 5,005 XML
  blobs, the same call `mix pramana.acquire_all` makes — grouped by the collection prefix
  in each path. Rerun it with `Pramana.Acquire.CBETA.Catalog.fetch/2` if the pin moves.

  **Most entries have no name, and that is on purpose.** Each CBETA file states its own
  collection in `<sourceDesc>` — T's files say 大正新脩大藏經, X's say 卍新纂大日本續藏經,
  J's say 嘉興大藏經（新文豐版） — and that is where these names come from. Each arrived
  with its collection, which is the rule working: the name is not written here until the
  files that state it are on disk. For the collections we have not acquired
  there is no such statement on disk, and a plausible expansion of a two-letter code is
  exactly the kind of confident invention this project refuses: a reader told that `YP`
  is some canon cannot tell a sourced fact from a guess. A code and a work count are
  facts. The name arrives with the files.
  """

  @pin "2b8ab8d5e4fe957a9b94f2cde01cb0d2e2dcd2b9"

  # id, works, name — name only where a file on disk states it.
  @collections [
    %{id: "T", works: 2471, name: "大正新脩大藏經"},
    %{id: "X", works: 1236, name: "卍新纂大日本續藏經"},
    %{id: "J", works: 287, name: "嘉興大藏經（新文豐版）"},
    %{id: "B", works: 204, name: nil},
    %{id: "ZW", works: 202, name: nil},
    %{id: "I", works: 101, name: nil},
    %{id: "N", works: 83, name: nil},
    %{id: "D", works: 64, name: nil},
    %{id: "G", works: 60, name: nil},
    %{id: "GA", works: 58, name: nil},
    %{id: "Y", works: 44, name: nil},
    %{id: "TX", works: 40, name: nil},
    %{id: "F", works: 27, name: nil},
    %{id: "L", works: 26, name: nil},
    %{id: "YP", works: 25, name: nil},
    %{id: "P", works: 20, name: nil},
    %{id: "A", works: 12, name: nil},
    %{id: "C", works: 12, name: nil},
    %{id: "K", works: 10, name: nil},
    %{id: "LC", works: 8, name: nil},
    %{id: "CC", works: 6, name: nil},
    %{id: "U", works: 3, name: nil},
    %{id: "GB", works: 2, name: nil},
    %{id: "S", works: 2, name: nil},
    %{id: "M", works: 1, name: nil},
    %{id: "ZS", works: 1, name: nil}
  ]

  @doc "Every collection CBETA publishes at the pinned commit, largest first."
  @spec all() :: [map()]
  def all, do: @collections

  @doc "The commit these counts were measured at."
  @spec pin() :: String.t()
  def pin, do: @pin

  @doc "Total works CBETA publishes across every collection."
  @spec total_works() :: pos_integer()
  def total_works, do: Enum.sum(Enum.map(@collections, & &1.works))

  @doc "One collection by its id, or `nil`."
  @spec get(String.t()) :: map() | nil
  def get(id), do: Enum.find(@collections, &(&1.id == id))
end
