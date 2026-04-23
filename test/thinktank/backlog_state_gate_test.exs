defmodule Thinktank.BacklogStateGateTest do
  use ExUnit.Case, async: false

  defp repo_root do
    Path.expand("../..", __DIR__)
  end

  defp gate_script do
    Path.join(repo_root(), "scripts/ci/backlog-state-gate.sh")
  end

  defp unique_backlog_path(dir) do
    filename = "zzz-backlog-gate-#{System.unique_integer([:positive])}.md"
    path = Path.join([repo_root(), dir, filename])
    File.mkdir_p!(Path.dirname(path))
    path
  end

  defp with_temp_backlog_file(dir, content, fun) do
    path = unique_backlog_path(dir)
    File.write!(path, content)

    on_exit(fn ->
      File.rm(path)
    end)

    fun.(Path.relative_to(path, repo_root()))
  end

  test "rejects top-level backlog items marked done" do
    with_temp_backlog_file(
      "backlog.d",
      """
      # Temporary Item

      Priority: high
      Status: done
      Estimate: S
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "top-level backlog item marked done"
      end
    )
  end

  test "rejects backlog items without a status field" do
    with_temp_backlog_file(
      "backlog.d",
      """
      # Temporary Item

      Priority: high
      Estimate: S
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "missing Status: field"
      end
    )
  end

  test "accepts done items that live under backlog.d/done" do
    with_temp_backlog_file(
      "backlog.d/done",
      """
      # Temporary Item

      Priority: high
      Status: done
      Estimate: S
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 0
        assert output =~ "PASS: backlog state gate passed."
      end
    )
  end

  test "rejects active items without repo anchors" do
    with_temp_backlog_file(
      "backlog.d",
      """
      # Temporary Item

      Priority: high
      Status: ready
      Estimate: S
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "must list at least one live repo anchor"
      end
    )
  end

  test "rejects active items with stale repo anchors" do
    with_temp_backlog_file(
      "backlog.d",
      """
      # Temporary Item

      Priority: high
      Status: ready
      Estimate: S

      ## Repo Anchors
      - `lib/thinktank/does_not_exist.ex`
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "repo anchor does not exist"
        assert output =~ "lib/thinktank/does_not_exist.ex"
      end
    )
  end

  test "rejects unsupported active statuses" do
    with_temp_backlog_file(
      "backlog.d",
      """
      # Temporary Item

      Priority: high
      Status: blocked
      Estimate: S

      ## Repo Anchors
      - `mix.exs`
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 1
        assert output =~ "unsupported active Status 'blocked'"
      end
    )
  end

  test "ignores non-path code spans in repo anchor notes" do
    with_temp_backlog_file(
      "backlog.d",
      """
      # Temporary Item

      Priority: high
      Status: ready
      Estimate: S

      ## Repo Anchors
      - `mix.exs` carries the project contract.
      - Domain tags such as `security` and `correctness` are not file paths.
      """,
      fn relative_path ->
        {output, status} =
          System.cmd(gate_script(), [relative_path],
            cd: repo_root(),
            stderr_to_stdout: true
          )

        assert status == 0
        assert output =~ "PASS: backlog state gate passed."
      end
    )
  end
end
