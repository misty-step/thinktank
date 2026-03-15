defmodule Thinktank.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Thinktank.AgentSupervisor}
    ]
    opts = [strategy: :one_for_one, name: Thinktank.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
