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

  defp write_mock_pi!(dir, log_path) do
    pi_path = Path.join(dir, "pi")

    File.write!(
      pi_path,
      """
      #!/bin/sh
      prompt_file=""
      model=""
      thinking=""
      tools=""

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --model)
            model="$2"
            shift 2
            ;;
          --thinking)
            thinking="$2"
            shift 2
            ;;
          --tools)
            tools="$2"
            shift 2
            ;;
          -p)
            prompt_file="$2"
            shift 2
            ;;
          *)
            shift
            ;;
        esac
      done

      prompt_path="${prompt_file#@}"
      reviewer="trace"

      if grep -q "You are guard" "$prompt_path"; then
        reviewer="guard"
      elif grep -q "You are atlas" "$prompt_path"; then
        reviewer="atlas"
      elif grep -q "You are proof" "$prompt_path"; then
        reviewer="proof"
      fi

      {
        printf 'cwd=%s\\n' "$PWD"
        printf 'pi_home=%s\\n' "$PI_CODING_AGENT_DIR"
        printf 'model=%s\\n' "$model"
        printf 'thinking=%s\\n' "$thinking"
        printf 'tools=%s\\n' "$tools"
        printf 'prompt=%s\\n' "$prompt_path"
        printf '%s\\n' '--'
      } >> "#{log_path}"

      export REVIEWER="$reviewer"

      cat <<'EOF'
      Review
      ```json
      {"reviewer":"$REVIEWER","perspective":"$REVIEWER","verdict":"PASS","confidence":0.9,"summary":"ok","findings":[],"stats":{"files_reviewed":1,"files_with_issues":0,"critical":0,"major":0,"minor":0,"info":0}}
      ```
      EOF
      """
    )

    File.chmod!(pi_path, 0o755)
    pi_path
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
    assert Enum.member?(args, "--thinking")
    assert Enum.member?(args, "medium")
    assert Enum.member?(args, "--tools")
    assert Enum.member?(args, "read,grep,find,ls")
    refute Enum.any?(args, &String.contains?(&1, "```diff"))
  end

  test "review workflow exercises the real subprocess path with a mock pi binary" do
    tmp = unique_tmp_dir("thinktank-review-subprocess")
    bin_dir = Path.join(tmp, "bin")
    log_path = Path.join(tmp, "pi.log")
    branch_name = "feature-#{System.unique_integer([:positive, :monotonic])}"

    File.mkdir_p!(bin_dir)
    write_mock_pi!(bin_dir, log_path)
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

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{bin_dir}:#{original_path}")

    on_exit(fn ->
      System.put_env("PATH", original_path)
    end)

    assert {:ok, result} =
             Engine.run(
               "review/cerberus",
               %{base: "main", head: "HEAD"},
               cwd: tmp,
               mode: :deep,
               agent_config_dir: nil
             )

    log = File.read!(log_path)

    assert result.context.final_verdict.verdict == "PASS"
    assert File.exists?(Path.join(result.output_dir, "verdict.json"))
    assert File.exists?(Path.join(result.output_dir, "review.md"))
    assert log =~ "cwd="
    assert log =~ Path.basename(tmp)
    assert log =~ "tools=read,grep,find,ls"
    assert log =~ "thinking=medium"
    assert log =~ "thinking=low"
    assert log =~ "prompt=#{Path.join(result.output_dir, "prompts")}"
    assert log =~ "pi_home=#{Path.join(result.output_dir, "pi-home")}"
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

  test "review workflow marks malformed reviewer output as invalid without crashing" do
    tmp = unique_tmp_dir("thinktank-review-malformed")
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

    runner = fn _cmd, ["-c", _shell_cmd | args], _opts ->
      [_, prompt_file] =
        Enum.chunk_every(args, 2, 1, :discard) |> Enum.find(fn [flag, _value] -> flag == "-p" end)

      prompt = File.read!(String.trim_leading(prompt_file, "@"))

      output =
        if prompt =~ "You are trace" do
          "Trace analysis without a verdict block"
        else
          "Review\n```json\n#{review_output("reviewer", "PASS", "info")}\n```"
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

    assert result.context.final_verdict.verdict == "PASS"
    assert Enum.any?(result.context.parsed_reviews, &(&1.status == :parse_error))
  end

  test "review workflow handles empty diffs without forcing code-review routes" do
    tmp = unique_tmp_dir("thinktank-review-empty")
    File.write!(Path.join(tmp, "lib_app.ex"), "defmodule App do\n  def ok, do: :ok\nend\n")

    git!(tmp, ["init", "-b", "main"])
    git!(tmp, ["config", "user.email", "test@example.com"])
    git!(tmp, ["config", "user.name", "ThinkTank Test"])
    git!(tmp, ["add", "."])
    git!(tmp, ["commit", "-m", "base"])

    runner = fn _cmd, _args, _opts ->
      {"Review\n```json\n#{review_output("reviewer", "PASS", "info")}\n```", 0}
    end

    assert {:ok, result} =
             Engine.run(
               "review/cerberus",
               %{base: "HEAD", head: "HEAD"},
               cwd: tmp,
               mode: :deep,
               runner: runner,
               agent_config_dir: nil
             )

    assert result.context.final_verdict.verdict == "PASS"
    assert result.context.diff_summary.total_changed_lines == 0
    assert result.context.review_route.code_changed == false
    refute Enum.member?(result.context.review_route.panel, "guard")
  end

  test "review workflow propagates agent timeouts as invalid reviewer results" do
    tmp = unique_tmp_dir("thinktank-review-timeout")
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

    runner = fn _cmd, ["-c", _shell_cmd | args], _opts ->
      [_, prompt_file] =
        Enum.chunk_every(args, 2, 1, :discard) |> Enum.find(fn [flag, _value] -> flag == "-p" end)

      prompt = File.read!(String.trim_leading(prompt_file, "@"))

      if prompt =~ "You are proof" do
        {"partial output", :timeout}
      else
        {"Review\n```json\n#{review_output("reviewer", "PASS", "info")}\n```", 0}
      end
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

    assert result.context.final_verdict.verdict == "PASS"
    assert Enum.any?(result.context.parsed_reviews, &(&1.status == :runtime_error))
  end
end
