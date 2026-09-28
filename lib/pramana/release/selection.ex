defmodule Pramana.Release.Selection do
  @moduledoc "The singleton selected release; separate from immutable release identities."
  use Ecto.Schema

  schema "release_selection" do
    belongs_to(:release, Pramana.Corpus.Release)
    field(:selected_at, :utc_datetime_usec)
  end
end
