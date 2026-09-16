defmodule Pramana.URN.Taisho do
  @moduledoc """
  The Taishō citation grammar — page, register, line.

  A Taishō reference like `T09n0262_p0037a13` decomposes as:

      T        Taishō canon
      09       volume
      n0262    text number (work)
      p0037    page
      a        register (column band on the page: a, b, or c)
      13       line within that register

  Our URN carries this as `pramana:cbeta.T:T0262_009@p0037a13`, where `_009` is the
  juan (fascicle) and `p0037a13` is the locator.

  This grammar is why `<lb/>` elements must survive normalization: the line number is
  not decoration, it *is* the citation. A scholar checks us by opening the printed
  volume to page 37, register a, line 13. See `docs/ARCHITECTURE.md`, Stage 1.
  """

  @type anchor :: %{page: String.t(), register: String.t(), line: pos_integer()}

  @registers ~w(a b c)

  @doc """
  Parses a Taishō locator such as `"p0037a13"`.

  The page is kept as a **string**, not an integer: Taishō page numbers are
  zero-padded to four digits and some carry suffixes, and round-tripping through an
  integer would silently rewrite the citation.
  """
  @spec parse_locator(String.t()) :: {:ok, anchor()} | {:error, atom()}
  def parse_locator("p" <> rest) do
    with {page, reg_and_line} <- String.split_at(rest, 4),
         true <- String.length(page) == 4 and numeric?(page),
         {register, line_str} <- String.split_at(reg_and_line, 1),
         true <- register in @registers,
         {line, ""} <- Integer.parse(line_str) do
      {:ok, %{page: page, register: register, line: line}}
    else
      _ -> {:error, :bad_taisho_locator}
    end
  end

  def parse_locator(_), do: {:error, :bad_taisho_locator}

  @doc "Renders an anchor back to locator form. Inverse of `parse_locator/1`."
  @spec format_locator(anchor()) :: String.t()
  def format_locator(%{page: page, register: register, line: line}) do
    "p#{page}#{register}#{pad_line(line)}"
  end

  @doc """
  Parses a work reference such as `"T0262_009"` into `{work_id, juan}`.

  Juan is optional: `"T0262"` yields `{"T0262", nil}`.
  """
  @spec parse_work(String.t()) :: {:ok, {String.t(), pos_integer() | nil}} | {:error, atom()}
  def parse_work(work) when is_binary(work) do
    case String.split(work, "_", parts: 2) do
      [id] ->
        if id == "", do: {:error, :empty_work}, else: {:ok, {id, nil}}

      [id, juan_str] ->
        case Integer.parse(juan_str) do
          {juan, ""} when juan > 0 -> {:ok, {id, juan}}
          _ -> {:error, :bad_juan}
        end
    end
  end

  @doc """
  The volume a Taishō text number falls in cannot be derived arithmetically — the
  mapping is a lookup table. But the *provenance* rule can be applied from the volume
  once known, and it is mechanical rather than heuristic:

  CBETA covers Taishō vols 1–55 and 85. SAT covers 1–85. The delta, vols **56–84**, is
  exactly the Japanese-composed sectarian corpus (Shingon, Tendai, Nichiren, Zen).

  **Origin is mechanical; role is not, and this used to guess it.** Until 2026-09-02 the
  56–84 clause returned `text_role: "commentary"` for the whole block. That is contradicted
  by every row `Pramana.Taisho.Divisions` holds for the range — 續經疏部 and 續律疏部・續論疏部
  are `subcommentary`, 續諸宗部 and 悉曇部 are `treatise`, and not one is `commentary`.

  It survived the correction of 2026-08-30, which rebuilt exactly this range from SAT's own
  分類 after finding 452 of 510 works mislabelled by a single collapsed row. **Same range,
  third time** — rule 41: a fix that does not sweep for the constant's other homes leaves it
  standing where it will fire next. Nothing is mislabelled today only because these volumes
  are not loaded, and the division table wins for canon `T` whenever it can speak; this is
  the fallback for when it cannot, and a fallback that guesses is worse than one that does
  not.

  So role is now `nil` here, which is what the rest of this module already does: *an
  unlabelled work is a smaller problem than a mislabelled one.*

  See `docs/ARCHITECTURE.md`, "Your Taishō requirement, solved".
  """
  @spec provenance_for_volume(pos_integer()) ::
          {:ok, %{composition_origin: String.t() | nil, text_role: String.t() | nil}}
          | {:error, atom()}
  def provenance_for_volume(volume) when is_integer(volume) and volume in 56..84 do
    {:ok, %{composition_origin: "japanese", text_role: nil}}
  end

  def provenance_for_volume(volume) when is_integer(volume) and volume in 1..85 do
    # Vols 1-55 and 85 hold Indic translations alongside Chinese compositions. Origin
    # and role here need per-work catalogue data — a Chinese-composed treatise in
    # vol. 45 is not an Indic sūtra — so we return nil rather than guess. Phase 1
    # populates these from the CBETA catalogue. Guessing would be worse than a gap:
    # a wrong provenance label is exactly the failure this project exists to prevent.
    {:ok, %{composition_origin: nil, text_role: nil}}
  end

  def provenance_for_volume(_), do: {:error, :volume_out_of_range}

  defp numeric?(str), do: String.match?(str, ~r/\A\d+\z/)
  defp pad_line(line), do: line |> Integer.to_string() |> String.pad_leading(2, "0")
end
