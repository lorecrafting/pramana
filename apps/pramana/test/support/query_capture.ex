defmodule Pramana.QueryCapture do
  @moduledoc "Capture synchronous Repo queries issued by the calling test process."

  def capture(fun) do
    parent = self()
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        [:pramana, :repo, :query],
        fn _, _, meta, _ ->
          if self() == parent, do: send(parent, {ref, meta.query})
        end,
        nil
      )

    result =
      try do
        fun.()
      after
        :telemetry.detach(ref)
      end

    {result, drain(ref, [])}
  end

  defp drain(ref, acc) do
    receive do
      {^ref, query} -> drain(ref, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
