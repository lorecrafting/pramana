defmodule Mix.Tasks.Pramana.Local.Validate do
  @shortdoc "Checks a local source directory. Writes nothing."

  @moduledoc """
  Validates `sources/local/<id>/` before anything is added to the corpus.

      mix pramana.local.validate sources/local/huang-nianzu-jie

  **This task writes nothing** — not to the database, not to `sources.lock.json`, not to
  `raw/`. Getting provenance wrong is the failure this project exists to prevent, so the
  checking step is deliberately separable and cheap to re-run. Run it as often as you
  like while getting a manifest right.

  It reports **every** problem at once rather than the first, because fixing one field
  per run is how people lose patience and start guessing at values.

  It also prints what the manifest *implies* — the URNs that will be produced, the
  licence gating that will apply, the provenance that will be attached — because most
  manifest mistakes are invisible until something is mis-cited months later.
  """

  use Mix.Task

  alias Pramana.Local.Manifest

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.config")

    case argv do
      [dir | _] -> validate(dir)
      [] -> Mix.raise("usage: mix pramana.local.validate <dir>")
    end
  end

  defp validate(dir) do
    case Manifest.load(dir) do
      {:ok, manifest} -> report_ok(manifest, dir)
      {:error, errors} -> report_errors(errors, dir)
    end
  end

  defp report_ok(manifest, dir) do
    Mix.shell().info("""

    #{IO.ANSI.green()}manifest OK#{IO.ANSI.reset()} — #{dir}

      id:         #{manifest.id}
      title:      #{manifest.title}#{title_en(manifest)}
      author:     #{manifest.author || "(none given)"}
      files:      #{length(manifest.files)} in text/
    """)

    report_provenance(manifest)
    report_addressing(manifest)
    report_license(manifest)
    report_extraction(manifest)
    report_relation(manifest)

    Mix.shell().info("""
    Nothing was written. To add it:

      mix pramana.local.add #{dir}
    """)
  end

  defp title_en(%{title_en: nil}), do: ""
  defp title_en(%{title_en: en}), do: "\n      title_en:   #{en}"

  defp report_provenance(manifest) do
    p = manifest.provenance

    Mix.shell().info("""
      PROVENANCE (required, never inferred — no division table applies to a local text)
        composition_origin: #{fetch(p, :composition_origin)}
        text_role:          #{fetch(p, :text_role)}
        label:              #{Pramana.Provenance.label(fetch(p, :composition_origin), fetch(p, :text_role))}
    """)
  end

  defp report_addressing(manifest) do
    addressing = manifest.citation["addressing"]

    Mix.shell().info("""
      ADDRESSING: #{addressing}
        #{addressing_note(addressing)}
        example URN: pramana:local.#{manifest.id}:#{manifest.id}@#{example_locator(addressing)}
    """)
  end

  defp addressing_note("canonical"),
    do: "citations can be checked against a published digital edition"

  defp addressing_note("edition_page"),
    do:
      "citations point at a page printed in the book, so a reader can turn to it.\n" <>
        "        The risk is our extraction, not the anchor."

  defp addressing_note("derived"),
    do:
      "NO intrinsic anchor. Positions come from file structure and will SHIFT if the\n" <>
        "        file changes, silently invalidating earlier citations. If this text has\n" <>
        "        printed page or section numbers, use them instead."

  defp addressing_note(other), do: "unknown addressing: #{other}"

  defp example_locator("edition_page"), do: "p0100"
  defp example_locator("canonical"), do: "p0001a01"
  defp example_locator(_), do: "sec1.p1"

  defp report_license(manifest) do
    license = manifest.license
    public? = Manifest.public?(manifest)

    Mix.shell().info("""
      LICENCE: #{license["class"]} (redistributable: #{license["redistributable"] == true})
        #{if public?, do: "may appear on public surfaces", else: "EXCLUDED from public surfaces and from any redistributed corpus"}
    """)
  end

  defp report_extraction(%{extraction: nil}) do
    Mix.shell().info("""
      EXTRACTION: not declared
        Fine for a born-digital text. If this came from a PDF or OCR, declare it —
        an OCR'd text and a hand-proofread one are not the same evidence.
    """)
  end

  defp report_extraction(%{extraction: extraction}) do
    Mix.shell().info("""
      EXTRACTION: #{extraction["method"] || "(method not stated)"}
        confidence: #{extraction["confidence"] || "(not stated)"}
        #{extraction["note"] || ""}
    """)
  end

  defp report_relation(%{comments_on: nil}), do: :ok

  defp report_relation(%{comments_on: rel}) do
    Mix.shell().info("""
      COMMENTS ON: #{rel["work"]}
        relation: #{rel["relation"] || "comments_on"} (confidence: #{rel["confidence"] || "unstated"})
    """)
  end

  # Always raises; declared so dialyzer does not report the caller as no_return.
  @spec report_errors([String.t()], Path.t()) :: no_return()
  defp report_errors(errors, dir) do
    for e <- errors, do: Mix.shell().error("  • #{e}")

    Mix.raise("""

    #{length(errors)} problem(s) in #{dir}. Nothing was written.

    See docs/ADDING_TEXTS.md for the manifest schema. Provenance and addressing are
    required rather than inferred: for a local text there is no catalogue to fall back
    on, and a wrong label is worse than a missing one.
    """)
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
