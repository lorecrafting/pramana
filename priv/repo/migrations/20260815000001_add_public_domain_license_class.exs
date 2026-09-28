defmodule Pramana.Repo.Migrations.AddPublicDomainLicenseClass do
  @moduledoc """
  Adds `public-domain` to the allowed licence classes.

  The original set assumed every free licence was a Creative Commons *grant*. Public
  Domain Mark is not a grant: it asserts the work is already free of known copyright
  restrictions. SuttaCentral applies it to the Mahāsaṅgīti Pāli root text (`scpub64`)
  while the repository's own LICENSE.md says CC0, so recording it as `cc0` would be
  restating the claim we deliberately went and checked.

  This surfaced as a check-constraint violation on ingest, which is the constraint doing
  its job — a licence class that is not enumerated is one nothing can reason about.
  """

  use Ecto.Migration

  @classes ~w(cc0 public-domain cc-by cc-by-sa nc restricted unknown)

  def up do
    drop constraint(:sources, :license_class_known)

    create constraint(:sources, :license_class_known,
             check: "license_class IN (#{quoted(@classes)})"
           )
  end

  def down do
    # Anything already recorded as public-domain would violate the narrower constraint,
    # and silently rewriting it to cc0 would assert a licence the source does not claim.
    execute("DELETE FROM sources WHERE license_class = 'public-domain'")

    drop constraint(:sources, :license_class_known)

    create constraint(:sources, :license_class_known,
             check: "license_class IN (#{quoted(@classes -- ["public-domain"])})"
           )
  end

  defp quoted(classes), do: Enum.map_join(classes, ",", &"'#{&1}'")
end
