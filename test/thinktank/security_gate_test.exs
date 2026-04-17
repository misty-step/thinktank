defmodule Thinktank.SecurityGateTest do
  use ExUnit.Case, async: false

  defp repo_root do
    Path.expand("../..", __DIR__)
  end

  defp gate_script do
    Path.join(repo_root(), "scripts/ci/security-gate.sh")
  end

  defp unique_lib_path do
    filename = "zzz-security-gate-#{System.unique_integer([:positive])}.ex"
    path = Path.join([repo_root(), "lib", filename])
    File.write!(path, "")

    on_exit(fn ->
      File.rm(path)
    end)

    path
  end

  defp with_temp_lib_file(content, fun) do
    path = unique_lib_path()
    File.write!(path, content)
    fun.(Path.relative_to(path, repo_root()))
  end

  test "rejects dynamic evaluation in runtime code" do
    with_temp_lib_file(
      """
      defmodule SecurityGateFixture do
        def run(input), do: Code.eval_string(input)
      end
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "dynamic execution API detected"
        assert output =~ relative_path
      end
    )
  end

  test "rejects System.cmd/3 outside approved runtime boundaries" do
    with_temp_lib_file(
      """
      defmodule SecurityGateFixture do
        def run, do: System.cmd("git", ["status"])
      end
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "System.cmd/3 is only allowed"
        assert output =~ relative_path
      end
    )
  end

  test "allows known runtime boundaries that use System.cmd/3" do
    {output, status} =
      System.cmd(
        gate_script(),
        ["lib/thinktank/review/context.ex", "lib/thinktank/executor/agentic.ex"],
        cd: repo_root(),
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "PASS: security gate passed."
  end
end
