defmodule Thinktank.ApplicationTest do
  use ExUnit.Case, async: true

  test "application starts successfully" do
    assert {:ok, _pid} = Application.ensure_all_started(:thinktank)
  end

  test "AgentSupervisor is running under the supervision tree" do
    {:ok, _} = Application.ensure_all_started(:thinktank)
    pid = Process.whereis(Thinktank.AgentSupervisor)
    assert is_pid(pid)
    assert Process.alive?(pid)
  end
end
