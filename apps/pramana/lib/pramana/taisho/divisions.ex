defmodule Pramana.Taisho.Divisions do
  @moduledoc """
  The Taishō divisions (部) and the provenance they determine.

  The Taishō is organised into divisions by **text number**, not by volume, and the
  division is what actually carries provenance: 阿含部 is Indic scripture, 經疏部 is
  Chinese exegesis, 疑似部 is Chinese texts presenting themselves as Indian
  translations.

  ## Where this table comes from

  CBETA's XML carries no classification markup — no `textClass`, no `catRef` — so the
  division cannot be read out of the files. This table was assembled from two
  independent published contents listings and cross-checked against each other, then
  validated against the baked corpus: every division's number range must fall inside
  its stated volume range, and `mix pramana.provenance --check` asserts it.

  That validation matters. A wrong boundary would mislabel a text's origin, and a
  confidently wrong provenance label is the specific failure this project exists to
  prevent — worse than no label at all.

  ## What is deliberately left null

  - **古逸部 (2732–2864)** — Dunhuang-recovered material of mixed and often unknown
    origin. The division tells us where it was *found*, not where it was composed.
  - **事彙部 (2121–2136)** — encyclopedic compilations that do not map cleanly onto a
    single role.

  Leaving these null is the point. `provenance_for_volume/1` already declines to guess
  for Taishō vols 1–55; this is the same discipline at finer resolution.
  """

  alias Pramana.URN.Taisho

  alias Pramana.Cbeta.Byline

  @type division :: %{
          first: pos_integer(),
          last: pos_integer(),
          name: String.t(),
          name_en: String.t(),
          volumes: String.t(),
          composition_origin: String.t() | nil,
          text_role: String.t() | nil
        }

  # {first, last, 部, English, volumes, composition_origin, text_role}
  @divisions [
    {1, 151, "阿含部", "Āgama", "1-2", "indic", "root"},
    {152, 219, "本緣部", "Jātaka and Avadāna", "3-4", "indic", "root"},
    {220, 261, "般若部", "Prajñāpāramitā", "5-8", "indic", "root"},
    {262, 277, "法華部", "Lotus", "9", "indic", "root"},
    {278, 309, "華嚴部", "Avataṃsaka", "9-10", "indic", "root"},
    {310, 373, "寶積部", "Ratnakūṭa", "11-12", "indic", "root"},
    {374, 396, "涅槃部", "Nirvāṇa", "12", "indic", "root"},
    {397, 424, "大集部", "Mahāsaṃnipāta", "13", "indic", "root"},
    {425, 847, "經集部", "Sūtra collection", "14-17", "indic", "root"},
    {848, 1420, "密教部", "Esoteric", "18-21", "indic", "root"},
    {1421, 1504, "律部", "Vinaya", "22-24", "indic", "root"},
    {1505, 1535, "釋經論部", "Indian sūtra commentaries", "25-26", "indic", "commentary"},
    {1536, 1563, "毘曇部", "Abhidharma", "26-29", "indic", "treatise"},
    {1564, 1578, "中觀部", "Madhyamaka", "30", "indic", "treatise"},
    {1579, 1627, "瑜伽部", "Yogācāra", "30-31", "indic", "treatise"},
    {1628, 1692, "論集部", "Treatise collection", "32", "indic", "treatise"},
    {1693, 1803, "經疏部", "Sūtra exegesis", "33-39", "chinese", "commentary"},
    {1804, 1815, "律疏部", "Vinaya exegesis", "40", "chinese", "commentary"},
    {1816, 1850, "論疏部", "Śāstra exegesis", "40-44", "chinese", "subcommentary"},
    {1851, 2025, "諸宗部", "Sectarian works", "44-48", "chinese", "treatise"},
    {2026, 2120, "史傳部", "History and biography", "49-52", "chinese", "history"},
    # Encyclopedic compilations; role does not map cleanly, so it is left null.
    {2121, 2136, "事彙部", "Cyclopedic works", "53-54", "chinese", nil},
    # Non-Buddhist INDIAN works in Chinese translation (Sāṃkhya, Vaiśeṣika).
    {2137, 2144, "外教部", "Non-Buddhist doctrines", "54", "indic", "treatise"},
    {2145, 2184, "目錄部", "Catalogues", "55", "chinese", "catalogue"},
    # CORRECTED 2026-08-30 FROM SAT'S OWN METADATA. This was one row —
    # `{2185, 2700, "續經疏部", ..., "commentary"}` — collapsing three divisions into one and
    # mislabelling **452 of the 510 works** in that range. It was assembled from two published
    # contents listings that agreed with each other and were both wrong here; the third
    # source is SAT's 541 IIIF manifests, each carrying its own 分類, in
    # `raw/sat-iiif/manifests/`.
    #
    # The existing validation could not have caught it: `mix pramana.provenance --check`
    # asserts that a division's number range falls inside its volume range, which a single
    # wrong row spanning 56–83 satisfies perfectly. And none of these works is loaded, so
    # `verify` and `integrity` were green over it — exactly as they were over the 122 works
    # § A4 records, and for the same reason.
    #
    # Caught before the text arrived rather than after, which is the whole argument for
    # fetching metadata first.
    {2185, 2245, "續經疏部", "Sub-commentaries on sūtras", "56-61", "japanese", "subcommentary"},
    {2246, 2295, "續律疏部・續論疏部", "Sub-commentaries on vinaya and śāstra", "62-70", "japanese",
     "subcommentary"},
    # 402 works, the largest division in the Taishō. The doctrinal writings of the Japanese
    # schools — Shingon, Tendai, Nichiren, Zen — which are compositions in their own right
    # and not commentary on anything, whatever the old row said.
    {2296, 2700, "續諸宗部", "Writings of the Japanese schools", "70-84", "japanese", "treatise"},
    {2701, 2731, "悉曇部", "Siddhaṃ script", "84", "japanese", "treatise"},
    # Recovered at Dunhuang. Found there; composed who knows where. Left null.
    {2732, 2864, "古逸部", "Recovered lost works", "85", nil, nil},
    # Chinese compositions PRESENTING as Indian translations. The whole reason the
    # provenance model has more than one axis.
    {2865, 2920, "疑似部", "Apocrypha", "85", "chinese", "apocryphon"}
  ]

  @doc "All divisions, in canonical order."
  @spec all() :: [division()]
  def all, do: Enum.map(@divisions, &to_map/1)

  @doc """
  The division containing a Taishō text number.

  Accepts the number as an integer or as the string form CBETA uses, which may carry a
  letter suffix (`"0220a"`, `"1969A"`) for works split across volumes. The suffix is
  part of the work id, not the number, so it is stripped for lookup.
  """
  @spec for_number(pos_integer() | String.t()) :: {:ok, division()} | {:error, :out_of_range}
  def for_number(number) when is_binary(number) do
    case Integer.parse(number) do
      {n, _suffix} -> for_number(n)
      :error -> {:error, :out_of_range}
    end
  end

  def for_number(n) when is_integer(n) do
    case Enum.find(@divisions, fn {first, last, _, _, _, _, _} -> n >= first and n <= last end) do
      nil -> {:error, :out_of_range}
      division -> {:ok, to_map(division)}
    end
  end

  @doc """
  Provenance attributes for a Taishō work number.

  Returns only what the division determines. Fields the division cannot settle are
  absent rather than guessed.
  """
  @spec provenance_for_number(pos_integer() | String.t()) :: map()
  def provenance_for_number(number) do
    case for_number(number) do
      {:ok, d} ->
        %{
          division: d.name,
          division_en: d.name_en,
          composition_origin: d.composition_origin,
          text_role: d.text_role
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      {:error, _} ->
        %{}
    end
  end

  @doc """
  Provenance for a pipeline target, so the BAKE assigns provenance rather than a
  separate pass doing it afterwards.

  That ordering matters. When the loader replaces work attributes on re-bake, a bake
  that computed weaker provenance than a later backfill would silently undo it. Having
  one source of truth — the division table — makes a re-bake converge instead.

  Falls back to the volume rule for anything outside the Taishō numbering.
  """
  @spec provenance_for_target(map()) :: map()
  def provenance_for_target(%{canon: "T", number: number} = target) do
    case provenance_for_number(number) do
      empty when map_size(empty) == 0 -> volume_fallback(target)
      attrs -> attrs
    end
  end

  # NOT the Taishō, so the 部 table cannot speak. CBETA holds 26 collections and this
  # table describes exactly one of them; X alone is 1,236 works. Falling through to the
  # volume rule here gives them nothing, because that rule is Taishō volume numbering too.
  #
  # So the work's own byline is asked instead — `唐 王勃撰` is composed, `後秦 佛陀耶舍…譯`
  # is translated — which broadly agrees with this table on the Taishō, where both can be
  # compared. **The agreement rate is computed by `Pramana.Coherence.byline_division/0`, not
  # written down here**: this comment quoted 97.3% for two phases and nothing re-checked it;
  # recomputed it is 95.8%, and the gap is the point of the check rather than a defect.
  #
  # The disagreements are structural rather than noise, and both classes are informative:
  #
  #   - `日本 永超集` (T2183) — the byline says Japanese and the table says Chinese, because
  #     the Japanese-composed catalogues sit in 目錄部, a division the table types as Chinese.
  #     Here the byline is more specific than the division.
  #   - `唐 三藏法師義淨奉詔譯` (T2897) — the byline says translated and the table says
  #     Chinese, because the work is in 疑似部, the DOUBTFUL division. A Chinese composition
  #     carrying a translator's byline is what 疑似部 means, so the table is right and the
  #     byline is the forgery it was written to be.
  #
  # See `Pramana.Cbeta.Byline`.
  #
  # The order matters and is deliberate: for the Taishō the curated table WINS, because it
  # is work-number-precise where the byline is a per-work inference, and a disagreement
  # between them is a question for a scholar rather than something to settle by whichever
  # rule happens to run last.
  def provenance_for_target(%{author: author} = target) when is_binary(author) do
    case Byline.provenance(author) do
      empty when map_size(empty) == 0 -> taisho_only_fallback(target)
      attrs -> attrs
    end
  end

  def provenance_for_target(target), do: taisho_only_fallback(target)

  # THE VOLUME RULE IS TAISHŌ VOLUME NUMBERING, AND ONLY THE TAISHŌ IS NUMBERED THAT WAY.
  #
  # This fell through to `volume_fallback/1` for every collection, and Taishō volumes 56–84
  # are the Japanese sectarian corpus — so **122 X works whose byline verb this rule does
  # not recognise were labelled `japanese`, with `text_role: commentary` alongside it**.
  # 淨土晨鐘 (清 周克復纂), 淨土資糧全集 (明 袾宏校正), 十不二門指要鈔詳解: Ming and Qing
  # authors from Zhejiang and Jiangsu, presented as Japanese-composed. That is invariant #4
  # running backwards, and it is the same family as the two-digit volume width — a Taishō
  # constant applied where Taishō numbering does not hold (rule 41).
  #
  # It hid because it produces a PLAUSIBLE label in the one collection that genuinely is
  # part-Japanese: the 卍續藏 is published in Kyoto and its header reads 卍新纂大日本續藏經.
  # Nothing in the corpus contradicted it until a translator's birthplace became resolvable
  # and could be set against the origin of what they wrote.
  #
  # An unlabelled work is a smaller problem than a mislabelled one — which this module
  # already says about `text_role` and did not honour here. Non-Taishō collections whose
  # byline is silent now get nothing.
  defp taisho_only_fallback(%{canon: "T"} = target), do: volume_fallback(target)
  defp taisho_only_fallback(_target), do: %{}

  defp volume_fallback(%{volume: volume}) when is_integer(volume) do
    case Taisho.provenance_for_volume(volume) do
      {:ok, attrs} -> attrs |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
      {:error, _} -> %{}
    end
  end

  defp volume_fallback(_), do: %{}

  @doc """
  Checks that every division's numbers fall within its stated volumes, given observed
  `{number, volume}` pairs from the corpus.

  Guards against a transcription error in the table above silently mislabelling a
  swathe of the canon.
  """
  @spec check_against(Enumerable.t()) :: {:ok, non_neg_integer()} | {:error, [map()]}
  def check_against(observed) do
    problems = Enum.flat_map(observed, fn {number, volume} -> check_one(number, volume) end)

    if problems == [], do: {:ok, Enum.count(observed)}, else: {:error, problems}
  end

  defp check_one(number, volume) do
    case for_number(number) do
      {:error, _} -> [%{number: number, volume: volume, problem: :no_division}]
      {:ok, d} -> check_volume(d, number, volume)
    end
  end

  defp check_volume(division, number, volume) do
    {lo, hi} = volume_range(division.volumes)

    if volume >= lo and volume <= hi,
      do: [],
      else: [
        %{number: number, volume: volume, division: division.name, expected: division.volumes}
      ]
  end

  defp volume_range(volumes) do
    case String.split(volumes, "-") do
      [single] -> {String.to_integer(single), String.to_integer(single)}
      [lo, hi] -> {String.to_integer(lo), String.to_integer(hi)}
    end
  end

  defp to_map({first, last, name, name_en, volumes, origin, role}) do
    %{
      first: first,
      last: last,
      name: name,
      name_en: name_en,
      volumes: volumes,
      composition_origin: origin,
      text_role: role
    }
  end
end
