defmodule Thinktank.Executor.OutputCollector do
  @moduledoc false

  defstruct sink: nil, chunks: []
end

defimpl Collectable, for: Thinktank.Executor.OutputCollector do
  def into(%Thinktank.Executor.OutputCollector{} = collector) do
    sink = collector.sink

    collector_fun = fn
      %Thinktank.Executor.OutputCollector{chunks: chunks} = acc, {:cont, chunk} ->
        if is_function(sink, 1) and is_binary(chunk) and chunk != "" do
          sink.(chunk)
        end

        %{acc | chunks: [chunk | chunks]}

      %Thinktank.Executor.OutputCollector{chunks: chunks}, :done ->
        chunks
        |> Enum.reverse()
        |> IO.iodata_to_binary()

      _acc, :halt ->
        :ok
    end

    {collector, collector_fun}
  end
end
