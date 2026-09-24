defmodule PramanaWeb.ReaderInventoryLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  setup :load_reader_fixture

  describe "the inventory" do
    test "leads with what is NOT loaded", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "Not loaded"
      assert html =~ "CBETA publishes 26 collections"
      assert html =~ "Taishō volumes 56–84"
    end

    test "names the absent collections rather than coding them", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "嘉興大藏經"
      assert html =~ "Jiaxing Canon"
    end

    test "shows the corpus totals and the bake that produced them", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "citable segments"
      assert html =~ "pipeline v"
    end

    test "breaks works down by composition origin, named in words", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "Where these texts were composed"
      assert html =~ "Indic-composed"
      assert html =~ "Japanese-composed"
    end
  end
end
