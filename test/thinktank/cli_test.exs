defmodule Thinktank.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Thinktank.CLI

  describe "parse_args/1" do
    test "parses legacy positional prompt as research workflow" do
      assert {:ok, command} = CLI.parse_args(["compare approaches"])
      assert command.action == :run
      assert command.workflow_id == "research/default"
      assert command.input.input_text == "compare approaches"
    end

    test "parses explicit research subcommand" do
      assert {:ok, command} = CLI.parse_args(["research", "audit", "this", "--paths", "./lib"])
      assert command.workflow_id == "research/default"
      assert command.input.input_text == "audit this"
      assert command.input.paths == [Path.expand("./lib")]
    end

    test "parses run subcommand with workflow id and input flag" do
      assert {:ok, command} =
               CLI.parse_args([
                 "run",
                 "research/default",
                 "--input",
                 "tradeoffs",
                 "--models",
                 "openai/gpt-5.4,anthropic/claude-sonnet-4.6"
               ])

      assert command.workflow_id == "research/default"
      assert command.input.input_text == "tradeoffs"

      assert command.input.models == [
               "openai/gpt-5.4",
               "anthropic/claude-sonnet-4.6"
             ]
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

      assert command.workflow_id == "review/cerberus"
      assert command.input.base == "origin/main"
      assert command.input.head == "HEAD"
      assert command.input.repo == "misty-step/thinktank"
      assert command.input.pr == 42
    end

    test "rejects quick mode for review workflows" do
      assert {:error, "thinktank review is agentic-only; remove --quick"} =
               CLI.parse_args(["review", "--quick"])

      assert {:error, "review/cerberus is agentic-only; remove --quick"} =
               CLI.parse_args(["run", "review/cerberus", "--quick"])
    end

    test "requires --repo when --pr is provided for review workflows" do
      assert {:error, "review/cerberus requires --repo when --pr is provided"} =
               CLI.parse_args(["review", "--pr", "42"])

      assert {:error, "review/cerberus requires --repo when --pr is provided"} =
               CLI.parse_args(["run", "review/cerberus", "--pr", "42", "--input", "review"])
    end

    test "parses workflow management commands" do
      assert {:ok, %{action: :workflows_list}} = CLI.parse_args(["workflows", "list"])
      assert {:ok, %{action: :workflows_validate}} = CLI.parse_args(["workflows", "validate"])

      assert {:ok, %{action: :workflows_show, workflow_id: "review/cerberus"}} =
               CLI.parse_args(["workflows", "show", "review/cerberus"])
    end

    test "returns :needs_stdin when no input is provided" do
      assert {:needs_stdin, %{workflow_id: "research/default"}} = CLI.parse_args([])
      assert {:needs_stdin, %{workflow_id: "research/default"}} = CLI.parse_args(["research"])

      assert {:needs_stdin, %{workflow_id: "research/default"}} =
               CLI.parse_args(["run", "research/default"])
    end

    test "parses quick and deep executor flags" do
      assert {:ok, %{mode: :quick}} = CLI.parse_args(["research", "test", "--quick"])
      assert {:ok, %{mode: :deep}} = CLI.parse_args(["review", "--deep"])
    end

    test "defaults tier to standard and parses other tiers" do
      assert {:ok, %{input: %{tier: :standard}}} = CLI.parse_args(["research", "test"])

      assert {:ok, %{input: %{tier: :cheap}}} =
               CLI.parse_args(["research", "test", "--tier", "cheap"])

      assert {:ok, %{input: %{tier: :premium}}} =
               CLI.parse_args(["research", "test", "--tier", "premium"])
    end

    test "returns errors for invalid tier and unknown flags" do
      assert {:error, "invalid tier: bogus" <> _} =
               CLI.parse_args(["research", "test", "--tier", "bogus"])

      assert {:error, "unknown flag: --bogus"} = CLI.parse_args(["research", "test", "--bogus"])
    end

    test "parses dry run and output flags" do
      assert {:ok, command} =
               CLI.parse_args(["research", "test", "--dry-run", "--output", "./tmp"])

      assert command.dry_run == true
      assert command.output == Path.expand("./tmp")
    end

    test "parses trust_repo_config flag" do
      assert {:ok, command} =
               CLI.parse_args(["research", "test", "--trust-repo-config"])

      assert command.trust_repo_config == true
    end
  end

  describe "dry_run_output/2" do
    test "renders workflow-oriented JSON" do
      {:ok, command} =
        CLI.parse_args(["research", "test prompt", "--dry-run", "--json", "--paths", "./lib"])

      {:ok, resolved} =
        Thinktank.Engine.resolve(command.workflow_id, command.input,
          cwd: command.cwd,
          trust_repo_config: command.trust_repo_config
        )

      decoded = CLI.dry_run_output(command, resolved) |> Jason.decode!()

      assert decoded["action"] == "run"
      assert decoded["workflow"] == "research/default"
      assert decoded["input"]["input_text"] == "test prompt"
      assert decoded["input"]["paths"] == [Path.expand("./lib")]
    end
  end

  describe "execute/1" do
    test "prints usage text for help" do
      output =
        capture_io(fn ->
          assert CLI.execute({:help, %{}}) == 0
        end)

      assert output =~ "thinktank"
      assert output =~ "workflows"
    end

    test "prints version for version requests" do
      output =
        capture_io(fn ->
          assert CLI.execute({:version, %{}}) == 0
        end)

      assert output =~ "thinktank "
    end

    test "prints errors to stderr" do
      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:error, "bad input"}) == 7
        end)

      assert stderr =~ "Error: bad input"
    end

    test "dry run prints JSON contract" do
      {:ok, command} = CLI.parse_args(["research", "test", "--dry-run"])

      output =
        capture_io(fn ->
          assert CLI.execute({:ok, command}) == 0
        end)

      assert {:ok, decoded} = Jason.decode(String.trim(output))
      assert decoded["workflow"] == "research/default"
      assert decoded["input"]["input_text"] == "test"
    end

    test "dry run validates workflow resolution" do
      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute(
                   {:ok,
                    %{
                      action: :run,
                      workflow_id: "unknown/workflow",
                      mode: nil,
                      json: false,
                      output: nil,
                      dry_run: true,
                      trust_repo_config: false,
                      cwd: File.cwd!(),
                      tier: :standard,
                      input: %{input_text: "test"}
                    }}
                 ) == 7
        end)

      assert stderr =~ "unknown workflow"
    end

    test "workflow commands execute against the built-in config" do
      list_output =
        capture_io(fn ->
          assert CLI.execute(
                   {:ok,
                    %{
                      action: :workflows_list,
                      cwd: File.cwd!(),
                      json: false,
                      trust_repo_config: false
                    }}
                 ) ==
                   0
        end)

      assert list_output =~ "review/cerberus"

      show_output =
        capture_io(fn ->
          assert CLI.execute(
                   {:ok,
                    %{
                      action: :workflows_show,
                      workflow_id: "review/cerberus",
                      cwd: File.cwd!(),
                      json: false,
                      trust_repo_config: false
                    }}
                 ) == 0
        end)

      assert show_output =~ "\"execution_mode\": \"deep\""

      validate_output =
        capture_io(fn ->
          assert CLI.execute(
                   {:ok,
                    %{
                      action: :workflows_validate,
                      cwd: File.cwd!(),
                      json: false,
                      trust_repo_config: false
                    }}
                 ) ==
                   0
        end)

      assert validate_output =~ "Validated"
    end
  end

  describe "usage_text/0" do
    test "documents workflow-oriented commands and flags" do
      text = CLI.usage_text()
      assert text =~ "thinktank run <workflow>"
      assert text =~ "thinktank research"
      assert text =~ "thinktank review"
      assert text =~ "thinktank workflows list|show|validate"
      assert text =~ "--input"
      assert text =~ "--paths"
      assert text =~ "--base"
      assert text =~ "--repo"
    end
  end

  describe "agent_config_dir/0" do
    test "returns env var path when THINKTANK_AGENT_CONFIG is set" do
      System.put_env("THINKTANK_AGENT_CONFIG", "/custom/config")
      assert CLI.agent_config_dir() == "/custom/config"
    after
      System.delete_env("THINKTANK_AGENT_CONFIG")
    end

    test "returns CWD/agent_config only when explicitly trusted" do
      System.delete_env("THINKTANK_AGENT_CONFIG")
      System.put_env("THINKTANK_TRUST_REPO_AGENT_CONFIG", "1")
      assert CLI.agent_config_dir() == Path.join(File.cwd!(), "agent_config")
    after
      System.delete_env("THINKTANK_TRUST_REPO_AGENT_CONFIG")
    end

    test "returns nil when repo agent_config is not explicitly trusted" do
      System.delete_env("THINKTANK_AGENT_CONFIG")
      System.delete_env("THINKTANK_TRUST_REPO_AGENT_CONFIG")
      assert CLI.agent_config_dir() == nil
    end

    test "returns nil when no env var and no agent_config dir exists" do
      System.delete_env("THINKTANK_AGENT_CONFIG")
      System.delete_env("THINKTANK_TRUST_REPO_AGENT_CONFIG")
      tmp = System.tmp_dir!()
      cwd = File.cwd!()
      File.cd!(tmp)
      result = CLI.agent_config_dir()
      File.cd!(cwd)
      assert result == nil
    end
  end
end
