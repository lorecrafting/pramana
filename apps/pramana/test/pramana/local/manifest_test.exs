defmodule Pramana.Local.ManifestTest do
  @moduledoc """
  Validation of a locally-added text's manifest.

  These tests are mostly about what validation *refuses*. Adding a text is the one place
  a human hand-writes provenance, and a wrong label here is indistinguishable from a
  right one until something is mis-cited months later — so the defaults lean
  conservative and the required fields are genuinely required.
  """
  use ExUnit.Case, async: true

  alias Pramana.Local.Manifest

  @valid %{
    "id" => "test-text",
    "title" => "測試",
    "format" => "text",
    "provenance" => %{"composition_origin" => "chinese", "text_role" => "commentary"},
    "citation" => %{"addressing" => "derived"}
  }

  setup do
    dir = Path.join(System.tmp_dir!(), "pramana-manifest-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "text"))
    File.write!(Path.join([dir, "text", "01.txt"]), "文字")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp validate(overrides, dir), do: Manifest.validate(Map.merge(@valid, overrides), dir)

  describe "required fields" do
    test "a minimal valid manifest passes", %{dir: dir} do
      assert {:ok, manifest} = validate(%{}, dir)
      assert manifest.id == "test-text"
    end

    test "reports EVERY problem at once, not just the first", %{dir: dir} do
      # Fixing one field per run is how people lose patience and start guessing.
      assert {:error, errors} =
               Manifest.validate(%{"id" => "x", "citation" => %{}}, dir)

      assert length(errors) > 2
    end

    test "provenance is required, never inferred", %{dir: dir} do
      assert {:error, errors} = validate(%{"provenance" => %{}}, dir)

      assert Enum.any?(errors, &(&1 =~ "provenance.composition_origin"))
      assert Enum.any?(errors, &(&1 =~ "provenance.text_role"))
    end

    test "an unknown origin or role is refused rather than stored", %{dir: dir} do
      assert {:error, errors} =
               validate(
                 %{"provenance" => %{"composition_origin" => "martian", "text_role" => "root"}},
                 dir
               )

      assert Enum.any?(errors, &(&1 =~ "martian"))
    end

    test "text/ must exist and contain something", %{dir: dir} do
      File.rm_rf!(Path.join(dir, "text"))
      assert {:error, errors} = validate(%{}, dir)
      assert Enum.any?(errors, &(&1 =~ "text/"))
    end
  end

  describe "the id, which ends up inside every URN" do
    test "rejects characters that would break the URN grammar", %{dir: dir} do
      # A colon is the URN's field separator and an @ is its locator separator; either
      # one inside an id makes every citation the text produces unparseable.
      for bad <- ["has:colon", "has@at", "Has-Caps", "has space", "has.dot"] do
        assert {:error, errors} = validate(%{"id" => bad}, dir)
        assert Enum.any?(errors, &(&1 =~ "`id`")), "accepted #{bad}"
      end
    end

    test "accepts lowercase, digits and hyphens", %{dir: dir} do
      assert {:ok, _} = validate(%{"id" => "huang-nianzu-jie-2"}, dir)
    end
  end

  describe "licence defaults" do
    test "an unspecified licence is RESTRICTED, not permissive", %{dir: dir} do
      # Most one-off texts are modern and in copyright. Defaulting permissive is a
      # licence violation waiting to happen; defaulting restricted only withholds it.
      assert {:ok, manifest} = validate(%{}, dir)

      assert manifest.license["class"] == "restricted"
      assert manifest.license["redistributable"] == false
      refute Manifest.public?(manifest)
    end

    test "a permissive licence must be declared explicitly to take effect", %{dir: dir} do
      assert {:ok, manifest} =
               validate(%{"license" => %{"class" => "cc0", "redistributable" => true}}, dir)

      assert Manifest.public?(manifest)
    end

    test "a permissive class alone does not make a text public", %{dir: dir} do
      # Both facts have to be asserted; a class without redistribution rights is not a
      # grant to republish.
      assert {:ok, manifest} = validate(%{"license" => %{"class" => "cc0"}}, dir)
      refute Manifest.public?(manifest)
    end
  end

  describe "addressing" do
    test "accepts the three honest levels", %{dir: dir} do
      for level <- ~w(canonical edition_page derived) do
        citation = %{"addressing" => level, "anchor_source" => "printed page numbers"}
        assert {:ok, _} = validate(%{"citation" => citation}, dir)
      end
    end

    test "edition_page must say where the page numbers came from", %{dir: dir} do
      # The claim "a reader can turn to this page" is only checkable if the manifest
      # says what the numbers are.
      assert {:error, errors} = validate(%{"citation" => %{"addressing" => "edition_page"}}, dir)
      assert Enum.any?(errors, &(&1 =~ "anchor_source"))
    end

    test "derived needs no anchor_source, because it claims nothing", %{dir: dir} do
      assert {:ok, _} = validate(%{"citation" => %{"addressing" => "derived"}}, dir)
    end

    test "an unknown addressing value is refused", %{dir: dir} do
      assert {:error, errors} = validate(%{"citation" => %{"addressing" => "vibes"}}, dir)
      assert Enum.any?(errors, &(&1 =~ "citation.addressing"))
    end
  end

  describe "external input never touches the atom table" do
    test "an unrecognised provenance key does not crash validation", %{dir: dir} do
      # Regression: the manifest was atomized with String.to_existing_atom/1, so a key
      # the code had never mentioned — `date_range` — raised ArgumentError on a
      # perfectly valid manifest.
      provenance = %{
        "composition_origin" => "chinese",
        "text_role" => "commentary",
        "date_range" => [1981, 1984],
        "some_future_key" => "value"
      }

      assert {:ok, manifest} = validate(%{"provenance" => provenance}, dir)
      assert manifest.provenance["date_range"] == [1981, 1984]
    end
  end

  describe "comments_on" do
    test "must name the work it explains", %{dir: dir} do
      assert {:error, errors} = validate(%{"comments_on" => %{"relation" => "comments_on"}}, dir)
      assert Enum.any?(errors, &(&1 =~ "comments_on"))
    end

    test "is optional", %{dir: dir} do
      assert {:ok, manifest} = validate(%{}, dir)
      assert manifest.comments_on == nil
    end
  end

  describe "load/1" do
    test "reports a missing manifest by path", %{dir: dir} do
      assert {:error, [error]} = Manifest.load(dir)
      assert error =~ "manifest.yaml"
    end

    test "reports invalid YAML rather than crashing", %{dir: dir} do
      File.write!(Path.join(dir, "manifest.yaml"), "id: [unclosed\n")
      assert {:error, [error]} = Manifest.load(dir)
      assert error =~ "YAML"
    end
  end
end
