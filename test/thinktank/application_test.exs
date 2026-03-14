defmodule Thinktank.ApplicationTest do
  use ExUnit.Case, async: true

  test "application starts successfully" do
    assert {:ok, _pid} = Application.ensure_all_started(:thinktank)
  end
end
