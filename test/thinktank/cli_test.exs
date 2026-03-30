defmodule Thinktank.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Thinktank.CLI

  @exit_codes CLI.exit_codes()

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
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
    assert {:ok, %{action: :benches_validate}} = CLI.parse_args(["workflows", "validate"])

    assert {:ok, %{action: :benches_show, bench_id: "review/default"}} =
             CLI.parse_args(["workflows", "show", "review/default"])
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
               reader: fn :stdio, :all -> "  inspect this branch  \n" end
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

  test "benches show without --full keeps agent names only" do
    {:ok, command} = CLI.parse_args(["benches", "show", "research/default"])
    assert command.full == false

    output =
      capture_io(fn ->
        assert CLI.execute({:ok, command}) == 0
      end)

    assert {:ok, decoded} = Jason.decode(String.trim(output))
    assert decoded["agents"] == ["systems", "verification", "ml", "dx"]
  end
end
