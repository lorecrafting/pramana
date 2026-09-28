defmodule Pramana.ReviewerScopeFixture do
  @moduledoc false

  def scope_input do
    demand_roots =
      for n <- 0..9 do
        work("T02" <> String.pad_leading(Integer.to_string(n), 2, "0"), "root", 100 + n)
      end

    citers =
      for n <- 0..9 do
        work("T17" <> String.pad_leading(Integer.to_string(n), 2, "0"), "commentary", 500 + n)
      end

    agamas = for id <- ~w(T0001 T0026 T0099 T0125), do: work(id, "root", 100)

    quotation_rows =
      Enum.zip(citers, demand_roots)
      |> Enum.map(fn {citer, root} ->
        %{
          a_work_id: citer.work_id,
          b_work_id: root.work_id,
          text_sha256: hash(citer.work_id <> root.work_id),
          length: 20
        }
      end)

    base_relation = %{
      source_work_id: "T1800",
      target_work_id: "T0400",
      target_work_ref: nil,
      relation: "comments_on",
      scope: "whole_work",
      target_urn: nil,
      confidence: "uncertain",
      method: "shared_text",
      evidence: %{"fixture" => true},
      review_status: "needs_review",
      review_reason: "Edition identity is disputed"
    }

    %{
      release: %{
        release_id: "review-release",
        source_bake_id: "review-bake",
        translation_set_id: "v2:review-translation",
        vector_set_id: "v2:review-vector",
        stamped_at: "2026-09-28T00:00:00Z"
      },
      works:
        agamas ++
          demand_roots ++
          citers ++
          [work("T1800", "commentary", 600), work("T0400", "root", 100)],
      quotation_rows: quotation_rows,
      relation_rows: [
        base_relation,
        %{
          base_relation
          | target_work_id: "T0200",
            method: "title_match",
            confidence: "certain",
            review_status: "unflagged",
            review_reason: nil
        }
      ],
      alignment_rows: []
    }
  end

  defp work(id, role, date_start) do
    title =
      Map.get(
        %{
          "T0001" => "長阿含經",
          "T0026" => "中阿含經",
          "T0099" => "雜阿含經",
          "T0125" => "增壹阿含經",
          "T1800" => "first commentary",
          "T0400" => "alternative root"
        },
        id,
        id
      )

    %{
      work_id: id,
      title: title,
      text_role: role,
      division:
        cond do
          id in ~w(T0001 T0026 T0099 T0125) -> "阿含部"
          role == "root" -> "經集部"
          true -> "經疏部"
        end,
      date_start: date_start,
      date_end: date_start + 50
    }
  end

  defp hash(value), do: value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
