defmodule Thinktank.ArchitectureGateTest do
  use ExUnit.Case, async: false

  defp repo_root do
    Path.expand("../..", __DIR__)
  end

  defp gate_script do
    Path.join(repo_root(), "scripts/ci/architecture-gate.sh")
  end

  defp unique_lib_path do
    unique = System.unique_integer([:positive])
    filename = "zzz-architecture-gate-#{unique}.ex"
    path = Path.join([repo_root(), "lib", filename])

    module_name = "ZzzArchitectureGate#{unique}"

    {path, module_name}
  end

  defp with_temp_lib_file(content_fun, fun) do
    {path, module_name} = unique_lib_path()
    File.write!(path, content_fun.(module_name))

    on_exit(fn ->
      File.rm(path)
    end)

    fun.(Path.relative_to(path, repo_root()))
  end

  test "rejects System.cmd/3 outside shared policy boundaries" do
    with_temp_lib_file(
      fn module_name ->
        """
        defmodule #{module_name} do
          def run, do: System.cmd("git", ["status"])
        end
        """
      end,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "System.cmd is only allowed"
        assert output =~ relative_path
      end
    )
  end

  test "checks the artifact layout registry" do
    {output, status} =
      System.cmd(gate_script(), [],
        cd: repo_root(),
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "architecture-gate: checking artifact layout registry"
    assert output =~ "PASS: architecture gate passed."
  end
end
