defmodule Pramana.Local.Normalizer do
  @moduledoc """
  Turns a locally-added text's `text/` directory into `Pramana.Normalize.IR`.

  One IR line per **file**, and the file is expected to be one page of the printed
  source, named by its printed page number. That is the same principle as the Taishō
  normalizer: the anchor is the edition's own, never invented (`CLAUDE.md` invariant #2).

  ## Why the page, and nothing finer

  A page here is ~500 characters, far coarser than a Taishō line. It is still the right
  unit, because it is the finest anchor the edition actually provides. Splitting a page
  into paragraphs and citing `@p0100.3` would look more precise while being *less*
  checkable — the page number is printed in the book and the paragraph index is
  something we made up. Retrieval chunking handles the size; citation does not get to
  invent precision.

  ## Running heads are removed, carefully

  About half the body pages repeat the book title and page number as a running head.
  Left in, every one of those pages matches a search for the title. Removed carelessly,
  real content disappears: page 837 opens `九九、往生要集 … 一○○、本源清淨大圓鏡`, where
  `一○○` is a **list number**, not a page number, and a rule that stripped any line
  containing Chinese numerals would eat it.

  So a first line is dropped only when it is the title followed by nothing but
  whitespace and numerals. The count of stripped heads is reported, because a silent
  change to 419 pages is exactly the kind of thing that should not be silent.
  """

  @behaviour Pramana.Pipeline.Normalizer

  alias Pramana.Local.Manifest
  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line

  # Chinese numerals as this book writes them, including ○ (U+25CB) for zero — NOT 〇
  # (U+3007). Getting that wrong silently mis-cut ~158 pages in the source project's
  # first extraction pass.
  @numerals "〇○０0-9一二三四五六七八九十百千"

  @impl Pramana.Pipeline.Normalizer
  def normalize(dir, opts) do
    with {:ok, manifest} <- load_manifest(dir, opts) do
      text_dir = Pramana.Paths.local_text_dir(dir)

      lines =
        Enum.map(manifest.files, fn rel ->
          {line, _dropped?} = to_line(rel, File.read!(Path.join(text_dir, rel)), manifest)
          line
        end)

      {:ok,
       %IR{
         work_id: work_id(manifest),
         canon: witness_id(manifest),
         volume: nil,
         number: nil,
         title: manifest.title,
         title_original: manifest.title,
         author: manifest.author,
         license_notice: manifest.license["note"],
         juan_count: 0,
         lines: lines,
         outline: [],
         gaiji: %{},
         unanchored_apparatus: []
       }}
    end
  end

  @doc "How many running heads `normalize/2` would strip. Reported by the add task."
  @spec stripped_running_heads(Path.t(), Manifest.t()) :: non_neg_integer()
  def stripped_running_heads(dir, manifest) do
    text_dir = Pramana.Paths.local_text_dir(dir)

    Enum.count(manifest.files, fn rel ->
      {_line, dropped?} = to_line(rel, File.read!(Path.join(text_dir, rel)), manifest)
      dropped?
    end)
  end

  defp load_manifest(_dir, opts) do
    case Keyword.fetch(opts, :manifest) do
      {:ok, %Manifest{} = manifest} -> {:ok, manifest}
      :error -> {:error, :manifest_required}
    end
  end

  defp to_line(rel, contents, manifest) do
    {body, dropped?} = strip_running_head(contents, manifest.title)

    line = %Line{
      anchor: anchor(rel),
      juan: nil,
      kind: :prose,
      text: String.trim(body),
      notes: [],
      apparatus: [],
      gaiji: [],
      editorial_punctuation: false
    }

    {line, dropped?}
  end

  # `0100.txt` -> "0100"; `toc-0003.txt` -> "toc-0003". Front matter restarts its
  # numbering, so it keeps its own prefixed sequence rather than being renumbered into
  # the body — renumbering would produce page references that match no printed page.
  defp anchor(rel), do: rel |> Path.basename() |> Path.rootname()

  defp strip_running_head(contents, title) do
    case String.split(contents, "\n", parts: 2) do
      [first, rest] ->
        maybe_drop(first, rest, title)

      # A page whose ENTIRE content is a running head, with no trailing newline. The
      # real source happened to have trailing newlines so this went unnoticed; without
      # the guard such a page keeps the book title as its text and then matches every
      # search for the title.
      [only] ->
        if running_head?(only, title), do: {"", true}, else: {only, false}
    end
  end

  defp maybe_drop(first, rest, title) do
    if running_head?(first, title), do: {rest, true}, else: {first <> "\n" <> rest, false}
  end

  defp running_head?(_line, nil), do: false

  defp running_head?(line, title) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, title) and
      trimmed
      |> String.replace_prefix(title, "")
      |> String.match?(~r/\A[\s#{@numerals}]*\z/u)
  end

  defp work_id(manifest), do: manifest.citation["work_id"] || manifest.id
  defp witness_id(manifest), do: manifest.citation["witness_id"] || manifest.id
end
