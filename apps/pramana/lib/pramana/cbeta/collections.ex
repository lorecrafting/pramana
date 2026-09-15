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

  **The names come from CBETA, not from us.** `canons.json` sits at the repository root at
  the same pin and names every collection in Chinese and English; each acquired collection
  also states its own name in every file's `<sourceDesc>`, and the two agree.

  For a while this table carried names for the three acquired collections and a bare code
  for the other 23, on the principle that a plausible expansion of a two-letter code is a
  guess a reader cannot tell from a fact. That was right, and `canons.json` proves it —
  the guesses would have been **wrong**. `GA` is 中國佛寺史志彙刊, not a monastery archive;
  and `YP` is 演培法師全集, a modern monk's collected works, while 永樂北藏 — the Ming
  imperial canon anyone would read `YP` as — is `P`. Naming those from their codes would
  have swapped a 20th-century author with a 15th-century canon, in a corpus whose entire
  purpose is telling those apart.

  `canons.json` also names three collections the repository ships no XML for at this pin —
  Q, R and Z. They are absent from the table below, which lists what is actually there.
  """

  @pin "2b8ab8d5e4fe957a9b94f2cde01cb0d2e2dcd2b9"

  # id, works, name — every name from CBETA's own `canons.json` at the pin below, never
  # from inference. The three collections `canons.json` names but ships no XML for at
  # this commit — Q, R and Z — are absent here for the same reason: this table lists
  # what the repository actually contains.
  @collections [
    %{id: "T", works: 2471, name: "大正新脩大藏經", name_en: "Taishō Tripiṭaka"},
    %{id: "X", works: 1236, name: "卍新纂大日本續藏經", name_en: "Manji Shinsan Dainihon Zokuzōkyō"},
    %{id: "J", works: 287, name: "嘉興大藏經（新文豐版）", name_en: "Jiaxing Canon (Shinwenfeng Edition)"},
    %{id: "B", works: 204, name: "大藏經補編", name_en: "Supplement to the Dazangjing"},
    %{
      id: "ZW",
      works: 202,
      name: "藏外佛教文獻",
      name_en: "Buddhist Texts not contained in the Tripiṭaka"
    },
    %{
      id: "I",
      works: 101,
      name: "北朝佛教石刻拓片百品",
      name_en: "Selections of Buddhist Stone Rubbings from the Northern Dynasties"
    },
    %{
      id: "N",
      works: 83,
      name: "漢譯南傳大藏經（元亨寺版）",
      name_en: "Chinese Translation of the Pāḷi Tipiṭaka (Yuan Heng Temple Edition)"
    },
    %{
      id: "D",
      works: 64,
      name: "國家圖書館善本佛典",
      name_en: "Selections from the Taipei National Central Library Buddhist Rare Book Collection"
    },
    %{id: "G", works: 60, name: "佛教大藏經", name_en: "Fojiao Canon"},
    %{id: "GA", works: 58, name: "中國佛寺史志彙刊", name_en: "Zhongguo Fosi Shizhi Huikan"},
    %{
      id: "Y",
      works: 44,
      name: "印順法師佛學著作集",
      name_en: "Corpus of Venerable Yin Shun's Buddhist Studies"
    },
    %{
      id: "TX",
      works: 40,
      name: "太虛大師全書",
      name_en: "Corpus of Venerable Tai Xu's Buddhist Studies"
    },
    %{id: "F", works: 27, name: "房山石經", name_en: "Fangshan shijing"},
    %{
      id: "L",
      works: 26,
      name: "乾隆大藏經（新文豐版）",
      name_en: "Qianlong Edition of the Canon (Shinwenfeng Edition)"
    },
    %{id: "YP", works: 25, name: "演培法師全集", name_en: "The Complete Works of Venerable Yen Pei"},
    %{id: "P", works: 20, name: "永樂北藏", name_en: "Northern Yongle Edition of the Canon"},
    %{id: "A", works: 12, name: "趙城金藏", name_en: "Jin Edition of the Canon"},
    %{
      id: "C",
      works: 12,
      name: "中華大藏經（中華書局版）",
      name_en: "Zhonghua Canon (Chunghwa Book Edition)"
    },
    %{
      id: "K",
      works: 10,
      name: "高麗大藏經（新文豐版）",
      name_en: "Tripiṭaka Koreana (Shinwenfeng Edition)"
    },
    %{id: "LC", works: 8, name: "呂澂佛學著作集", name_en: "Corpus of Lü Cheng's Buddhist Studies"},
    %{id: "CC", works: 6, name: "CBETA 選集", name_en: "CBETA Selected Collection"},
    %{id: "U", works: 3, name: "洪武南藏", name_en: "Southern Hongwu Edition of the Canon"},
    %{id: "GB", works: 2, name: "中國佛寺志叢刊", name_en: "Zhongguo fosizhi congkan"},
    %{id: "S", works: 2, name: "宋藏遺珍（新文豐版）", name_en: "Songzang yizhen (Shinwenfeng Edition)"},
    %{id: "M", works: 1, name: "卍正藏經（新文豐版）", name_en: "Manji Daizōkyō (Shinwenfeng Edition)"},
    %{
      id: "ZS",
      works: 1,
      name: "正史佛教資料類編",
      name_en: "Passages concerning Buddhism from the Official Histories"
    }
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

  # HOW WIDE THE VOLUME NUMBER IS, PER COLLECTION — and it is not a constant.
  #
  # `T09`, `X25`, `J31` are two digits; `A091`, `P154`, `L130`, `U205` are three. The
  # width is a property of the edition, which `Pramana.Bake.WorkList` learned the hard way
  # when two works failed to bake with `:enoent` on a path rebuilt as `A91`.
  #
  # These eleven are the collections held, and each was checked TWICE against CBETA rather
  # than reasoned about: the acquired directory name (`raw/cbeta/A/A091/A091n1057.xml`) and
  # the `id` attribute CBETA's own reader puts on the line — fetched from
  # `cbdata.dila.edu.tw/stable/juans`, which returns the same HTML the website renders.
  #
  # N was added on 2026-08-28 and the test below is why it was not forgotten: acquiring the
  # collection turned `mix test` red with "N is acquired but has no verified volume width,
  # so its lineheads will be nil". The guard was written the day before, against a lockfile
  # that had no N in it, and it caught the first collection to arrive after it. Checked as
  # the others were — `raw/cbeta/N/N13/...` and `N13n0006_p0001a01` from the rendered juan.
  #
  # I, F, GA, GB and ZS arrived the same day and the guard caught all five together.
  # **GA and GB are three digits** where their neighbours are two — `GA000na001` — which is
  # exactly the assumption that made `A091` wrong, waiting in a different collection.
  #
  # ZS is worth a note it does not need a table entry for: its pages are ALPHABETIC —
  # `ZS01n0001_pa001a01`, not `_p0001a01`. The volume token is unaffected, but anything
  # that parses a page number from a linehead will meet this.
  #
  # **CBETA's catalogue disagrees with CBETA's reader, and the reader is what we want.**
  # `works?work=M1540` reports `vol: "M059"`, while the line in the rendered juan is
  # `M59n1540_p0789b01` and the file is `M/M59/M59n1540.xml`. A width table built from the
  # catalogue field would have produced `M059n1540_p0789b01`, which is not a citation
  # anything can resolve. Checking against the artefact a reader actually sees, rather
  # than against a metadata field describing it, is the same rule that made a text's own
  # byline beat the volume table for provenance.
  #
  # The other 16 collections are ABSENT rather than guessed. We hold none of them, so
  # there is no page to check a guess against, and a linehead is a citation — the one
  # thing invariant #2 says must never be invented.
  @volume_width %{
    "T" => 2,
    "X" => 2,
    "J" => 2,
    "K" => 2,
    "S" => 2,
    "M" => 2,
    "N" => 2,
    "I" => 2,
    "F" => 2,
    "ZS" => 2,
    "GA" => 3,
    "GB" => 3,
    "A" => 3,
    "P" => 3,
    "L" => 3,
    "U" => 3
  }

  @doc """
  CBETA's own volume token for a collection and volume — `"A091"`, `"T09"` — or `nil`.

  `nil` for a collection whose width has not been checked against a real CBETA page, and
  for a volume that is not a positive integer. A volume-spanning work records its range
  (`"130-133"`) on the text, and a range is not a coordinate: every printed reference is
  to one volume, so the caller must supply the volume the cited *line* was printed in.
  """
  @spec volume_token(String.t(), integer() | String.t()) :: String.t() | nil
  # `volume >= 0`, NOT `> 0`. Three of the collections acquired on 2026-08-28 number their
  # first volume ZERO — `I00`, `GA000`, `GB000` — and the guard here said `> 0` because a
  # volume being at least 1 is the kind of assumption nobody checks. It is the same shape as
  # the two-digit width: a property of an edition, asserted rather than read, and refuted by
  # the next edition to arrive.
  def volume_token(canon, volume) when is_binary(canon) and is_integer(volume) and volume >= 0 do
    case Map.fetch(@volume_width, canon) do
      {:ok, width} -> canon <> String.pad_leading(Integer.to_string(volume), width, "0")
      :error -> nil
    end
  end

  def volume_token(canon, volume) when is_binary(canon) and is_binary(volume) do
    case Integer.parse(volume) do
      {n, ""} -> volume_token(canon, n)
      _ -> nil
    end
  end

  def volume_token(_canon, _volume), do: nil

  @doc "The collections whose volume token is known well enough to build a citation from."
  @spec volume_token_known() :: [String.t()]
  def volume_token_known, do: @volume_width |> Map.keys() |> Enum.sort()
end
