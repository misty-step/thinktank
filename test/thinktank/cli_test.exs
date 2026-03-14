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

    test "returns error when no instruction provided" do
      assert {:error, "instruction argument required"} = CLI.parse_args([])
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
      assert opts.paths == ["./src"]
    end

    test "parses multiple --paths flags" do
      {:ok, opts} = CLI.parse_args(["test", "--paths", "./src", "--paths", "./lib"])
      assert opts.paths == ["./src", "./lib"]
    end

    test "parses --json flag" do
      {:ok, opts} = CLI.parse_args(["test", "--json"])
      assert opts.json == true
    end

    test "parses --output flag" do
      {:ok, opts} = CLI.parse_args(["test", "--output", "./results"])
      assert opts.output == "./results"
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
end
