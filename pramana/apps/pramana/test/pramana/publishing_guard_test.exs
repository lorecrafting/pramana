defmodule Pramana.Publishing.GuardTest do
  @moduledoc """
  The public artefact is a separate bake into a separate database, and that is the real
  protection. What it does not protect against is **one wrong environment variable**: a
  `DATABASE_URL` pointing at the research corpus starts a perfectly healthy node that
  serves CBETA to the public and reports nothing.

  `verify/0` is tested rather than the boot path, because the boot path's whole job is to
  stop the node and a test suite that stops itself proves nothing.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Publishing.Guard
  alias Pramana.Repo

  setup do
    previous = System.get_env("PRAMANA_PUBLIC")
    System.delete_env("PRAMANA_PUBLIC")

    on_exit(fn ->
      if is_nil(previous),
        do: System.delete_env("PRAMANA_PUBLIC"),
        else: System.put_env("PRAMANA_PUBLIC", previous)
    end)

    :ok
  end

  defp source!(id, redistributable) do
    Repo.insert!(%Pramana.Corpus.Source{
      id: id,
      name: id,
      license_spdx: if(redistributable, do: "CC0-1.0", else: "LicenseRef-CBETA-NC"),
      license_class: if(redistributable, do: "cc0", else: "nc"),
      commercial_use: redistributable,
      redistributable: redistributable
    })
  end

  defp text!(source_id, work_id) do
    Repo.insert!(%Pramana.Corpus.Witness{id: "w-#{work_id}", name: "w"})
    Repo.insert!(%Pramana.Corpus.Work{id: work_id, title: work_id})

    Repo.insert!(%Pramana.Corpus.Text{
      work_id: work_id,
      source_id: source_id,
      witness_id: "w-#{work_id}",
      urn_prefix: "pramana:#{source_id}.w:#{work_id}",
      body: "x",
      body_sha256: "x",
      meta: %{}
    })
  end

  describe "verify/0" do
    test "allows an empty database" do
      # Nothing present cannot leak. Vacuous, and the honest answer.
      assert Guard.verify() == :ok
    end

    test "allows a corpus of redistributable sources only" do
      source!("sc", true)
      text!("sc", "mn1")

      assert Guard.verify() == :ok
    end

    test "refuses a corpus holding one source it may not publish" do
      source!("sc", true)
      source!("cbeta", false)
      text!("sc", "mn1")
      text!("cbeta", "T0262")

      assert {:error, [forbidden]} = Guard.verify()
      assert forbidden.id == "cbeta"
      assert forbidden.rows == 1
    end

    # A conservative flag and a forbidding licence are different facts, and only the second
    # may stop a node. Refusing to boot over content that is merely unconfirmed would make
    # the check something operators learn to work around.
    test "does not refuse over content withheld by uncertainty rather than by licence" do
      source!("sc", true)
      text!("sc", "mn1")

      Repo.insert_all("translations", [
        %{
          anchor_urn: "pramana:sc.w:mn1@1.1",
          work_id: "mn1",
          lang: "en",
          translator_id: "sujato",
          tier: "t0",
          method: "human",
          text: "So I have heard.",
          text_sha256: "x",
          review_state: "raw",
          license_spdx: "CC0-1.0",
          redistributable: false,
          meta: %{},
          inserted_at: DateTime.utc_now() |> DateTime.to_naive(),
          updated_at: DateTime.utc_now() |> DateTime.to_naive()
        }
      ])

      assert Guard.verify() == :ok
    end
  end

  describe "public?/0" do
    # `nil` rather than a no-op child: a research node's supervision tree should not carry
    # a process whose purpose is to do nothing, and the difference is visible in `:sys`.
    test "a research node gets no child at all, not an inert one" do
      System.delete_env("PRAMANA_PUBLIC")

      assert Guard.child_spec_if_public() == nil
    end

    test "a public node gets a temporary child, since a check that has run is not a service" do
      System.put_env("PRAMANA_PUBLIC", "1")

      assert %{id: Guard, restart: :temporary, start: {Guard, :verify_and_ignore, []}} =
               Guard.child_spec_if_public()
    after
      System.delete_env("PRAMANA_PUBLIC")
    end

    # The refusing branch calls `System.stop/1` and cannot be exercised without ending the
    # test run, which is the point of it. The passing branch can: it must return `:ignore`
    # so the supervisor records no child.
    test "on a safe corpus it starts nothing and reports :ignore" do
      assert Guard.verify() == :ok
      assert Guard.verify_and_ignore() == :ignore
    end

    test "is off unless the node declares itself public" do
      # A research node holds restricted text by design and must start normally.
      refute Guard.public?()
    end
  end
end
