defmodule Thinktank.CLIEngineBoundaryTest do
  use ExUnit.Case, async: true

  alias Thinktank.{CLI, Engine}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  test "parsed research commands resolve into the same engine run shape" do
    cwd = unique_tmp_dir("thinktank-cli-engine-boundary")
    output_dir = Path.join(cwd, "captured-run")
    paths_root = Path.join(cwd, "lib")

    File.mkdir_p!(paths_root)

    assert {:ok, command} =
             CLI.parse_args([
               "research",
               "inspect",
               "this",
               "--paths",
               paths_root,
               "--agents",
               "systems,dx",
               "--output",
               output_dir,
               "--no-synthesis"
             ])

    assert {:ok, resolved} =
             Engine.resolve(command.bench_id, command.input,
               cwd: cwd,
               output: command.output,
               config: command.config
             )

    assert resolved.output_dir == Path.expand(output_dir)
    assert resolved.contract.artifact_dir == Path.expand(output_dir)
    assert resolved.contract.workspace_root == cwd
    assert resolved.contract.input["input_text"] == "inspect this"
    assert resolved.contract.input["paths"] == [Path.expand(paths_root)]
    assert resolved.contract.input["agents"] == ["systems", "dx"]
    assert resolved.contract.input["no_synthesis"] == true
    assert Enum.map(resolved.agents, & &1.name) == ["systems", "dx"]
  end
end
