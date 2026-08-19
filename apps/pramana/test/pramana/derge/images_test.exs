defmodule Pramana.Derge.ImagesTest do
  @moduledoc """
  Turning a folio into the photograph of that leaf.

  The mapping is BDRC's, read off the canvas labels in its manifest. These tests pin the
  reading of it — and the refusal, which matters more: a page image that is nearly right
  is worse than none, because it looks like proof.
  """
  use ExUnit.Case, async: true

  alias Pramana.Derge.Images

  defp canvas(id, labels) do
    %{
      "@id" => "https://iiifpres.bdrc.io/v:bdr:I1KG9127/canvas/#{id}",
      "label" => Enum.map(labels, &%{"@language" => "en", "@value" => &1})
    }
  end

  defp manifest(canvases), do: %{"sequences" => [%{"canvases" => canvases}]}

  describe "reading the folio labels" do
    test "a canvas is labelled with its folio, and that is the mapping" do
      # BDRC labels each canvas `1a`, `1b`, `2a` — the same reference the etext prints.
      folios =
        Images.folios_in(
          manifest([
            canvas("I1KG91270003.jpg", ["1a", "img. 3"]),
            canvas("I1KG91270004.jpg", ["1b", "img. 4"])
          ])
        )

      assert folios == %{"1a" => "I1KG91270003.jpg", "1b" => "I1KG91270004.jpg"}
    end

    test "the image number and the Tibetan label are not folios" do
      # A canvas carries four labels: `1a`, `img. 3`, `1na/`, `par grangs _3`. Only the
      # first is a reference a reader could look up.
      folios =
        Images.folios_in(
          manifest([canvas("I1KG91270003.jpg", ["img. 3", "1na/", "par grangs _3", "1a"])])
        )

      assert folios == %{"1a" => "I1KG91270003.jpg"}
    end

    test "the cataloguing cards have no folio and are skipped" do
      # The two scans before the text are BDRC's own cards, labelled by image number only.
      folios =
        Images.folios_in(
          manifest([
            canvas("I1KG91270001.tif", ["img. 1"]),
            canvas("I1KG91270002.tif", ["img. 2"]),
            canvas("I1KG91270003.jpg", ["1a", "img. 3"])
          ])
        )

      assert folios == %{"1a" => "I1KG91270003.jpg"}
    end

    test "a manifest with no canvases yields nothing rather than raising" do
      assert Images.folios_in(%{}) == %{}
      assert Images.folios_in(manifest([])) == %{}
    end
  end

  describe "the volumes of the edition" do
    test "the image group comes from the etext's own directory" do
      # `UT4CZ5369-I1KG9127` is volume 1, and BDRC's record for that group says so too.
      # Adding 9126 to the volume number also works and is a fact about nothing.
      root = Path.join(System.tmp_dir!(), "derge-images-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "UT4CZ5369-I1KG9127"))

      File.write!(
        Path.join(root, "UT4CZ5369-I1KG9127/vol.xml"),
        """
        <tei:TEI xmlns:tei="http://www.tei-c.org/ns/1.0"><tei:teiHeader><tei:fileDesc>
        <tei:titleStmt><tei:title>vol [1]</tei:title></tei:titleStmt>
        </tei:fileDesc></tei:teiHeader></tei:TEI>
        """
      )

      on_exit(fn -> File.rm_rf!(root) end)

      assert Images.volumes(root) == [{1, "I1KG9127"}]
    end
  end

  describe "the links" do
    test "the manifest URL is BDRC's presentation service" do
      assert Images.manifest_url("I1KG9177") == "https://iiifpres.bdrc.io/v:bdr:I1KG9177/manifest"
    end
  end

  describe "what happens when there is no image" do
    test "a URN from another tradition is not a Derge folio" do
      assert Images.for_urn("pramana:cbeta.T:T0262_001@p0001c17") == :error
      assert Images.for_urn("pramana:sc.ms:mn1@1.1") == :error
    end

    test "a malformed URN does not raise" do
      assert Images.for_urn("nonsense") == :error
      assert Images.for_urn("pramana:derge.D:toh1") == :error
    end
  end
end
