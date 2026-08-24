defmodule Pramana.Cbeta.BylineTest do
  @moduledoc """
  Composition origin read from a work's own byline.

  This exists because `Taisho.Divisions` is the 部 table for the Taishō and CBETA holds 26
  collections. The rule was validated against that table on 2,077 Taishō works where both
  are known and agreed on 97.3% — these tests pin the behaviour, not the accuracy.
  """
  use ExUnit.Case, async: true

  alias Pramana.Cbeta.Byline
  alias Pramana.Taisho.Divisions

  describe "provenance/1 — the verb is the discriminator" do
    test "譯 means translated, so the work is Indic in origin" do
      assert Byline.provenance("後秦 佛陀耶舍共竺佛念譯") == %{composition_origin: "indic"}
      assert Byline.provenance("劉宋 求那跋陀羅譯") == %{composition_origin: "indic"}
      assert Byline.provenance("唐 玄奘譯") == %{composition_origin: "indic"}
    end

    test "撰 means composed, so the work originates where its author did" do
      # 唐 王勃撰 — Wang Bo, a Tang poet. The work is Chinese, not a translation, and the
      # byline is the only thing in the file that says so.
      assert Byline.provenance("唐 王勃撰") == %{composition_origin: "chinese"}
      assert Byline.provenance("宋 契嵩述") == %{composition_origin: "chinese"}
      assert Byline.provenance("明 智旭著") == %{composition_origin: "chinese"}
    end

    test "失譯 is still a translation — the translator is lost, not the fact" do
      assert Byline.provenance("失譯") == %{composition_origin: "indic"}
      assert Byline.provenance("失譯人名") == %{composition_origin: "indic"}
    end

    test "a Japanese author is Japanese even when they 撰" do
      # Checked BEFORE the verb, because a Japanese author composes too. X is published in
      # Japan and holds Japanese material beside the Chinese, so this is not hypothetical.
      assert Byline.provenance("日本 空海撰") == %{composition_origin: "japanese"}
      assert Byline.provenance("日本 源信述") == %{composition_origin: "japanese"}
    end
  end

  describe "what it refuses to decide" do
    test "never sets text_role" do
      # The verb says how a text ARRIVED. `text_role` says what it DOES — root, treatise,
      # commentary, history — and 撰 covers all of them. A guess here would mislabel
      # thousands of works in a field the API groups by.
      refute Map.has_key?(Byline.provenance("唐 王勃撰"), :text_role)
      refute Map.has_key?(Byline.provenance("唐 玄奘譯"), :text_role)
    end

    test "returns nothing rather than a guess for an unrecognised byline" do
      assert Byline.provenance("某人") == %{}
      assert Byline.provenance("") == %{}
      assert Byline.provenance("   ") == %{}
      assert Byline.provenance(nil) == %{}
    end
  end

  describe "verb/1" do
    test "reports what it matched on, so the rule can be audited" do
      # A caller checking a provenance label is entitled to see the evidence, not only
      # the conclusion.
      assert Byline.verb("唐 玄奘譯") == "譯"
      assert Byline.verb("唐 王勃撰") == "撰"
      assert Byline.verb("某人") == nil
    end
  end

  describe "the division table still wins for the Taishō" do
    test "a Taishō target is decided by number, not by byline" do
      # The 部 table is work-number-precise; the byline is a per-work inference. Where they
      # disagree that is a question for a scholar, not something to settle by whichever
      # rule ran last. T0001 is 阿含部 — Indic root scripture.
      assert %{composition_origin: "indic", division: "阿含部"} =
               Divisions.provenance_for_target(%{
                 canon: "T",
                 number: "0001",
                 volume: 1,
                 author: "唐 王勃撰"
               })
    end

    test "a non-Taishō target falls through to the byline" do
      assert %{composition_origin: "chinese"} =
               Divisions.provenance_for_target(%{
                 canon: "X",
                 number: "1508",
                 volume: 75,
                 author: "唐 王勃撰"
               })
    end
  end
end
