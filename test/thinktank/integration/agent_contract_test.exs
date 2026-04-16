defmodule Thinktank.Integration.AgentContractTest do
  @moduledoc """
  Integration tests verifying the agent discovery contract:
  validate benches (JSON) -> list benches (JSON) -> pick one -> show it (JSON, full).
  Also tests structured error envelope output.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Thinktank.CLI
  alias Thinktank.Test.FakePi
  alias Thinktank.Test.Workspace

  @exit_codes CLI.exit_codes()
  @repo_root Path.expand("../../..", __DIR__)

  describe "agent discovery path" do
    test "validate benches exposes a machine-readable success payload" do
      {:ok, validate_cmd} = CLI.parse_args(["benches", "validate", "--json"])

      validate_output =
        capture_io(fn ->
          assert CLI.execute({:ok, validate_cmd}) == @exit_codes.success
        end)

      {:ok, validate_payload} = Jason.decode(String.trim(validate_output))
      assert validate_payload["status"] == "ok"
      assert is_integer(validate_payload["bench_count"])
      assert validate_payload["bench_count"] > 0
      assert Map.keys(validate_payload) |> Enum.sort() == ["bench_count", "status"]
    end

    test "list benches, pick one, show full spec — all JSON" do
      # Step 1: list benches as JSON
      {:ok, list_cmd} = CLI.parse_args(["benches", "list", "--json"])

      list_output =
        capture_io(fn ->
          assert CLI.execute({:ok, list_cmd}) == @exit_codes.success
        end)

      {:ok, benches} = Jason.decode(String.trim(list_output))
      assert [_ | _] = benches

      # Every bench entry has the required schema
      Enum.each(benches, fn bench ->
        assert is_binary(bench["id"])
        assert is_binary(bench["description"])
        assert is_binary(bench["kind"])
        assert is_integer(bench["agent_count"])
        assert bench["agent_count"] > 0
      end)

      # Step 2: pick one bench
      picked = List.first(benches)
      bench_id = picked["id"]

      # Step 3: show it with --full --json
      {:ok, show_cmd} = CLI.parse_args(["benches", "show", bench_id, "--full", "--json"])

      show_output =
        capture_io(fn ->
          assert CLI.execute({:ok, show_cmd}) == @exit_codes.success
        end)

      {:ok, detail} = Jason.decode(String.trim(show_output))
      assert detail["id"] == bench_id
      assert is_binary(detail["description"])
      assert is_binary(detail["kind"])
      assert is_list(detail["agents"])

      # Full agent specs have the required fields
      Enum.each(detail["agents"], fn agent ->
        assert is_binary(agent["name"]), "agent missing name"
        assert is_binary(agent["model"]), "agent #{agent["name"]} missing model"
        assert is_binary(agent["system_prompt"]), "agent #{agent["name"]} missing system_prompt"
        assert is_binary(agent["thinking_level"]), "agent #{agent["name"]} missing thinking_level"
        assert is_integer(agent["timeout_ms"]), "agent #{agent["name"]} missing timeout_ms"
        assert is_nil(agent["tools"]) or is_list(agent["tools"])
      end)

      # Agent count from list matches resolved agent count from show
      assert picked["agent_count"] == length(detail["agents"])
    end
  end

  describe "run contract" do
    test "help text documents all supported input modes" do
      output =
        capture_io(fn ->
          assert CLI.execute({:help, %{}}) == @exit_codes.success
        end)

      assert output =~ "Task text can come from --input, positional text, or piped stdin."

      assert File.read!(Path.join(@repo_root, "README.md")) =~
               Enum.join(
                 [
                   "Task text can come from `--input`, positional text on fixed commands like",
                   "`research`, or piped stdin."
                 ],
                 "\n"
               )
    end

    test "research can read stdin and expose output_dir and artifacts in JSON" do
      FakePi.with_fake_pi("success", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-run-contract")

        File.cd!(workspace, fn ->
          assert {:needs_stdin, command} =
                   CLI.parse_args(["research", "--json", "--no-synthesis", "--agents", "systems"])

          assert {:ok, command} =
                   CLI.read_stdin(command,
                     stdin_piped?: true,
                     reader: fn :stdio, :eof -> "inspect this repo\n" end
                   )

          {output, _stderr} =
            capture_stdout_and_stderr(fn ->
              assert CLI.execute({:ok, command}) == @exit_codes.success
            end)

          {:ok, payload} = Jason.decode(String.trim(output))

          assert Map.keys(payload) |> Enum.sort() == [
                   "agents",
                   "artifacts",
                   "bench",
                   "completed_at",
                   "duration_ms",
                   "error",
                   "output_dir",
                   "started_at",
                   "status",
                   "synthesis"
                 ]

          assert Map.take(payload, ["status", "output_dir", "error"]) == %{
                   "status" => "complete",
                   "output_dir" => payload["output_dir"],
                   "error" => nil
                 }

          assert is_list(payload["artifacts"])
          assert File.exists?(Path.join(payload["output_dir"], "contract.json"))
        end)
      end)
    end

    test "json runs emit stderr progress without corrupting stdout json" do
      FakePi.with_fake_pi("success", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-run-progress")

        System.put_env("THINKTANK_PROGRESS_HEARTBEAT_MS", "25")
        System.put_env("THINKTANK_TEST_PI_DELAY_MS", "150")

        on_exit(fn ->
          System.delete_env("THINKTANK_PROGRESS_HEARTBEAT_MS")
          System.delete_env("THINKTANK_TEST_PI_DELAY_MS")
        end)

        File.cd!(workspace, fn ->
          assert {:ok, command} =
                   CLI.parse_args([
                     "research",
                     "inspect this repo",
                     "--json",
                     "--no-synthesis",
                     "--agents",
                     "systems"
                   ])

          {stdout, stderr} =
            capture_stdout_and_stderr(fn ->
              assert CLI.execute({:ok, command}) == @exit_codes.success
            end)

          {:ok, payload} = Jason.decode(String.trim(stdout))
          progress_events = decode_jsonl!(stderr)

          assert payload["status"] == "complete"
          assert is_binary(payload["output_dir"])
          assert Enum.any?(progress_events, &(&1["phase"] == "initializing"))
          assert Enum.any?(progress_events, &(&1["phase"] == "running_agents"))
          assert Enum.any?(progress_events, &(&1["kind"] == "heartbeat"))
          assert Enum.all?(progress_events, &(&1["output_dir"] == payload["output_dir"]))
        end)
      end)
    end

    test "non-json run output includes the selected output directory" do
      FakePi.with_fake_pi("success", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-run-text")
        output_root = Path.join(workspace, "captured-run")

        File.cd!(workspace, fn ->
          assert {:ok, command} =
                   CLI.parse_args([
                     "research",
                     "inspect this repo",
                     "--no-synthesis",
                     "--agents",
                     "systems",
                     "--output",
                     output_root
                   ])

          output =
            capture_io(fn ->
              assert CLI.execute({:ok, command}) == @exit_codes.success
            end)

          assert output =~ "Output: #{Path.expand(output_root)}"
        end)
      end)
    end

    test "degraded run json exposes a typed top-level error" do
      FakePi.with_fake_pi("degraded", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-run-degraded")

        File.cd!(workspace, fn ->
          assert {:ok, command} =
                   CLI.parse_args([
                     "research",
                     "inspect this repo",
                     "--json",
                     "--no-synthesis",
                     "--agents",
                     "systems,dx"
                   ])

          {output, _stderr} =
            capture_stdout_and_stderr(fn ->
              assert CLI.execute({:ok, command}) == @exit_codes.generic_error
            end)

          {:ok, payload} = Jason.decode(String.trim(output))
          assert payload["status"] == "degraded"
          assert payload["error"]["code"] == "degraded_run"
        end)
      end)
    end

    test "partial run json preserves the stdout envelope and scratchpad artifacts" do
      FakePi.with_fake_pi("degraded", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-run-partial")

        File.cd!(workspace, fn ->
          assert {:ok, command} =
                   CLI.parse_args([
                     "research",
                     "inspect this repo",
                     "--json",
                     "--agents",
                     "systems"
                   ])

          {stdout, stderr} =
            capture_stdout_and_stderr(fn ->
              assert CLI.execute({:ok, command}) == @exit_codes.generic_error
            end)

          {:ok, payload} = Jason.decode(String.trim(stdout))
          progress_events = decode_jsonl!(stderr)

          assert payload["status"] == "partial"
          assert payload["error"]["code"] == "partial_run"
          assert Enum.any?(progress_events, &(&1["phase"] == "running_agents"))

          artifact_names = Enum.map(payload["artifacts"], & &1["name"])
          assert "run-scratchpad" in artifact_names
          assert Enum.any?(artifact_names, &String.starts_with?(&1, "agent-scratchpad-"))

          summary = File.read!(Path.join(payload["output_dir"], "summary.md"))
          assert summary =~ "Partial Result"
          assert summary =~ "Raw agent output"

          agent_scratchpad =
            payload["artifacts"]
            |> Enum.find(&String.starts_with?(&1["name"], "agent-scratchpad-"))
            |> then(& &1["file"])
            |> then(&Path.join(payload["output_dir"], &1))
            |> File.read!()

          assert agent_scratchpad =~ "attempt 1/1 started"
          assert agent_scratchpad =~ "agent finished successfully"
        end)
      end)
    end

    test "review eval json exposes typed errors and aggregate artifacts" do
      FakePi.with_fake_pi("fail", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-review-eval")
        Workspace.init_git_repo!(workspace)
        fixture_root = Workspace.unique_tmp_dir("thinktank-agent-review-fixtures")
        output_root = Path.join(Workspace.unique_tmp_dir("thinktank-agent-review-output"), "runs")

        contract = %{
          "bench_id" => "review/default",
          "workspace_root" => workspace,
          "input" => %{"input_text" => "Review the current change"},
          "artifact_dir" => Path.join(fixture_root, "source-run"),
          "adapter_context" => %{}
        }

        path = Path.join([fixture_root, "case", "contract.json"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Jason.encode!(contract))

        assert {:ok, command} =
                 CLI.parse_args([
                   "review",
                   "eval",
                   fixture_root,
                   "--json",
                   "--output",
                   output_root
                 ])

        output =
          capture_io(fn ->
            assert CLI.execute({:ok, command}) == @exit_codes.generic_error
          end)

        {:ok, payload} = Jason.decode(String.trim(output))

        assert Map.keys(payload) |> Enum.sort() == [
                 "artifacts",
                 "cases",
                 "error",
                 "output_dir",
                 "status",
                 "target"
               ]

        assert payload["status"] == "failed"
        assert payload["output_dir"] == Path.expand(output_root)

        assert [%{"file" => "case-001", "name" => "case-001", "type" => "directory"}] =
                 payload["artifacts"]

        assert payload["error"]["code"] == "review_eval_failed"
        assert hd(payload["cases"])["error"]["code"] == "no_successful_agents"
      end)
    end

    test "review eval text output includes the selected output directory" do
      FakePi.with_fake_pi("success", fn _env ->
        workspace = Workspace.unique_tmp_dir("thinktank-agent-review-eval-text")
        Workspace.init_git_repo!(workspace)
        fixture_root = Workspace.unique_tmp_dir("thinktank-agent-review-text-fixtures")

        output_root =
          Path.join(Workspace.unique_tmp_dir("thinktank-agent-review-text-output"), "runs")

        contract = %{
          "bench_id" => "review/default",
          "workspace_root" => workspace,
          "input" => %{"input_text" => "Review the current change"},
          "artifact_dir" => Path.join(fixture_root, "source-run"),
          "adapter_context" => %{}
        }

        path = Path.join([fixture_root, "case", "contract.json"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Jason.encode!(contract))

        assert {:ok, command} =
                 CLI.parse_args(["review", "eval", fixture_root, "--output", output_root])

        output =
          capture_io(fn ->
            assert CLI.execute({:ok, command}) == @exit_codes.success
          end)

        assert output =~ "Output: #{Path.expand(output_root)}"
      end)
    end
  end

  describe "error envelope" do
    test "structured JSON error on dry-run with invalid input" do
      command = %{
        action: :run,
        bench_id: "research/default",
        cwd: File.cwd!(),
        json: true,
        output: nil,
        dry_run: true,
        trust_repo_config: nil,
        input: %{input_text: 42, paths: [], agents: [], no_synthesis: false}
      }

      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:ok, command}) == @exit_codes.input_error
        end)

      {:ok, decoded} = Jason.decode(String.trim(stderr))
      assert is_map(decoded["error"])
      assert decoded["error"]["code"] == "missing_input_text"
      assert is_binary(decoded["error"]["message"])
      assert is_map(decoded["error"]["details"])
    end

    test "text error on dry-run with invalid input without --json" do
      command = %{
        action: :run,
        bench_id: "research/default",
        cwd: File.cwd!(),
        json: false,
        output: nil,
        dry_run: true,
        trust_repo_config: nil,
        input: %{input_text: 42, paths: [], agents: [], no_synthesis: false}
      }

      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:ok, command}) == @exit_codes.input_error
        end)

      assert stderr =~ "Error: input text is required"
    end
  end

  defp capture_stdout_and_stderr(fun) when is_function(fun, 0) do
    test_pid = self()

    stdout =
      capture_io(fn ->
        stderr =
          capture_io(:stderr, fn ->
            fun.()
          end)

        send(test_pid, {:captured_stderr, stderr})
      end)

    assert_received {:captured_stderr, stderr}
    {stdout, stderr}
  end

  defp decode_jsonl!(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, decoded} ->
          decoded

        {:error, error} ->
          flunk("expected JSON line, got error #{inspect(error)}\nraw:\n#{line}")
      end
    end)
  end
end
