defmodule Pramana.Normalize.Derge.AuditTest do
  @moduledoc """
  The independent count.

  Its whole value is that it does not know how the normalizer works. These tests check
  that it stays that way: it must count text the parser drops, and it must not care what
  a work or a folio is.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Derge.Audit
  alias Pramana.Normalize.Derge.Edition

  defp tei(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <tei:TEI xmlns:tei="http://www.tei-c.org/ns/1.0">
      <tei:teiHeader><tei:fileDesc>
        <tei:titleStmt><tei:title>vol [1]</tei:title></tei:titleStmt>
        <tei:publicationStmt><tei:distributor>Esukhia</tei:distributor></tei:publicationStmt>
      </tei:fileDesc></tei:teiHeader>
      <tei:text><tei:body><tei:div>#{body}</tei:div></tei:body></tei:text>
    </tei:TEI>
    """
  end

  defp folio(n, content), do: ~s(<tei:p n="1" data-orig-n="#{n}">#{content}</tei:p>)
  defp line(n), do: ~s(<tei:milestone unit="line" n="#{n}"/>)
  defp toh(n), do: ~s(<tei:milestone unit="text" toh="#{n}"/>)

  test "counts the text and nothing around it" do
    xml = tei(folio("1b", "#{line(1)}#{toh(1)}abc"))

    assert {:ok, %{text_bytes: 3}} = Audit.census(xml)
  end

  test "counts text the parser will drop, which is the point" do
    # Text before the first toh marker belongs to no work and is dropped. The audit must
    # still see it, or the difference it exists to measure is invisible.
    xml = tei(folio("1a", "title page") <> folio("1b", "#{line(1)}#{toh(1)}abc"))

    assert {:ok, %{text_bytes: 12, preamble_bytes: 9}} = Audit.census(xml)
  end

  test "whitespace and indentation are not content" do
    xml = tei(folio("1b", "\n   #{line(1)}#{toh(1)}a b\n   "))

    assert {:ok, %{text_bytes: 2}} = Audit.census(xml)
  end

  test "a volume with no marker at all is all preamble" do
    # These are the 26 volumes that the first version of the normalizer discarded whole.
    xml = tei(folio("1a", "#{line(1)}continuation"))

    assert {:ok, %{text_bytes: 12, preamble_bytes: 12}} = Audit.census(xml)
  end

  describe "reconciling the walk against the count" do
    test "a clean edition drops only the first volume's preamble" do
      root = write_edition!()

      {:ok, volumes} = Edition.volumes_at(root)
      {:ok, [first, second]} = Edition.reconcile(volumes, catalogue_volumes: [])

      assert first.dropped == first.allowed
      assert first.allowed > 0
      assert second.dropped == 0
    end

    test "a later volume is allowed to drop nothing, even though it has a preamble" do
      # This is the 146,962-line bug stated as a rule. Volume 2 continues a work it does
      # not name, so by the audit's reckoning its entire content sits before any marker —
      # exactly what the first version of the normalizer read as front matter and threw
      # away. Every byte of it belongs to the work running in from volume 1, so the
      # allowance here is zero and any drop is a failure.
      root = write_edition!()
      {:ok, [_v1, {2, path}] = volumes} = Edition.volumes_at(root)

      {:ok, census} = path |> File.read!() |> Audit.census()
      {:ok, [_first, second]} = Edition.reconcile(volumes)

      assert census.preamble_bytes > 0
      assert second.allowed == 0
      assert second.dropped == 0
    end
  end

  defp write_edition! do
    root = Path.join(System.tmp_dir!(), "derge-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "v1"))
    File.mkdir_p!(Path.join(root, "v2"))

    File.write!(
      Path.join(root, "v1/v1.xml"),
      tei(folio("1a", "title page") <> folio("1b", "#{line(1)}#{toh(1)}abc"))
    )

    File.write!(
      Path.join(root, "v2/v2.xml"),
      String.replace(tei(folio("1a", "#{line(1)}continues")), "[1]", "[2]")
    )

    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
