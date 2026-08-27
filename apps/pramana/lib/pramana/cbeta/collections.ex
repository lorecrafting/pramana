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
end
