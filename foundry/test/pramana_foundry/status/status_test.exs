defmodule PramanaFoundry.StatusTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Status

  @orig_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @new_rev "1234567890123456789012345678901234567890"

  describe "revision visibility" do
    test "reports matching revisions initially" do
      state = %{"accepted_revision" => @orig_rev}
      report = Status.report(state, runtime_implementation_revision: @orig_rev)

      assert report["accepted_revision"] == @orig_rev
      assert report["runtime_implementation_revision"] == @orig_rev
      assert report["revisions_match?"] == true
      assert report["revision_labels_authoritative?"] == false
      refute Map.has_key?(report, "revision_disagreement")
    end

    test "visibly disagrees when accepted revision advances beyond running implementation" do
      # Accepted revision advanced to @new_rev via integration, but runtime was booted at @orig_rev
      state = %{"accepted_revision" => @new_rev}
      report = Status.report(state, runtime_implementation_revision: @orig_rev)

      assert report["accepted_revision"] == @new_rev
      assert report["runtime_implementation_revision"] == @orig_rev
      assert report["revisions_match?"] == false
      assert report["revision_disagreement"] =~ "controlled restart required"
      assert report["revision_disagreement"] =~ @orig_rev
      assert report["revision_disagreement"] =~ @new_rev
    end
  end
end
