defmodule Thinktank.ReviewWorkflowTest do
  use ExUnit.Case, async: false

  alias Thinktank.Engine

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> flunk("git #{Enum.join(args, " ")} failed: #{output}")
    end
  end

  defp review_output(agent, verdict, severity) do
    Jason.encode!(%{
      reviewer: agent,
      perspective: agent,
      verdict: verdict,
      confidence: 0.9,
      summary: "#{agent} summary",
      findings:
        if verdict == "PASS" do
          []
        else
          [
            %{
              severity: severity,
              category: "logic",
              title: "#{agent} finding",
              description: "Problem",
              suggestion: "Fix it",
              file: "lib/app.ex",
              line: 12
            }
          ]
        end,
      stats: %{
        files_reviewed: 1,
        files_with_issues: if(verdict == "PASS", do: 0, else: 1),
        critical: if(severity == "critical", do: 1, else: 0),
        major: if(severity == "major", do: 1, else: 0),
        minor: 0,
        info: 0
      }
    })
  end

  test "runs local diff review workflow and aggregates verdicts" do
    tmp = unique_tmp_dir("thinktank-review")
    branch_name = "feature-#{System.unique_integer([:positive, :monotonic])}"
    File.write!(Path.join(tmp, "lib_app.ex"), "defmodule App do\n  def ok, do: :ok\nend\n")

    git!(tmp, ["init", "-b", "main"])
    git!(tmp, ["config", "user.email", "test@example.com"])
    git!(tmp, ["config", "user.name", "ThinkTank Test"])
    git!(tmp, ["add", "."])
    git!(tmp, ["commit", "-m", "base"])
    git!(tmp, ["checkout", "-b", branch_name])

    File.write!(
      Path.join(tmp, "lib_app.ex"),
      "defmodule App do\n  def ok(user), do: user.token\nend\n"
    )

    git!(tmp, ["add", "."])
    git!(tmp, ["commit", "-m", "change"])

    test_pid = self()

    runner = fn _cmd, ["-c", shell_cmd | args], _opts ->
      send(test_pid, {:shell_cmd, shell_cmd, args})

      [_, prompt_file] =
        Enum.chunk_every(args, 2, 1, :discard) |> Enum.find(fn [flag, _value] -> flag == "-p" end)

      prompt = File.read!(String.trim_leading(prompt_file, "@"))

      output =
        cond do
          prompt =~ "You are guard" ->
            "Guard analysis\n```json\n#{review_output("guard", "FAIL", "critical")}\n```"

          prompt =~ "You are trace" ->
            "Trace analysis\n```json\n#{review_output("trace", "PASS", "info")}\n```"

          true ->
            "Atlas analysis\n```json\n#{review_output("atlas", "PASS", "info")}\n```"
        end

      {output, 0}
    end

    assert {:ok, result} =
             Engine.run(
               "review/cerberus",
               %{base: "main", head: "HEAD"},
               cwd: tmp,
               mode: :deep,
               runner: runner,
               agent_config_dir: nil
             )

    assert result.context.review_route.panel |> Enum.take(2) == ["trace", "guard"]
    assert result.context.final_verdict.verdict == "FAIL"
    assert File.exists?(Path.join(result.output_dir, "verdict.json"))
    assert File.exists?(Path.join(result.output_dir, "review.md"))
    assert_receive {:shell_cmd, shell_cmd, args}
    assert shell_cmd == "exec < /dev/null; exec \"$@\""
    assert Enum.member?(args, "--tools")
    assert Enum.member?(args, "read,grep,find,ls")
    refute Enum.any?(args, &String.contains?(&1, "```diff"))
  end

  test "review workflow rejects non-agentic mode requests" do
    tmp = unique_tmp_dir("thinktank-review-mode")

    assert {:error, {:mode_not_allowed, "review/cerberus", :quick, :deep}, nil} =
             Engine.run(
               "review/cerberus",
               %{base: "main", head: "HEAD"},
               cwd: tmp,
               mode: :quick
             )
  end

  test "review workflow rejects incomplete PR review inputs" do
    tmp = unique_tmp_dir("thinktank-review-pr")

    assert {:error, {:stage_failed, "prepare", {:pr_review_requires_repo, 42}}, _output_dir} =
             Engine.run(
               "review/cerberus",
               %{pr: 42},
               cwd: tmp,
               mode: :deep
             )
  end

  test "local diff review still works from detached HEAD" do
    tmp = unique_tmp_dir("thinktank-review-detached")
    File.write!(Path.join(tmp, "lib_app.ex"), "defmodule App do\n  def ok, do: :ok\nend\n")

    git!(tmp, ["init", "-b", "main"])
    git!(tmp, ["config", "user.email", "test@example.com"])
    git!(tmp, ["config", "user.name", "ThinkTank Test"])
    git!(tmp, ["add", "."])
    git!(tmp, ["commit", "-m", "base"])

    File.write!(
      Path.join(tmp, "lib_app.ex"),
      "defmodule App do\n  def ok(user), do: user.token\nend\n"
    )

    git!(tmp, ["add", "."])
    git!(tmp, ["commit", "-m", "change"])
    git!(tmp, ["checkout", "--detach", "HEAD"])

    runner = fn _cmd, ["-c", _shell_cmd | args], _opts ->
      [_, prompt_file] =
        Enum.chunk_every(args, 2, 1, :discard) |> Enum.find(fn [flag, _value] -> flag == "-p" end)

      prompt = File.read!(String.trim_leading(prompt_file, "@"))

      output =
        if prompt =~ "You are trace" do
          "Trace analysis\n```json\n#{review_output("trace", "PASS", "info")}\n```"
        else
          "Atlas analysis\n```json\n#{review_output("atlas", "PASS", "info")}\n```"
        end

      {output, 0}
    end

    assert {:ok, result} =
             Engine.run(
               "review/cerberus",
               %{base: "HEAD~1", head: "HEAD"},
               cwd: tmp,
               mode: :deep,
               runner: runner,
               agent_config_dir: nil
             )

    assert result.context.final_verdict.verdict == "PASS"
  end
end
