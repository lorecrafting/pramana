defmodule Pramana.Repo.Migrations.AddByteOffsets do
  use Ecto.Migration

  @moduledoc """
  Segments carry BOTH character and byte offsets into `texts.body`.

  Character offsets are what clients need: Classical Chinese is multi-byte throughout,
  and a JS or Python client slicing by codepoint would mis-cut on byte offsets.

  Byte offsets are what the server needs: `String.slice/3` is O(n) because it must
  walk the binary counting codepoints, so resolving one citation costs a full scan of
  the text body. `binary_part/3` is O(1). Verifying every segment of the Lotus Sūtra
  took 18.5s by character offset; by byte offset it is milliseconds, and the citation
  guard runs on every answer.

  Storing both is a few bytes per row and removes a scaling problem.
  """

  def change do
    alter table(:segments) do
      add :byte_start, :integer
      add :byte_end, :integer
    end
  end
end
