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

  @type person :: %{id: String.t(), names: [String.t()], dynasty: String.t() | nil}
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
        if String.contains?(byline, dynasty),
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
          end
      }
    end)
  end
end
