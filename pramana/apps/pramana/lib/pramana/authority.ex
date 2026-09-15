defmodule Pramana.Authority do
  @moduledoc """
  Resolves a CBETA byline to a DILA authority person — 求那跋陀羅 to `A000636`.

  `works.attributed_author` is a byline string as the edition printed it: `劉宋 求那跋陀羅譯`,
  `唐 義淨譯`, `明 宗泐．如𡬶同註`. That is what the witness says, and it is deliberately
  stored verbatim — but it is not an identity. The same translator appears with different
  characters across editions, and two people share a name in different centuries.

  Linking it to DILA's authority id gives what a byline cannot: **one identity across
  spellings**, alternative names, dates, and a stable external reference. That is the join
  `docs/ROADMAP.md` Phase 6 needs for *"how Kumārajīva vs Xuanzang rendered this term"* —
  the question is meaningless until you can say which works are by the same hand.

  ## The rule, and what it refuses

  A byline matches when it **contains** an authority name of two or more characters, longest
  first. Where that name belongs to several people, the **dynasty** decides: CBETA bylines
  open with one and DILA records carry one, so `宋 道隆述` resolves to the Song 道隆 and not
  to any other.

  Measured over the corpus's 1,944 distinct bylines:

      name_and_dynasty                  986
      name_match_no_dynasty              46   → 1,032 linked, 53.1%
      refused                           912

  **This said 74% for an hour and the number was wrong.** The first version checked the
  dynasty only when a name was ambiguous, on the reasoning that a single candidate needs no
  disambiguation — so `宋 道隆述` linked to a Tang 道隆, which is precisely the
  coincidence-of-characters case this exists to refuse. Whether a name is ambiguous says
  nothing about whether the match is right. Checking the dynasty on every branch costs 21
  points of coverage and buys back the meaning of the number. A unit test caught it before
  it shipped; the measurement script had not.

  **A refusal is the common outcome here and that is correct.** 912 bylines name someone the
  authority does not record under that spelling, name several people, or carry a dynasty no
  namesake shares. `confidence` and `method` travel with every link so the difference
  between the two rules survives into an answer, as invariant #5 requires.

  ## It links a byline, not a work

  Two works with the same byline get the same link, and a work with several people in its
  byline — `明 宗泐．如𡬶同註` — resolves to the first name matched, not to both. Multiple
  attribution is real and this does not model it. See `link_byline/2`.
  """

  # DYNASTY NAMES ARE SYNONYMS ACROSS THE TWO SOURCES, and asserting they would match cost
  # the most important links in the corpus. CBETA writes 姚秦 where DILA writes 後秦 — the
  # same Later Qin, named for its ruling Yao family rather than by sequence — and 吳 where
  # DILA writes 孫吳. Before this, 竺佛念, 瞿曇僧伽提婆, 天息災 and 維祇難 were all refused:
  # four of the translators the corpus most depends on.
  #
  # Each pair below is one dynasty under two conventional names. Nothing here maps two
  # DIFFERENT dynasties together, which is the mistake that would silently merge people.
  @dynasty_synonyms %{
    "姚秦" => "後秦",
    "苻秦" => "前秦",
    "孫吳" => "吳",
    "東吳" => "吳",
    "蕭齊" => "南齊",
    "元魏" => "北魏",
    "後魏" => "北魏",
    "拓跋魏" => "北魏",
    "高齊" => "北齊",
    "宇文周" => "北周",
    "曹魏" => "魏"
  }

  import Ecto.Query

  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityPlace
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  @type relation :: %{type: String.t(), person_id: String.t(), name: String.t() | nil}

  # DATES ARE RANGES, AND THE WIDTH IS THE UNCERTAINTY. DILA writes
  # `<birth> +0383-01-01 ~ +0383-12-31 </birth>` for "sometime in 383", and
  # `+0442-01-28 ~ +0443-02-15` for a death whose lunar date crosses a Julian year. Storing
  # one year would discard the thing the range is there to say, which is the same reason
  # `attribution_confidence` sits beside `attributed_author` rather than replacing it.
  @type date_range :: %{earliest: Date.t() | nil, latest: Date.t() | nil, note: String.t() | nil}

  @type person :: %{
          id: String.t(),
          names: [String.t()],
          dynasty: String.t() | nil,
          relations: [relation()],
          external_ids: %{String.t() => String.t()},
          birth: date_range() | nil,
          death: date_range() | nil,
          sect: String.t() | nil,
          place_of_origin: String.t() | nil,
          place_id: String.t() | nil,
          active_at: [String.t()],
          monk: boolean() | nil,
          concise: String.t() | nil
        }
  @type link :: %{
          authority_id: String.t(),
          matched_name: String.t(),
          dynasty: String.t() | nil,
          method: String.t(),
          confidence: String.t()
        }

  @doc """
  Builds a lookup from parsed authority records.

  Names shorter than two characters are dropped: a single character appears inside almost
  every byline and would match everything.
  """
  @spec index([person()]) :: map()
  def index(people) when is_list(people) do
    by_name =
      Enum.reduce(people, %{}, fn person, acc ->
        person.names
        |> Enum.filter(&(String.length(&1) >= 2))
        |> Enum.reduce(acc, fn name, inner ->
          Map.update(inner, name, [person.id], &[person.id | &1])
        end)
      end)

    %{
      by_name: by_name,
      # Longest first, so 求那跋陀羅 is tried before any two-character substring of it.
      names: by_name |> Map.keys() |> Enum.sort_by(&String.length/1, :desc),
      people: Map.new(people, &{&1.id, &1})
    }
  end

  @doc """
  Resolves one byline, or `nil` when it cannot be resolved confidently.

  `nil` rather than a best guess. A wrong authority link is worse than none: it merges two
  people into one identity, and every later question about "the same translator" inherits
  the error silently.
  """
  @spec link_byline(String.t() | nil, map()) :: link() | nil
  def link_byline(byline, _index) when byline in [nil, ""], do: nil

  def link_byline(byline, index) do
    case Enum.find(index.names, &String.contains?(byline, &1)) do
      nil -> nil
      name -> resolve(byline, name, Map.fetch!(index.by_name, name), index)
    end
  end

  # A UNIQUE NAME IS STILL CHECKED AGAINST THE DYNASTY. This clause used to return the link
  # unconditionally, on the reasoning that one candidate needs no disambiguation — so
  # `宋 道隆述` linked to a Tang 道隆, which is exactly the coincidence-of-characters case
  # this module exists to refuse. It only refused them when the name happened to be
  # ambiguous, which is unrelated to whether the match is right.
  defp resolve(byline, name, [id], index) do
    case index.people[id].dynasty do
      nil ->
        # The authority states no dynasty, so it cannot disagree. Weaker evidence, and
        # `method` says which rule ran.
        found(id, name, index, "name_match_no_dynasty")

      dynasty ->
        if dynasty_agrees?(byline, dynasty),
          do: found(id, name, index, "name_and_dynasty"),
          else: nil
    end
  end

  defp resolve(byline, name, ids, index) do
    ids
    |> Enum.filter(fn id ->
      dynasty = index.people[id].dynasty
      is_binary(dynasty) and String.contains?(byline, dynasty)
    end)
    |> case do
      [id] ->
        found(id, name, index, "name_and_dynasty")

      # Several people of that name from that dynasty, or none. Both are refusals, and the
      # second is the more informative: a name that matched with no person of that dynasty
      # behind it is usually a coincidence of characters rather than a person.
      _ ->
        nil
    end
  end

  # Agreement, not string equality. Three ways a byline and a record can name one dynasty:
  # verbatim, through a synonym, or as 宋 against 北宋 — where one conventional name
  # contains the other because it distinguishes a period the byline did not bother to.
  defp dynasty_agrees?(byline, dynasty) do
    canonical = Map.get(@dynasty_synonyms, dynasty, dynasty)

    String.contains?(byline, dynasty) or String.contains?(byline, canonical) or
      Enum.any?(byline_dynasties(byline), fn d ->
        canonical == Map.get(@dynasty_synonyms, d, d) or String.contains?(canonical, d)
      end)
  end

  # The leading run of Han characters before the first space is where CBETA puts the
  # dynasty: `姚秦 竺佛念譯`. Bylines that omit it simply produce nothing to compare.
  defp byline_dynasties(byline) do
    byline
    |> String.split(~r/[\s　]+/u, trim: true)
    |> Enum.take(1)
  end

  # `<birth> +0383-01-01 ~ +0383-12-31 <note>依記錄推算。</note> </birth>`
  #
  # Both ends are kept. A range of one day and a range of thirteen months are different
  # claims, and collapsing either to "383" makes them look the same.
  defp date_range(body, element) do
    # `~r/.../` and not `~r{...}`: a `{4}` quantifier closes the brace-delimited sigil early,
    # and the rest of the file uses braces only in patterns that have no quantifiers.
    pattern =
      ~r/<#{element}[^>]*>\s*([+\-]?\d{4}-\d{2}-\d{2})?\s*~?\s*([+\-]?\d{4}-\d{2}-\d{2})?(.*?)<\/#{element}>/s

    case Regex.run(pattern, body) do
      nil ->
        nil

      [_, earliest, latest, rest] ->
        case {parse_date(earliest), parse_date(latest)} do
          {nil, nil} -> nil
          {e, l} -> %{earliest: e, latest: l || e, note: note_text(rest)}
        end
    end
  end

  # `+0383-01-01`. The leading sign is an era marker, not arithmetic: `-` is BCE, which no
  # record here uses but the format allows, and dropping it silently would turn a
  # pre-Common-Era date into a Common-Era one.
  # No `nil` clause: `Regex.run/2` gives `""` for a group that did not participate, never
  # `nil`, so a defensive clause here is unreachable code that dialyzer correctly refuses.
  defp parse_date(""), do: nil

  defp parse_date("-" <> _), do: nil

  defp parse_date(text) do
    case Date.from_iso8601(String.trim_leading(text, "+")) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp note_text(rest) do
    case Regex.run(~r{<note>([^<]+)</note>}, rest) do
      [_, text] -> String.trim(text)
      _ -> nil
    end
  end

  defp note(body, type) do
    case Regex.run(~r{<note type="#{type}">([^<]*)</note>}, body) do
      [_, text] -> text |> String.trim() |> presence()
      _ -> nil
    end
  end

  defp place_name(body) do
    case Regex.run(~r{<note type="placeOfOrigin">\s*<placeName>\s*([^<\s]+)}, body) do
      [_, name] -> presence(String.trim(name))
      _ -> nil
    end
  end

  # `<ref target="…/place/">PL000000055425</ref>` — the id in DILA's place authority, kept
  # so the two databases can be joined without re-matching on a place name.
  defp place_id(body) do
    case Regex.run(~r{<note type="placeOfOrigin">.*?<ref[^>]*>\s*(PL\d+)}s, body) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp presence(""), do: nil
  defp presence(text), do: text

  defp found(id, name, index, method) do
    %{
      authority_id: id,
      matched_name: name,
      dynasty: index.people[id].dynasty,
      method: method,
      # `probable`, never `certain`. The name is certainly present in the byline; that it
      # denotes THIS person rather than a namesake the authority does not record is an
      # inference.
      confidence: "probable"
    }
  end

  @doc """
  Every work attributed to one authority person, with the bylines that named them.

  This is what an identity buys and a byline string cannot: 竺佛念 appears under more than
  one spelling, and asking for "everything by 竺佛念" as text would find one of them.

  The distinct bylines come back alongside the works, because they are the evidence for the
  grouping and a caller may disagree with it. `Pramana.Authority` never claims `certain`.
  """
  @spec works(String.t(), keyword()) :: %{
          authority_id: String.t(),
          works: [map()],
          bylines: [String.t()],
          count: non_neg_integer(),
          returned: non_neg_integer()
        }
  def works(authority_id, opts \\ []) when is_binary(authority_id) do
    rows =
      Repo.all(
        from w in Work,
          where: w.authority_id == ^authority_id,
          order_by: w.id,
          limit: ^Keyword.get(opts, :limit, 100),
          select: %{
            work_id: w.id,
            title: w.title,
            attributed_author: w.attributed_author,
            composition_origin: w.composition_origin,
            text_role: w.text_role,
            method: w.authority_method,
            confidence: w.authority_confidence
          }
      )

    # COUNTED SEPARATELY, NOT `length(rows)`. `rows` is capped by `:limit`, so counting it
    # reports the page size as the total — `count: 3` for a translator with 28 works, which
    # is the coverage-denominator failure (rule 44) inside a single function.
    total = Repo.aggregate(from(w in Work, where: w.authority_id == ^authority_id), :count)

    %{
      authority_id: authority_id,
      works: rows,
      bylines: rows |> Enum.map(& &1.attributed_author) |> Enum.uniq() |> Enum.sort(),
      count: total,
      returned: length(rows)
    }
  end

  @doc """
  The whole record behind an authority id: names, dates, sect, place, external ids, lineage.

  This is the node the rest of the graph hangs from. `works/2` says what one hand produced;
  this says who the hand belonged to, and it is what makes a work's `date_start` legible —
  a bound is only interpretable next to the lifespan it was derived from.

  ## Dates come back as ranges, and the width is the claim

  DILA records a birth as `0602` or as `0602-05-13` or as a span, and flattening those to
  one year throws away the difference between a date known to the day and a date known to
  the century. Both ends of both ranges are returned. `docs/RULES.md` 41 is the reason:
  a lost distinction is not recoverable later by anyone.

  `works.date_start`/`date_end` are derived from these by `mix pramana.authority.link`, and
  carry `date_basis: "authority_lifespan"` so nothing downstream mistakes a lifespan bound
  for a composition date.

  ## `external_ids` is the way out of this corpus

  Wikidata Q-ids for 1,446 of the linked works' people, plus whatever else DILA records.
  They are pass-throughs: nothing here fetches them, and their correctness is DILA's claim,
  not ours.

  Returns `nil` for an id the authority does not define, rather than an empty person — an
  unknown id and a person with no recorded dates are different answers.
  """
  @spec person(String.t()) :: map() | nil
  def person(authority_id) when is_binary(authority_id) do
    case Repo.get(AuthorityPerson, authority_id) do
      nil ->
        nil

      row ->
        %{
          authority_id: row.id,
          name: row.name,
          also_known_as: row.names -- [row.name],
          dynasty: row.dynasty,
          birth: range(row.birth_earliest, row.birth_latest, row.birth_note),
          death: range(row.death_earliest, row.death_latest, row.death_note),
          sect: row.sect,
          place_of_origin: row.place_of_origin,
          place_id: row.place_id,
          place: place_record(row.place_id),
          active_at: row.active_at,
          monk: row.monk,
          summary: row.concise,
          external_ids: row.external_ids,
          source: row.source,
          lineage: lineage(authority_id),
          works_in_bake:
            Repo.aggregate(from(w in Work, where: w.authority_id == ^authority_id), :count)
        }
    end
  end

  # THE STRING AND THE RECORD BOTH, never one instead of the other. `place_of_origin` is
  # what the person authority printed — 沛縣 — and `place` is what the place authority knows
  # about it. They can disagree, because they are two files maintained separately, and
  # collapsing them would hide that from a caller who has every right to prefer the byline's
  # own spelling.
  #
  # `nil` for an id the place file does not define: 22 of the 4,310 places people reference
  # are not in it, and an empty record would read as a place about which nothing is known
  # rather than one that is missing.
  defp place_record(nil), do: nil

  defp place_record(place_id) do
    case Repo.get(AuthorityPlace, place_id) do
      nil ->
        nil

      place ->
        %{
          place_id: place.id,
          name: place.name,
          name_en: place.name_en,
          # The modern administrative path, and the historical unit beside it. `country` is
          # a Tang circuit — 江南東道 — not a modern state, and it is the one a scholar
          # means by "a Jiangnan translator".
          district: place.district,
          district_path: place.district_path,
          historical_region: place.country,
          contained_by: place.region_name,
          # LONGITUDE FIRST in the source, named here so it cannot be misread. `certainty`
          # is DILA's own, and travels with the value.
          lon: place.lon,
          lat: place.lat,
          certainty: place.geo_cert
        }
    end
  end

  # `nil` rather than a range with two nils: "no date recorded" is a statement, and an
  # empty structure reads as a date whose ends happen to be missing.
  defp range(nil, nil, _note), do: nil

  defp range(earliest, latest, note) do
    %{earliest: earliest, latest: latest, note: note, exact: earliest == latest}
  end

  @doc """
  A person's teachers and students, **as DILA states them**.

  Never inferred — not from co-occurrence, not from dates, not from anything. Inferred
  lineage is how a scholarly claim gets manufactured; every row here carries `source` so a
  chain is reportable as *DILA says* rather than as fact.
  """
  @spec lineage(String.t()) :: %{teachers: [map()], students: [map()]}
  def lineage(authority_id) when is_binary(authority_id) do
    rows =
      Repo.all(
        from r in AuthorityRelation,
          where: r.person_id == ^authority_id,
          select: %{type: r.type, id: r.related_id, name: r.related_name, source: r.source}
      )

    %{
      teachers: Enum.filter(rows, &(&1.type == "teacher")),
      students: Enum.filter(rows, &(&1.type == "student"))
    }
  end

  @doc """
  A teacher chain walked upward, oldest ancestor last.

  Stops at `depth`, and stops at a cycle. **A cycle is real data, not a bug**: authority
  editors record what sources say, and sources disagree about who taught whom, so two
  people can each be recorded as the other's teacher. Walking that forever is the failure;
  reporting it is not.

  Where a person has several teachers the chain follows the first and says so in
  `branched`, because a lineage is a graph and a chain is a path through it.
  """
  @spec teacher_chain(String.t(), keyword()) :: %{
          chain: [map()],
          branched: boolean(),
          stopped: atom()
        }
  def teacher_chain(authority_id, opts \\ []) do
    walk_teachers(
      authority_id,
      Keyword.get(opts, :depth, 8),
      MapSet.new([authority_id]),
      [],
      false
    )
  end

  defp walk_teachers(_id, 0, _seen, acc, branched),
    do: %{chain: Enum.reverse(acc), branched: branched, stopped: :depth}

  defp walk_teachers(id, depth, seen, acc, branched) do
    case lineage(id).teachers do
      [] ->
        %{chain: Enum.reverse(acc), branched: branched, stopped: :no_teacher_recorded}

      [next | rest] ->
        if MapSet.member?(seen, next.id) do
          %{chain: Enum.reverse(acc), branched: branched, stopped: :cycle}
        else
          walk_teachers(
            next.id,
            depth - 1,
            MapSet.put(seen, next.id),
            [next | acc],
            branched or rest != []
          )
        end
    end
  end

  @doc """
  Parses DILA's place authority TEI into place records.

  A `place_id` on a person — `PL000000009585` — is opaque without this. What it resolves to
  is not primarily a coordinate but a **region**, in two independent schemes, and both are
  kept because they answer different questions:

  - `district` is the **modern** administrative path, `中國-浙江省-杭州市-下城區`, hyphen
    separated from country down to county. Split into `district_path` as well as kept whole,
    because a path collapsed to a string cannot be grouped by province and a path split into
    parts loses the spelling DILA published.
  - `country` is the **historical** unit — 江南東道, 隴右道, 西突厥. Tang circuits, not modern
    states, and this is the one a scholar wants: "a Jiangnan translator" is a claim about the
    Tang and says nothing about Zhejiang.

  ## `<geo>` is longitude first, and nothing in the file says so

  TEI's own convention for `<geo>` is latitude then longitude. DILA publishes the reverse:
  于闐 reads `79.828 36.9881`, and Khotan is 37.1°N 79.9°E. Read as documented, every place
  in this corpus lands in the Arctic Ocean. `cert` rides on most of them and is stored
  beside the value rather than dropped — a coordinate whose confidence has been discarded is
  a coordinate nobody can argue with.

  ## The tag carries attributes, and matching without them reports absence

  `<geo cert="high">`, not `<geo>`. A pattern written for the bare tag returns a plausible
  number rather than an error — it measured coverage of this field at 0.0% when the true
  figure for the places this corpus cites is 100%. Rule 62.
  """
  @spec parse_places(String.t()) :: [map()]
  def parse_places(xml) when is_binary(xml) do
    ~r{<place xml:id="(PL\d+)"[^>]*>(.*?)</place>\s*(?=<place xml:id="PL|</listPlace>)}s
    |> Regex.scan(xml)
    |> Enum.map(fn [_, id, body] -> place(id, body) end)
  end

  defp place(id, body) do
    names = place_names(body)
    district = tag(body, "district")

    %{
      id: id,
      # The head name is the one without `type="alternative"`; `names` keeps every spelling,
      # which is what makes a place findable under the characters a text actually printed.
      name: List.first(names),
      names: names,
      name_en: lang_name(body, "eng-Latn"),
      district: district,
      district_path: district_path(district),
      country: tag(body, "country"),
      region_id: attr(body, ~r{<place key="(PL[A-Z]\d+)"}),
      region_name: attr(body, ~r{<place key="PL[A-Z]\d+">([^<]+)</place>}),
      note: tag(body, "note")
    }
    |> Map.merge(geo(body))
  end

  defp place_names(body) do
    ~r{<placeName[^>]*>([^<]+)</placeName>}
    |> Regex.scan(body)
    |> Enum.map(fn [_, n] -> String.trim(n) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp lang_name(body, lang) do
    attr(body, ~r{<placeName[^>]*xml:lang="#{lang}"[^>]*>([^<]+)</placeName>})
  end

  # LONGITUDE FIRST. See the moduledoc above; this is the one line where getting it backwards
  # is invisible until someone plots a map of Tang China across the Arctic.
  defp geo(body) do
    case Regex.run(~r{<geo(?:\s+cert="([^"]*)")?[^>]*>\s*([\-\d.]+)\s+([\-\d.]+)\s*</geo>}, body) do
      [_, cert, lon, lat] -> %{lon: to_float(lon), lat: to_float(lat), geo_cert: nilify(cert)}
      _ -> %{lon: nil, lat: nil, geo_cert: nil}
    end
  end

  defp to_float(text) do
    case Float.parse(text) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp nilify(""), do: nil
  defp nilify(value), do: value

  # `中國-浙江省-杭州市-下城區` — country, province, city, county, which is the shape of 4,022
  # of the 4,256 districts this corpus cites.
  #
  # **A semicolon means several regions, not a deeper one.** 257 entries read
  # `中國;蒙古;俄羅斯-遠東聯邦管區…-Sakhalin`, a place spanning modern borders. Splitting those
  # on `-` produces fragments that look exactly like a hierarchy and are not, which is worse
  # than having none — rule 33. Those keep the raw string and an empty path.
  defp district_path(nil), do: []

  defp district_path(text) do
    if String.contains?(text, [";", "；"]) do
      []
    else
      text |> String.split("-", trim: true) |> Enum.map(&String.trim/1)
    end
  end

  defp tag(body, name) do
    attr(body, ~r{<#{name}>([^<]*)</#{name}>}s)
  end

  defp attr(body, pattern) do
    case Regex.run(pattern, body) do
      [_, value] -> value |> String.trim() |> nilify()
      _ -> nil
    end
  end

  @doc """
  Parses DILA's person authority TEI into the shape `index/1` wants.

  Deliberately a plain regex scan rather than a streaming parser: the file is one 49 MB
  document of 49,259 flat `<person>` elements with no nesting to track, and `Saxy` would buy
  nothing here that it buys on a TEI witness.
  """
  @spec parse_people(String.t()) :: [person()]
  def parse_people(xml) when is_binary(xml) do
    ~r{<person xml:id="([^"]+)"[^>]*>(.*?)</person>}s
    |> Regex.scan(xml)
    |> Enum.map(fn [_, id, body] ->
      %{
        id: id,
        names:
          ~r{<persName[^>]*>([^<]+)</persName>}
          |> Regex.scan(body)
          |> Enum.map(fn [_, n] -> String.trim(n) end)
          |> Enum.reject(&(&1 == "")),
        dynasty:
          case Regex.run(~r{<note type="dynasty">\s*([^<\s]+)}, body) do
            [_, d] -> String.trim(d)
            _ -> nil
          end,
        # `<relation type="teacher" active="A000242" n="弘璧"/>` — the lineage, stated by
        # DILA rather than inferred by us. `n` is the name as that record spells it and is
        # kept for display; `active` is the identity and is what a chain is walked on.
        relations:
          ~r{<relation type="([^"]+)" active="([^"]+)"(?: n="([^"]*)")?}
          |> Regex.scan(body)
          |> Enum.map(fn
            [_, type, pid, name] -> %{type: type, person_id: pid, name: name}
            [_, type, pid] -> %{type: type, person_id: pid, name: nil}
          end),
        # `<idno type="Wikidata">Q16906306</idno>`, and CBDB and others alongside it. Kept
        # as a map so a new authority appearing upstream needs no code change here.
        external_ids:
          ~r{<idno type="([^"]+)">([^<]+)</idno>}
          |> Regex.scan(body)
          |> Map.new(fn [_, kind, value] -> {kind, String.trim(value)} end),
        birth: date_range(body, "birth"),
        death: date_range(body, "death"),
        sect: note(body, "sect"),
        place_of_origin: place_name(body),
        place_id: place_id(body),
        # `鄧尉山聖恩寺；天台山華頂；天平白雲古寺` — monasteries, on a full-width semicolon.
        active_at:
          case note(body, "activeAt") do
            nil -> []
            text -> text |> String.split(["；", ";"], trim: true) |> Enum.map(&String.trim/1)
          end,
        monk:
          case note(body, "monk") do
            "是" -> true
            "否" -> false
            _ -> nil
          end,
        concise: note(body, "concise")
      }
    end)
  end
end
