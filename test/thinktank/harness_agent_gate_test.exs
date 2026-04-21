defmodule Thinktank.HarnessAgentGateTest do
  use ExUnit.Case, async: false

  defp repo_root do
    Path.expand("../..", __DIR__)
  end

  defp gate_script do
    Path.join(repo_root(), "scripts/ci/harness-agent-gate.sh")
  end

  defp unique_agent_path do
    filename = "zzz-harness-agent-gate-#{System.unique_integer([:positive])}.md"
    path = Path.join([repo_root(), ".claude", "agents", filename])
    File.mkdir_p!(Path.dirname(path))
    path
  end

  defp with_temp_agent_file(content, fun) do
    path = unique_agent_path()
    File.write!(path, content)

    on_exit(fn ->
      File.rm(path)
    end)

    fun.(Path.relative_to(path, repo_root()))
  end

  test "rejects agent frontmatter that hardcodes a model field" do
    with_temp_agent_file(
      """
      ---
      model: gpt-5
      ---

      # Temporary Agent
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "must not declare model or reasoning selection fields"
        assert output =~ relative_path
      end
    )
  end

  test "rejects concrete model family mentions in agent prose" do
    with_temp_agent_file(
      """
      # Temporary Agent

      Prefer gpt-5-class models when available.
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "must not mention concrete model families by name"
        assert output =~ relative_path
      end
    )
  end

  test "accepts lens-only agent prose" do
    with_temp_agent_file(
      """
      # Temporary Agent

      This persona defines a review lens only. Model selection belongs to the caller/runtime.
      """,
      fn _relative_path ->
        {output, status} =
          System.cmd(gate_script(), [],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 0
        assert output =~ "PASS: harness agent gate passed."
      end
    )
  end
end
