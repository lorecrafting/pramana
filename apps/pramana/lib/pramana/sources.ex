defmodule Pramana.Sources do
  @moduledoc """
  Registry of upstream corpus sources and their licenses.

  License data is structured, not free text, because `license_class` drives
  redistribution decisions that must be enforceable in a query. See
  `docs/SOURCES.md` and the licensing posture section of `CLAUDE.md`:
  **we publish the pipeline, not the corpus.**
  """

  @type license :: %{
          spdx: String.t(),
          class: String.t(),
          commercial_use: boolean(),
          redistributable: boolean(),
          notice: String.t() | nil
        }

  @type t :: %{
          id: String.t(),
          name: String.t(),
          upstream_url: String.t(),
          repo: String.t() | nil,
          license: license()
        }

  @sources %{
    "cbeta" => %{
      id: "cbeta",
      name: "CBETA Chinese Buddhist Electronic Tripitaka (XML P5)",
      upstream_url: "https://github.com/cbeta-org/xml-p5",
      repo: "cbeta-org/xml-p5",
      license: %{
        spdx: "LicenseRef-CBETA-NC",
        class: "nc",
        commercial_use: false,
        redistributable: false,
        notice: "Available for non-commercial use when distributed with this header intact."
      }
    },
    "sat" => %{
      id: "sat",
      name: "SAT Daizōkyō Text Database",
      upstream_url: "https://21dzk.l.u-tokyo.ac.jp/SAT/",
      repo: nil,
      license: %{
        spdx: "CC-BY-SA-4.0",
        class: "cc-by-sa",
        commercial_use: true,
        redistributable: true,
        notice: nil
      }
    },
    "sc" => %{
      id: "sc",
      name: "SuttaCentral bilara-data",
      upstream_url: "https://github.com/suttacentral/bilara-data",
      repo: "suttacentral/bilara-data",
      license: %{
        spdx: "CC0-1.0",
        class: "cc0",
        commercial_use: true,
        redistributable: true,
        notice: nil
      }
    }
  }

  @doc "Fetches a source definition by id."
  @spec fetch(String.t()) :: {:ok, t()} | {:error, :unknown_source}
  def fetch(id) when is_binary(id) do
    case Map.fetch(@sources, id) do
      {:ok, source} -> {:ok, source}
      :error -> {:error, :unknown_source}
    end
  end

  @doc "All known source ids."
  @spec ids() :: [String.t()]
  def ids, do: Map.keys(@sources)

  @doc """
  True when a source's content may be redistributed by us.

  Nothing in this project should ever republish corpus text for which this is false.
  """
  @spec redistributable?(t()) :: boolean()
  def redistributable?(%{license: %{redistributable: value}}), do: value
end
