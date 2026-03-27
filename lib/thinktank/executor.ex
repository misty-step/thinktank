defmodule Thinktank.Executor do
  @moduledoc """
  Chooses the configured executor backend for a workflow fanout stage.
  """

  alias Thinktank.{Config, RunContract}
  alias Thinktank.Executor.{Agentic, Direct}

  @spec run([Thinktank.AgentSpec.t()], RunContract.t(), map(), Config.t(), keyword()) :: [map()]
  def run(agents, %RunContract{mode: :quick} = contract, context, config, opts) do
    Direct.run(agents, contract, context, config, opts)
  end

  def run(agents, %RunContract{mode: :deep} = contract, context, config, opts) do
    Agentic.run(agents, contract, context, config, opts)
  end
end
