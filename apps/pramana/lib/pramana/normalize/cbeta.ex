defmodule Pramana.Normalize.CBETA do
  @moduledoc """
  Streaming Saxy handler converting CBETA TEI P5 into `Pramana.Normalize.IR`.

  Streaming, not DOM: a bake touches thousands of files concurrently and some are
  large, so documents are never loaded whole (`CLAUDE.md`, working conventions).

  ## What survives, and why

  | Element | Handling |
  |---|---|
  | `<lb n="0001a05"/>` | **The citation.** Becomes the line anchor. Losing these loses citability. |
  | `<milestone unit="juan"/>` | Fascicle boundaries |
  | `<lg>`/`<l>` | Marks lines as verse rather than prose |
  | `<app><lem/><rdg/></app>` | Only `<lem>` (the base-text reading) enters the running text; every `<rdg>` variant is recorded in the apparatus |
  | `<note>` | Captured separately, never mixed into body text |
  | `<g ref="#CB00006"/>` | Resolved through the header's `<charDecl>` to a real Unicode codepoint |
  | `<cb:mulu>`, `<cb:docNumber>` | Navigation apparatus, excluded from body text |

  ## Real structures this handler is built around

  Discovered by running against T0262 rather than assumed. All three broke a simpler
  single-buffer design:

  1. **`<app>` nests inside `<lem>`.** Apparatus state is therefore a stack, and every
     level is recorded — a nested variant is still a real variant.
  2. **`<note>` appears inside `<lem>`.** Note text must reach neither the body nor the
     lemma.
  3. **`<lem>` spans `<lb/>`** (`後秦龜茲國三藏法師<lb n="0001c17"/>鳩摩羅什奉　詔譯`).
     This is why lemma text flows into the *line* buffer as it arrives rather than
     being held and dumped at `</lem>`: buffering it would attribute the whole lemma
     to whichever line happened to close it, silently mis-citing the first half.

  ## Traps

  - **No blanket Unicode normalization.** Han variants are semantically meaningful in
    a critical edition, so characters pass through byte-for-byte.
  - **`<rdg>` must not leak into the body.** It is an *alternative* reading; treating
    it as text would silently interleave variants into the sūtra.
  - **CBETA punctuation is modern editorial addition**, absent from the witness. It is
    retained but flagged per line, so nobody cites it as original.
  """

  @behaviour Saxy.Handler

  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line

  # Text inside these never belongs to the running body text.
  # cb:mulu is excluded from BODY text but captured as the outline — it is the
  # table of contents, not noise. See start_element("cb:mulu", ...).
  @suppressed ~w(cb:docNumber teiHeader)
  # Editorial punctuation CBETA inserts; not present in the printed witness.
  @editorial_punctuation ~w(， 。 、 ； ： ？ ！ 「 」 『 』 （ ）)

  @doc """
  Normalizes a TEI document into an `IR` struct.

  Accepts a binary or a stream of binaries. `work_id`, `canon`, `volume`, and
  `number` are supplied by the caller because they come from the acquire step's
  catalogue knowledge, not from guessing.
  """
  @spec normalize(binary() | Enumerable.t(), keyword()) :: {:ok, IR.t()} | {:error, term()}
  def normalize(xml, opts) do
    state = initial_state()

    result =
      case xml do
        bin when is_binary(bin) -> Saxy.parse_string(bin, __MODULE__, state)
        stream -> Saxy.parse_stream(stream, __MODULE__, state)
      end

    with {:ok, final} <- result, do: {:ok, build_ir(final, opts)}
  end

  defp initial_state do
    %{
      suppress: 0,
      in_char_decl: false,
      in_body: false,
      in_back: false,
      anchors: %{},
      back_apparatus: [],
      outline: [],
      mulu: nil,
      char_id: nil,
      char_prop: nil,
      char_props: %{},
      gaiji: %{},
      juan: nil,
      juan_count: 0,
      anchor: nil,
      kind: :prose,
      line_juan: nil,
      line_kind: :prose,
      verse_depth: 0,
      head_depth: 0,
      buf: [],
      # Stacks, because <app> nests inside <lem>.
      app_stack: [],
      lem_stack: [],
      rdg: nil,
      note: nil,
      notes: [],
      apparatus: [],
      gaiji_seen: [],
      lines: [],
      header: %{},
      header_field: nil
    }
  end

  # ---- Saxy callbacks ----

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state), do: {:ok, flush_line(state)}

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state),
    do: {:ok, start_element(name, attrs, state)}

  @impl Saxy.Handler
  def handle_event(:end_element, name, state), do: {:ok, end_element(name, state)}

  @impl Saxy.Handler
  def handle_event(:characters, chars, state), do: {:ok, characters(chars, state)}

  # ---- start elements ----

  # ONLY inside <body>. The <back> apparatus reproduces body text inside its lemmas,
  # <lb/> and all, so treating those as line boundaries invents ~35 phantom lines with
  # DUPLICATE anchors — which would mean non-unique URNs and apparatus attached twice.
  defp start_element("lb", attrs, %{in_body: true} = state) do
    # A new physical line begins: close out the previous one first.
    #
    # `juan` and `kind` are captured HERE, not at flush time. Flushing happens when
    # the *next* <lb/> arrives, by which point a </lg> or a new <milestone> may have
    # already changed the running state — recording them then attributes each line's
    # properties to its neighbour.
    state = flush_line(state)
    %{state | anchor: attr(attrs, "n"), line_juan: state.juan, line_kind: state.kind}
  end

  defp start_element("lb", _attrs, state), do: state

  defp start_element("milestone", attrs, state) do
    if attr(attrs, "unit") == "juan" do
      juan = attrs |> attr("n") |> to_int()
      %{state | juan: juan, juan_count: max(state.juan_count, juan || 0)}
    else
      state
    end
  end

  defp start_element("body", _attrs, state), do: %{state | in_body: true}
  defp start_element("back", _attrs, state), do: %{state | in_back: true}

  # CBETA keeps its collation apparatus in <back> as a 校注 block, whose <app> entries
  # point at <anchor> positions in the body. Recording where each anchor occurred is
  # what lets a variant reading be attached to the line it actually belongs to.
  defp start_element("anchor", attrs, %{in_body: true, anchor: line} = state)
       when line != nil do
    case attr(attrs, "xml:id") do
      nil -> state
      id -> %{state | anchors: Map.put(state.anchors, id, line)}
    end
  end

  defp start_element("lg", _attrs, state) do
    %{state | verse_depth: state.verse_depth + 1, kind: :verse} |> retag_open_line(:verse)
  end

  defp start_element("head", _attrs, state) do
    %{state | head_depth: state.head_depth + 1, kind: :head} |> retag_open_line(:head)
  end

  defp start_element("app", attrs, state) do
    # A nested <app> (one sitting inside a parent's <lem>) carries no `from` of its
    # own; it annotates the same span as its parent, so it inherits that anchor.
    # Without this, nested variants resolve to no line and are silently lost.
    from = attr(attrs, "from") || parent_from(state.app_stack)
    %{state | app_stack: [%{from: from, lem: nil, rdgs: []} | state.app_stack]}
  end

  defp start_element("lem", _attrs, state),
    do: %{state | lem_stack: [[] | state.lem_stack]}

  defp start_element("rdg", attrs, state),
    do: %{state | rdg: %{wit: attr(attrs, "wit"), resp: attr(attrs, "resp"), acc: []}}

  defp start_element("note", attrs, state),
    do: %{state | note: %{n: attr(attrs, "n"), type: attr(attrs, "type"), acc: []}}

  # <cb:mulu level="1" n="1" type="品">1 序品</cb:mulu> — a TOC entry. Its text must not
  # reach the body, but the entry itself is structure worth keeping, anchored to the
  # line it sits on.
  defp start_element("cb:mulu", attrs, state) do
    entry = %{
      level: attrs |> attr("level") |> to_int(),
      n: attr(attrs, "n"),
      type: attr(attrs, "type"),
      anchor: state.anchor,
      juan: state.juan,
      acc: []
    }

    %{suppress(state) | mulu: entry}
  end

  defp start_element("g", attrs, state) do
    ref = attrs |> attr("ref") |> strip_hash()
    %{state | gaiji_seen: [ref | state.gaiji_seen]}
  end

  defp start_element("charDecl", _attrs, state), do: %{state | in_char_decl: true}

  defp start_element("char", attrs, state),
    do: %{state | char_id: attr(attrs, "xml:id"), char_props: %{}}

  defp start_element("mapping", attrs, state),
    do: %{state | char_prop: {:mapping, attr(attrs, "type")}}

  defp start_element("localName", _attrs, state), do: %{state | char_prop: :local_name}
  defp start_element("value", _attrs, state), do: %{state | char_prop: :value}

  defp start_element("title", attrs, state) do
    if state.in_body, do: state, else: %{state | header_field: {:title, attr(attrs, "level")}}
  end

  defp start_element("author", _attrs, state) do
    if state.in_body, do: state, else: %{state | header_field: :author}
  end

  defp start_element("availability", _attrs, state), do: %{state | header_field: :license}

  defp start_element(name, _attrs, state) when name in @suppressed, do: suppress(state)
  defp start_element(_name, _attrs, state), do: state

  # ---- end elements ----

  defp end_element("body", state), do: %{state | in_body: false}
  defp end_element("back", state), do: %{state | in_back: false}
  defp end_element("charDecl", state), do: %{state | in_char_decl: false}

  defp end_element("char", state),
    do: %{state | gaiji: Map.put(state.gaiji, state.char_id, state.char_props), char_id: nil}

  defp end_element(el, state) when el in ~w(mapping localName value),
    do: %{state | char_prop: nil}

  defp end_element("lg", state) do
    depth = state.verse_depth - 1
    %{state | verse_depth: depth, kind: if(depth > 0, do: :verse, else: :prose)}
  end

  defp end_element("head", state) do
    depth = state.head_depth - 1
    %{state | head_depth: depth, kind: if(depth > 0, do: :head, else: :prose)}
  end

  defp end_element("lem", %{lem_stack: []} = state), do: state

  defp end_element("lem", %{lem_stack: [acc | rest]} = state) do
    text = acc |> Enum.reverse() |> IO.iodata_to_binary()

    app_stack =
      case state.app_stack do
        [app | tail] -> [%{app | lem: text} | tail]
        [] -> []
      end

    %{state | lem_stack: rest, app_stack: app_stack}
  end

  defp end_element("rdg", %{rdg: nil} = state), do: state

  defp end_element("rdg", state) do
    text = state.rdg.acc |> Enum.reverse() |> IO.iodata_to_binary()

    # A <rdg> whose content is only <space/> means those witnesses OMIT the lemma.
    # That is a real variant reading, not missing data, and must not be confused with
    # an empty string when the apparatus is displayed.
    rdg = %{text: text, wit: state.rdg.wit, resp: state.rdg.resp, omitted: text == ""}

    app_stack =
      case state.app_stack do
        [app | tail] -> [%{app | rdgs: app.rdgs ++ [rdg]} | tail]
        [] -> []
      end

    %{state | rdg: nil, app_stack: app_stack}
  end

  defp end_element("app", %{app_stack: []} = state), do: state

  defp end_element("app", %{app_stack: [app | rest], in_back: true} = state),
    do: %{state | app_stack: rest, back_apparatus: [app | state.back_apparatus]}

  defp end_element("app", %{app_stack: [app | rest]} = state),
    do: %{state | app_stack: rest, apparatus: [app | state.apparatus]}

  defp end_element("cb:mulu", %{mulu: nil} = state), do: unsuppress(state)

  defp end_element("cb:mulu", state) do
    title = state.mulu.acc |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

    entry =
      state.mulu
      |> Map.delete(:acc)
      |> Map.put(:title, title)

    %{unsuppress(state) | outline: [entry | state.outline], mulu: nil}
  end

  defp end_element("note", %{note: nil} = state), do: state

  defp end_element("note", state) do
    text = state.note.acc |> Enum.reverse() |> IO.iodata_to_binary()
    notes = if text == "", do: state.notes, else: [text | state.notes]
    %{state | note: nil, notes: notes}
  end

  defp end_element(el, state) when el in ~w(title author availability),
    do: %{state | header_field: nil}

  defp end_element(name, state) when name in @suppressed, do: unsuppress(state)
  defp end_element(_name, state), do: state

  # ---- character data ----
  #
  # Order matters. Notes and variant readings are checked first because they occur
  # *inside* lemmas, and their text belongs to neither the body nor the lemma.

  defp characters(chars, %{in_char_decl: true, char_prop: prop} = state) when prop != nil,
    do: put_char_prop(state, chars)

  defp characters(chars, %{note: note} = state) when note != nil,
    do: %{state | note: %{note | acc: [chars | note.acc]}}

  defp characters(chars, %{rdg: rdg} = state) when rdg != nil,
    do: %{state | rdg: %{rdg | acc: [chars | rdg.acc]}}

  defp characters(chars, %{mulu: mulu} = state) when mulu != nil,
    do: %{state | mulu: %{mulu | acc: [chars | mulu.acc]}}

  defp characters(chars, %{in_body: false, header_field: field} = state) when field != nil,
    do: %{state | header: Map.update(state.header, field, chars, &(&1 <> chars))}

  defp characters(_chars, %{suppress: n} = state) when n > 0, do: state
  defp characters(_chars, %{in_body: false, lem_stack: []} = state), do: state

  defp characters(chars, state) do
    if String.trim(chars) == "" do
      state
    else
      # Lemma text goes to the line buffer as it arrives, so an <lb/> inside a <lem>
      # splits it across lines correctly, and is *also* captured for the apparatus.
      # Outside <body> only the lemma capture applies: the apparatus in <back> is not
      # running text and must never reach a line.
      lem_stack =
        case state.lem_stack do
          [acc | rest] -> [[chars | acc] | rest]
          [] -> []
        end

      buf = if state.in_body, do: [chars | state.buf], else: state.buf
      %{state | buf: buf, lem_stack: lem_stack}
    end
  end

  defp put_char_prop(state, chars) do
    key =
      case state.char_prop do
        {:mapping, type} -> "mapping_#{type}"
        :local_name -> "local_name"
        :value -> "value"
      end

    %{state | char_props: Map.update(state.char_props, key, chars, &(&1 <> chars))}
  end

  # ---- line flushing ----

  defp flush_line(%{anchor: nil} = state), do: reset_line(state)

  defp flush_line(state) do
    text = state.buf |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

    line = %Line{
      anchor: state.anchor,
      juan: state.line_juan,
      kind: state.line_kind,
      text: text,
      notes: Enum.reverse(state.notes),
      apparatus: Enum.reverse(state.apparatus),
      gaiji: state.gaiji_seen |> Enum.reverse() |> Enum.uniq(),
      editorial_punctuation: String.contains?(text, @editorial_punctuation)
    }

    reset_line(%{state | lines: [line | state.lines]})
  end

  defp reset_line(state),
    do: %{state | buf: [], notes: [], apparatus: [], gaiji_seen: []}

  # A structural element can open just *after* the <lb/> that starts its line, as in
  # `<lg><lb n="..."/><l>...</l></lg>`. Retag only while the line is still empty: once
  # text has accumulated, the line genuinely began as prose and must stay prose, or
  # every prose line preceding a verse block gets mislabelled.
  defp retag_open_line(%{buf: []} = state, kind), do: %{state | line_kind: kind}
  defp retag_open_line(state, _kind), do: state

  # ---- assembly ----

  defp build_ir(state, opts) do
    gaiji = Map.new(state.gaiji, fn {id, props} -> {id, decode_gaiji(props)} end)
    by_line = group_back_apparatus(state)

    lines =
      state.lines
      |> Enum.reverse()
      |> Enum.map(&resolve_gaiji(&1, gaiji))
      |> Enum.map(&attach_apparatus(&1, by_line))

    %IR{
      work_id: Keyword.fetch!(opts, :work_id),
      canon: Keyword.fetch!(opts, :canon),
      volume: Keyword.get(opts, :volume),
      number: Keyword.get(opts, :number),
      title: trim_or_nil(state.header[{:title, "m"}]),
      title_original: trim_or_nil(state.header[{:title, "m"}]),
      author: trim_or_nil(state.header[:author]),
      license_notice: trim_or_nil(state.header[:license]),
      juan_count: state.juan_count,
      gaiji: gaiji,
      lines: lines,
      # Apparatus whose `from` anchor is absent from the body. Kept and counted, never
      # dropped: an entry we cannot place is a defect to surface, not to hide.
      unanchored_apparatus: Map.get(by_line, nil, []),
      outline: Enum.reverse(state.outline)
    }
  end

  # Resolve each <back> <app from="#beg0001003"> to the body line where that anchor sits.
  defp group_back_apparatus(state) do
    state.back_apparatus
    |> Enum.reverse()
    |> Enum.group_by(fn app -> Map.get(state.anchors, strip_hash(app.from || "")) end)
  end

  defp attach_apparatus(%Line{} = line, by_line) do
    case Map.get(by_line, line.anchor) do
      nil -> line
      apps -> %{line | apparatus: line.apparatus ++ apps}
    end
  end

  defp decode_gaiji(props) do
    %{
      unicode: props |> Map.get("mapping_unicode") |> codepoint(),
      normalized: Map.get(props, "value"),
      composition: Map.get(props, "value")
    }
  end

  # "U+249B2" -> the actual character. CBETA files carry the PUA form inline, so the
  # header mapping is the only route to a real Unicode codepoint.
  defp codepoint("U+" <> hex) do
    case Integer.parse(hex, 16) do
      {cp, ""} when cp in 0..0x10FFFF -> <<cp::utf8>>
      _ -> nil
    end
  end

  defp codepoint(_), do: nil

  # Gaiji resolution is recorded on the line but does NOT rewrite the text: the inline
  # character is what the edition prints. Phase 1 adds the substitution pass once the
  # full gaiji table and its test suite exist.
  defp resolve_gaiji(%Line{gaiji: []} = line, _table), do: line

  defp resolve_gaiji(%Line{} = line, table),
    do: %{line | gaiji: Enum.map(line.gaiji, &%{ref: &1, mapping: Map.get(table, &1)})}

  # ---- small helpers ----

  defp attr(attrs, name), do: Enum.find_value(attrs, fn {k, v} -> if k == name, do: v end)

  defp parent_from([%{from: from} | _]), do: from
  defp parent_from([]), do: nil

  defp strip_hash("#" <> rest), do: rest
  defp strip_hash(other), do: other

  defp to_int(nil), do: nil

  defp to_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp trim_or_nil(nil), do: nil

  defp trim_or_nil(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp suppress(state), do: %{state | suppress: state.suppress + 1}
  defp unsuppress(state), do: %{state | suppress: max(state.suppress - 1, 0)}
end
