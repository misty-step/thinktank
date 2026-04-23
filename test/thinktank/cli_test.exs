defmodule Thinktank.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Thinktank.{BenchSpec, CLI, Config, RunContract, RunStore}

  @exit_codes CLI.exit_codes()

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp in_tmp_repo_config(yaml, fun) do
    tmp = unique_tmp_dir("thinktank-cli")
    config_path = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(config_path))
    File.write!(config_path, yaml)
    File.cd!(tmp, fun)
  end

  test "parses legacy positional prompt as research bench" do
    assert {:ok, command} = CLI.parse_args(["compare approaches"])
    assert command.action == :run
    assert command.bench_id == "research/default"
    assert command.input.input_text == "compare approaches"
  end

  test "parses explicit research subcommand with paths and agents" do
    assert {:ok, command} =
             CLI.parse_args([
               "research",
               "audit",
               "this",
               "--paths",
               "./lib",
               "--paths",
               "./test",
               "--agents",
               "systems,dx"
             ])

    assert command.bench_id == "research/default"
    assert command.input.input_text == "audit this"
    assert command.input.paths == [Path.expand("./lib"), Path.expand("./test")]
    assert command.input.agents == ["systems", "dx"]
  end

  test "parses review subcommand flags" do
    assert {:ok, command} =
             CLI.parse_args([
               "review",
               "--base",
               "origin/main",
               "--head",
               "HEAD",
               "--repo",
               "misty-step/thinktank",
               "--pr",
               "42"
             ])

    assert command.bench_id == "review/default"
    assert command.input.base == "origin/main"
    assert command.input.head == "HEAD"
    assert command.input.repo == "misty-step/thinktank"
    assert command.input.pr == 42
  end

  test "parses review eval command" do
    assert {:ok, command} =
             CLI.parse_args([
               "review",
               "eval",
               "./tmp/review-run",
               "--bench",
               "review/default",
               "--json"
             ])

    assert command.action == :review_eval
    assert command.target == Path.expand("./tmp/review-run")
    assert command.bench_id == "review/default"
    assert command.json == true
  end

  test "requires --repo when --pr is provided for review" do
    assert {:error, "review/default requires --repo when --pr is provided"} =
             CLI.parse_args(["review", "--pr", "42"])
  end

  test "custom review benches inherit review flag parsing from bench kind" do
    in_tmp_repo_config(
      """
      benches:
        demo/review:
          kind: review
          description: Demo review bench
          agents:
            - trace
          default_task: Review the change
      """,
      fn ->
        assert {:ok, command} =
                 CLI.parse_args([
                   "run",
                   "demo/review",
                   "--trust-repo-config",
                   "--base",
                   "origin/master",
                   "--head",
                   "HEAD",
                   "--repo",
                   "misty-step/thinktank",
                   "--pr",
                   "42"
                 ])

        assert command.bench_id == "demo/review"
        assert command.input.input_text == "Review the change"
        assert command.input.base == "origin/master"
        assert command.input.head == "HEAD"
        assert command.input.repo == "misty-step/thinktank"
        assert command.input.pr == 42
      end
    )
  end

  test "custom benches with a default task do not require stdin" do
    in_tmp_repo_config(
      """
      benches:
        demo/custom:
          description: Demo bench
          agents:
            - trace
          default_task: Investigate the workspace
      """,
      fn ->
        assert {:ok, command} =
                 CLI.parse_args(["run", "demo/custom", "--trust-repo-config"])

        assert command.bench_id == "demo/custom"
        assert command.input.input_text == "Investigate the workspace"
      end
    )
  end

  test "research bench can use a configured default task without stdin" do
    in_tmp_repo_config(
      """
      benches:
        research/default:
          kind: research
          description: Custom research bench
          agents:
            - systems
          default_task: Investigate the workspace
      """,
      fn ->
        assert {:ok, command} =
                 CLI.parse_args(["research", "--trust-repo-config"])

        assert command.bench_id == "research/default"
        assert command.input.input_text == "Investigate the workspace"
      end
    )
  end

  test "custom review benches require --repo when --pr is provided" do
    in_tmp_repo_config(
      """
      benches:
        demo/review:
          kind: review
          description: Demo review bench
          agents:
            - trace
          default_task: Review the change
      """,
      fn ->
        assert {:error, "demo/review requires --repo when --pr is provided"} =
                 CLI.parse_args([
                   "run",
                   "demo/review",
                   "--trust-repo-config",
                   "--pr",
                   "42"
                 ])
      end
    )
  end

  test "parses bench management commands and legacy workflows alias" do
    assert {:ok, %{action: :benches_list}} = CLI.parse_args(["benches", "list"])

    assert {:ok, %{action: :benches_validate, json: true}} =
             CLI.parse_args(["workflows", "validate", "--json"])

    assert {:ok, %{action: :benches_show, bench_id: "review/default"}} =
             CLI.parse_args(["workflows", "show", "review/default"])
  end

  test "parses run inspection commands" do
    assert {:ok, %{action: :runs_list, json: true}} = CLI.parse_args(["runs", "list", "--json"])

    assert {:ok, %{action: :runs_show, target: "abc123"}} =
             CLI.parse_args(["runs", "show", "abc123"])

    assert {:ok, %{action: :runs_wait, target: "./tmp/run", timeout_ms: 250}} =
             CLI.parse_args(["runs", "wait", "./tmp/run", "--timeout-ms", "250"])

    assert {:error, "--timeout-ms must be a non-negative integer"} =
             CLI.parse_args(["runs", "wait", "./tmp/run", "--timeout-ms", "-1"])
  end

  test "benches validate prints JSON when --json is requested" do
    {:ok, config} = Config.load()
    expected_count = length(Config.list_benches(config))

    {:ok, command} = CLI.parse_args(["benches", "validate", "--json"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.success
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded == %{"status" => "ok", "bench_count" => expected_count}
  end

  test "benches validate prints a human summary unless --json is requested" do
    {:ok, config} = Config.load()
    expected_count = length(Config.list_benches(config))

    {:ok, command} = CLI.parse_args(["benches", "validate"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.success
      end)

    assert output == "Validated #{expected_count} benches\n"
  end

  test "workflows validate prints the same JSON contract while the alias exists" do
    {:ok, config} = Config.load()
    expected_count = length(Config.list_benches(config))

    {:ok, command} = CLI.parse_args(["workflows", "validate", "--json"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.success
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded == %{"status" => "ok", "bench_count" => expected_count}
  end

  test "benches validate emits structured JSON errors for invalid trusted repo config" do
    in_tmp_repo_config("[]\n", fn ->
      assert {:ok, command} =
               CLI.parse_args(["benches", "validate", "--trust-repo-config", "--json"])

      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:ok, command}) == @exit_codes.input_error
        end)

      assert {:ok, decoded} = Jason.decode(String.trim(stderr))
      assert decoded["error"]["code"] == "run_error"
      assert decoded["error"]["message"] =~ "must contain a YAML mapping"
      assert decoded["error"]["details"] == %{}
      assert decoded["output_dir"] == nil
    end)
  end

  test "benches validate emits text errors without --json" do
    in_tmp_repo_config("[]\n", fn ->
      assert {:ok, command} = CLI.parse_args(["benches", "validate", "--trust-repo-config"])

      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:ok, command}) == @exit_codes.input_error
        end)

      assert stderr =~ "Error: config file"
      assert stderr =~ "must contain a YAML mapping"
    end)
  end

  test "returns :needs_stdin when no research input is provided" do
    assert {:needs_stdin, %{bench_id: "research/default"}} = CLI.parse_args([])
    assert {:needs_stdin, %{bench_id: "research/default"}} = CLI.parse_args(["research"])

    assert {:needs_stdin, %{bench_id: "research/default"}} =
             CLI.parse_args(["run", "research/default"])
  end

  test "uses --input when no positional prompt is provided" do
    assert {:ok, command} = CLI.parse_args(["--input", "inspect this branch"])
    assert command.bench_id == "research/default"
    assert command.input.input_text == "inspect this branch"
  end

  test "rejects malformed reserved subcommands" do
    assert {:error, "run requires a bench id"} = CLI.parse_args(["run"])

    assert {:error, "benches expects list, show <bench>, or validate"} =
             CLI.parse_args(["benches", "show", "research/default", "extra"])

    assert {:error, "runs expects list, show <path-or-id>, or wait <path-or-id>"} =
             CLI.parse_args(["runs", "show"])
  end

  test "read_stdin fails fast when stdin is interactive" do
    command = %{bench_id: "research/default", input: %{input_text: nil}}

    assert {:error, "input text is required"} =
             CLI.read_stdin(command,
               stdin_piped?: false,
               reader: fn _, _ -> flunk("stdin reader should not run without piped input") end
             )
  end

  test "read_stdin trims piped input" do
    command = %{bench_id: "research/default", input: %{input_text: nil}}

    assert {:ok, updated} =
             CLI.read_stdin(command,
               stdin_piped?: true,
               reader: fn :stdio, :eof -> "  inspect this branch  \n" end
             )

    assert updated.input.input_text == "inspect this branch"
  end

  test "dry run prints bench-oriented JSON contract" do
    {:ok, command} =
      CLI.parse_args(["research", "test prompt", "--dry-run", "--json", "--paths", "./lib"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded["bench"] == "research/default"
    assert decoded["input"]["input_text"] == "test prompt"
  end

  test "dry run prints a human summary unless --json is requested" do
    {:ok, command} = CLI.parse_args(["research", "test prompt", "--dry-run"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert output =~ "Bench: research/default"
    assert output =~ "Description:"
    assert output =~ "Input: test prompt"
  end

  test "dry run JSON includes planner metadata for review benches" do
    {:ok, command} = CLI.parse_args(["review", "--dry-run", "--json"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded["bench"] == "review/default"
    assert decoded["planner"] == "marshal"
  end

  test "uses env trust for repo config when the flag is omitted" do
    in_tmp_repo_config(
      """
      benches:
        demo/custom:
          description: Demo custom bench
          agents:
            - trace
          default_task: Investigate the workspace
      """,
      fn ->
        System.put_env("THINKTANK_TRUST_REPO_CONFIG", "1")
        on_exit(fn -> System.delete_env("THINKTANK_TRUST_REPO_CONFIG") end)

        assert {:ok, command} = CLI.parse_args(["run", "demo/custom", "--dry-run", "--json"])

        output =
          capture_io(fn ->
            assert CLI.execute({:ok, command}) == 0
          end)

        assert {:ok, decoded} = Jason.decode(String.trim(output))
        assert decoded["bench"] == "demo/custom"
      end
    )
  end

  test "execute uses the config snapshot resolved during parse" do
    for {args, initial_yaml, overwrite_yaml, expected_bench, expected_description} <- [
          {["run", "demo/review", "--trust-repo-config", "--dry-run", "--json"],
           """
           benches:
             demo/review:
               kind: review
               description: First config snapshot
               agents:
                 - trace
               default_task: Review the current change and report only real issues with evidence.
           """,
           """
           benches:
             demo/review:
               kind: review
               description: Second config snapshot
               agents:
                 - ghost
               default_task: Broken config
           """, "demo/review", "First config snapshot"},
          {["research", "inspect this", "--trust-repo-config", "--dry-run", "--json"],
           """
           benches:
             research/default:
               kind: research
               description: First research snapshot
               agents:
                 - systems
           """,
           """
           benches:
             research/default:
               kind: research
               description: Second research snapshot
               agents:
                 - ghost
           """, "research/default", "First research snapshot"}
        ] do
      in_tmp_repo_config(initial_yaml, fn ->
        config_path = Path.join([File.cwd!(), ".thinktank", "config.yml"])

        assert {:ok, command} = CLI.parse_args(args)

        File.write!(config_path, overwrite_yaml)

        output =
          capture_io(fn ->
            assert CLI.execute({:ok, command}) == 0
          end)

        assert {:ok, decoded} = Jason.decode(String.trim(output))
        assert decoded["bench"] == expected_bench
        assert decoded["description"] == expected_description
      end)
    end
  end

  test "prints usage text for help" do
    output =
      capture_io(fn ->
        assert CLI.execute({:help, %{}}) == 0
      end)

    assert output =~ "thinktank benches"
    assert output =~ "thinktank review"
    assert output =~ "thinktank runs"
    assert output =~ "Task text can come from --input, positional text, or piped stdin."
  end

  test "runs list --json emits discovered runs with typed state" do
    output_dir = init_run_fixture("thinktank-cli-runs-list", "review/default", "degraded")
    run_id = Path.basename(output_dir)

    {:ok, command} = CLI.parse_args(["runs", "list", "--json"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.success
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert is_list(decoded["runs"])

    run = Enum.find(decoded["runs"], &(&1["id"] == run_id))
    assert run["bench"] == "review/default"
    assert run["status"] == "degraded"
    assert run["output_dir"] == output_dir
  end

  test "runs list returns an input error for invalid internal limit" do
    command = %{action: :runs_list, cwd: File.cwd!(), json: false, limit: -1}

    stderr =
      capture_io(:stderr, fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.input_error
      end)

    assert stderr =~ "Error: run list limit must be a non-negative integer"
  end

  test "runs show prints terminal status without treating failed runs as CLI errors" do
    output_dir = init_run_fixture("thinktank-cli-runs-show", "research/default", "failed")

    {:ok, command} = CLI.parse_args(["runs", "show", output_dir])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.success
      end)

    assert output =~ "Status: failed"
    assert output =~ "Output: #{output_dir}"
  end

  test "runs show --json emits the run envelope" do
    output_dir = init_run_fixture("thinktank-cli-runs-show-json", "research/default", "failed")

    {:ok, command} = CLI.parse_args(["runs", "show", output_dir, "--json"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.success
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded["run"]["status"] == "failed"
    assert decoded["run"]["output_dir"] == output_dir
  end

  test "runs show returns an input error for an existing non-run file target" do
    path = Path.join(unique_tmp_dir("thinktank-cli-runs-show-invalid-file"), "notes.txt")
    File.write!(path, "not a run")

    {:ok, command} = CLI.parse_args(["runs", "show", path])

    stderr =
      capture_io(:stderr, fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.input_error
      end)

    assert stderr =~ "Error: not a ThinkTank run directory: #{path}"
  end

  test "runs show returns a generic error for malformed run artifacts" do
    output_dir =
      init_run_fixture("thinktank-cli-runs-show-invalid-artifact", "research/default", "complete")

    manifest_path = Path.join(output_dir, "manifest.json")

    manifest_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.put("status", "mystery")
    |> then(&File.write!(manifest_path, Jason.encode!(&1, pretty: true)))

    {:ok, command} = CLI.parse_args(["runs", "show", output_dir])

    stderr =
      capture_io(:stderr, fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.generic_error
      end)

    assert stderr =~ "Error: unknown run status: \"mystery\""
  end

  test "runs wait exits non-zero when the final run status is not complete" do
    output_dir = init_run_fixture("thinktank-cli-runs-wait", "research/default", "partial")

    {:ok, command} = CLI.parse_args(["runs", "wait", output_dir])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.generic_error
      end)

    assert output =~ "Status: partial"
  end

  test "runs wait --json preserves the run envelope on non-complete terminal state" do
    output_dir = init_run_fixture("thinktank-cli-runs-wait-json", "research/default", "partial")

    {:ok, command} = CLI.parse_args(["runs", "wait", output_dir, "--json"])

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.generic_error
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded["run"]["status"] == "partial"
    assert decoded["run"]["output_dir"] == output_dir
  end

  test "runs wait returns an input error for an existing non-run file target" do
    path = Path.join(unique_tmp_dir("thinktank-cli-runs-wait-invalid-file"), "notes.txt")
    File.write!(path, "not a run")

    {:ok, command} = CLI.parse_args(["runs", "wait", path])

    stderr =
      capture_io(:stderr, fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.input_error
      end)

    assert stderr =~ "Error: not a ThinkTank run directory: #{path}"
  end

  test "runs wait supports bounded polling with --timeout-ms" do
    output_dir = Path.join(unique_tmp_dir("thinktank-cli-runs-wait-timeout"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{"input_text" => "inspect this"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}
    RunStore.init_run(output_dir, contract, bench)

    {:ok, command} = CLI.parse_args(["runs", "wait", output_dir, "--timeout-ms", "0"])

    stderr =
      capture_io(:stderr, fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.generic_error
      end)

    assert stderr =~ "Error: timed out waiting for run to finish: #{output_dir}"
  end

  test "runs wait --json includes output_dir in timeout errors" do
    output_dir = Path.join(unique_tmp_dir("thinktank-cli-runs-wait-timeout-json"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{"input_text" => "inspect this"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}
    RunStore.init_run(output_dir, contract, bench)

    {:ok, command} = CLI.parse_args(["runs", "wait", output_dir, "--timeout-ms", "0", "--json"])

    stderr =
      capture_io(:stderr, fn ->
        assert CLI.execute({:ok, command}) == @exit_codes.generic_error
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(stderr))
    assert decoded["output_dir"] == output_dir
    assert decoded["error"]["code"] == "run_wait_timeout"
  end

  test "renders a cost line in the human-readable run payload" do
    output =
      CLI.render_run_payload(%{
        bench: "research/default",
        status: "complete",
        output_dir: "/tmp/thinktank-run",
        agents: [%{"name" => "systems", "metadata" => %{"status" => "ok"}}],
        artifacts: [%{"name" => "summary", "file" => "summary.md"}],
        usd_cost_total: 0.0006625,
        pricing_gaps: []
      })

    assert output =~ "Cost: $0.000663"
  end

  test "renders pricing gaps in the human-readable run payload" do
    output =
      CLI.render_run_payload(%{
        bench: "research/default",
        status: "partial",
        output_dir: "/tmp/thinktank-run",
        agents: [],
        artifacts: [],
        usd_cost_total: nil,
        pricing_gaps: ["unknown/model"]
      })

    assert output =~ "Cost: unavailable (pricing gap: unknown/model)"
  end

  test "benches list --json emits a JSON array with id, description, kind, agent_count" do
    {:ok, command} = CLI.parse_args(["benches", "list", "--json"])
    assert command.action == :benches_list
    assert command.json == true

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert is_list(decoded)
    assert length(decoded) >= 2

    Enum.each(decoded, fn entry ->
      assert is_binary(entry["id"])
      assert is_binary(entry["description"])
      assert is_binary(entry["kind"])
      assert is_integer(entry["agent_count"])
    end)

    research = Enum.find(decoded, &(&1["id"] == "research/default"))
    assert research["kind"] == "research"
    assert research["agent_count"] == 4
  end

  defp init_run_fixture(prefix, bench_id, status) do
    output_dir = Path.join(unique_tmp_dir(prefix), "run")

    contract = %RunContract{
      bench_id: bench_id,
      workspace_root: File.cwd!(),
      input: %{"input_text" => "inspect this"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: bench_id, description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)
    RunStore.complete_run(output_dir, status)
    output_dir
  end

  test "benches list without --json emits tab-separated text" do
    {:ok, command} = CLI.parse_args(["benches", "list"])
    assert command.json == false

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert output =~ "research/default\t"
    assert output =~ "review/default\t"
  end

  test "benches show --full --json resolves agent names to full specs" do
    {:ok, command} =
      CLI.parse_args(["benches", "show", "review/default", "--full", "--json"])

    assert command.action == :benches_show
    assert command.json == true
    assert command.full == true

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert is_list(decoded["agents"])
    assert is_boolean(decoded["structured_findings"])

    assert [_ | _] = decoded["agents"]

    Enum.each(decoded["agents"], fn agent ->
      assert is_binary(agent["name"])
      assert is_binary(agent["model"])
      assert String.trim(agent["model"]) != ""
      assert is_binary(agent["system_prompt"])
      assert is_binary(agent["thinking_level"])
      assert is_integer(agent["timeout_ms"])
      assert is_nil(agent["tools"]) or is_list(agent["tools"])
    end)
  end

  test "benches show --json preserves the machine-readable payload without --full" do
    {:ok, command} = CLI.parse_args(["benches", "show", "research/default", "--json"])
    assert command.action == :benches_show
    assert command.json == true
    assert command.full == false

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded["id"] == "research/default"
    assert decoded["kind"] == "research"
    assert decoded["structured_findings"] == true
    assert decoded["agents"] == ["systems", "verification", "ml", "dx"]
    assert decoded["planner"] == nil
    assert decoded["synthesizer"] == "research-synth"
  end

  test "benches show without --full emits human-readable text" do
    {:ok, command} = CLI.parse_args(["benches", "show", "research/default"])
    assert command.full == false

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert output =~ "Bench: research/default"
    assert output =~ "Description:"
    assert output =~ "Kind: research"
    assert output =~ "Structured Findings: true"
    assert output =~ "Agents:"
    assert output =~ "- systems"
    assert output =~ "- verification"
    assert output =~ "- ml"
    assert output =~ "- dx"
    assert {:error, _} = Jason.decode(String.trim(output))
  end

  test "benches show --full emits human-readable agent details without --json" do
    {:ok, command} = CLI.parse_args(["benches", "show", "review/default", "--full"])
    assert command.full == true
    assert command.json == false

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert output =~ "Bench: review/default"
    assert output =~ "Kind: review"
    assert output =~ "Agents:"
    assert output =~ "trace"
    assert output =~ "model="
    assert output =~ "thinking_level="
    assert output =~ "timeout_ms="
    assert output =~ "system_prompt:"
    assert output =~ ~r/system_prompt:\n\s{6}\S/
    assert {:error, _} = Jason.decode(String.trim(output))
  end
end
