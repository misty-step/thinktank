defmodule Thinktank.CLITest do
  use ExUnit.Case, async: true

  alias Thinktank.CLI

  describe "parse_args/1" do
    test "parses instruction as positional argument" do
      assert {:ok, %{instruction: "review this code"}} = CLI.parse_args(["review this code"])
    end

    test "joins multiple positional args into instruction" do
      assert {:ok, %{instruction: "review this code"}} =
               CLI.parse_args(["review", "this", "code"])
    end

    test "returns :needs_stdin when no instruction provided" do
      assert {:needs_stdin, _parsed} = CLI.parse_args([])
    end

    test "parses --help flag" do
      assert {:help, _} = CLI.parse_args(["--help"])
    end

    test "parses -h alias" do
      assert {:help, _} = CLI.parse_args(["-h"])
    end

    test "parses --version flag" do
      assert {:version, _} = CLI.parse_args(["--version"])
    end

    test "defaults to deep mode" do
      {:ok, opts} = CLI.parse_args(["test"])
      assert opts.mode == :deep
    end

    test "parses --quick flag" do
      {:ok, opts} = CLI.parse_args(["test", "--quick"])
      assert opts.mode == :quick
    end

    test "parses --paths flag" do
      {:ok, opts} = CLI.parse_args(["test", "--paths", "./src"])
      assert opts.paths == [Path.expand("./src")]
    end

    test "parses multiple --paths flags" do
      {:ok, opts} = CLI.parse_args(["test", "--paths", "./src", "--paths", "./lib"])
      assert opts.paths == [Path.expand("./src"), Path.expand("./lib")]
    end

    test "parses --json flag" do
      {:ok, opts} = CLI.parse_args(["test", "--json"])
      assert opts.json == true
    end

    test "parses --output flag and expands path" do
      {:ok, opts} = CLI.parse_args(["test", "--output", "./results"])
      assert opts.output == Path.expand("./results")
    end

    test "parses --models as comma-separated list" do
      {:ok, opts} = CLI.parse_args(["test", "--models", "claude-opus-4-6,gpt-5.4"])
      assert opts.models == ["claude-opus-4-6", "gpt-5.4"]
    end

    test "parses --roles as comma-separated list" do
      {:ok, opts} = CLI.parse_args(["test", "--roles", "security auditor, perf engineer"])
      assert opts.roles == ["security auditor", "perf engineer"]
    end

    test "parses --perspectives count" do
      {:ok, opts} = CLI.parse_args(["test", "--perspectives", "5"])
      assert opts.perspectives == 5
    end

    test "defaults perspectives to 4" do
      {:ok, opts} = CLI.parse_args(["test"])
      assert opts.perspectives == 4
    end

    test "parses --dry-run flag" do
      {:ok, opts} = CLI.parse_args(["test", "--dry-run"])
      assert opts.dry_run == true
    end

    test "parses --no-synthesis flag" do
      {:ok, opts} = CLI.parse_args(["test", "--no-synthesis"])
      assert opts.no_synthesis == true
    end

    test "returns error for unknown flags" do
      assert {:error, "unknown flag: --bogus"} = CLI.parse_args(["test", "--bogus"])
    end
  end

  describe "exit_codes/0" do
    test "defines all 11 exit codes" do
      codes = CLI.exit_codes()
      assert codes.success == 0
      assert codes.generic_error == 1
      assert codes.auth_error == 2
      assert codes.rate_limit == 3
      assert codes.invalid_request == 4
      assert codes.server_error == 5
      assert codes.network_error == 6
      assert codes.input_error == 7
      assert codes.content_filtered == 8
      assert codes.insufficient_credits == 9
      assert codes.cancelled == 10
    end
  end

  describe "agent_config_dir/0" do
    test "discovers agent_config in project root" do
      dir = CLI.agent_config_dir()
      assert dir != nil
      assert File.dir?(dir)
      assert String.ends_with?(dir, "agent_config")
    end

    test "respects THINKTANK_AGENT_CONFIG env override" do
      System.put_env("THINKTANK_AGENT_CONFIG", "/tmp/custom-config")
      assert CLI.agent_config_dir() == "/tmp/custom-config"
    after
      System.delete_env("THINKTANK_AGENT_CONFIG")
    end
  end

  describe "dry_run JSON output" do
    test "produces valid JSON envelope" do
      {:ok, opts} = CLI.parse_args(["test instruction", "--dry-run", "--json"])
      json = CLI.dry_run_output(opts)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["mode"] == "dry_run"
      assert decoded["instruction"] == "test instruction"
      assert is_list(decoded["paths"])
    end
  end
end
