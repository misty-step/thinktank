defmodule Thinktank.OutputTest do
  use ExUnit.Case, async: true

  alias Thinktank.{Output, Perspective}

  @moduletag :tmp_dir

  # Build Perspective structs from role names for test convenience.
  # Uses "test-model" and a generic system prompt.
  defp perspectives(roles) when is_list(roles) do
    Enum.with_index(roles, fn role, i ->
      %Perspective{
        role: role,
        model: "test-model-#{rem(i, 2)}",
        system_prompt: "You are a #{role}.",
        priority: i + 1
      }
    end)
  end

  defp usage(prompt \\ 10, completion \\ 20, cost \\ 0.001) do
    %{
      prompt_tokens: prompt,
      completion_tokens: completion,
      total_tokens: prompt + completion,
      cost: cost
    }
  end

  describe "init_run/3" do
    test "creates output dir and manifest with full perspective config", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run1")
      persp = perspectives(["security-analyst", "performance-engineer", "architect"])

      assert :ok = Output.init_run(output_dir, persp, nil)
      assert File.dir?(output_dir)

      manifest = read_manifest(output_dir)
      assert manifest["status"] == "running"
      assert length(manifest["perspectives"]) == 3

      for p <- manifest["perspectives"] do
        assert p["status"] == "pending"
        assert is_nil(p["file"])
        assert is_binary(p["model"])
        assert is_binary(p["system_prompt"])
        assert is_integer(p["priority"])
      end
    end

    test "manifest records model and system_prompt per perspective", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run1b")

      persp = [
        %Perspective{
          role: "auditor",
          model: "anthropic/claude-sonnet-4.6",
          system_prompt: "You are a security auditor.",
          priority: 1
        },
        %Perspective{
          role: "architect",
          model: "openai/gpt-5.4",
          system_prompt: "You are a software architect.",
          priority: 2
        }
      ]

      Output.init_run(output_dir, persp, nil)
      manifest = read_manifest(output_dir)

      auditor = Enum.find(manifest["perspectives"], &(&1["role"] == "auditor"))
      assert auditor["model"] == "anthropic/claude-sonnet-4.6"
      assert auditor["system_prompt"] == "You are a security auditor."
      assert auditor["priority"] == 1

      architect = Enum.find(manifest["perspectives"], &(&1["role"] == "architect"))
      assert architect["model"] == "openai/gpt-5.4"
      assert architect["system_prompt"] == "You are a software architect."
      assert architect["priority"] == 2
    end

    test "manifest contains run metadata", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run2")
      assert :ok = Output.init_run(output_dir, perspectives(["analyst"]), nil)

      manifest = read_manifest(output_dir)
      assert is_binary(manifest["started_at"])
      assert manifest["version"] == Thinktank.MixProject.project()[:version]
    end

    test "manifest stores router_usage when provided", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run_ru")
      router_usage = usage(50, 100, 0.005)

      Output.init_run(output_dir, perspectives(["a"]), router_usage)
      manifest = read_manifest(output_dir)

      assert manifest["router_usage"]["prompt_tokens"] == 50
      assert manifest["router_usage"]["completion_tokens"] == 100
      assert manifest["router_usage"]["total_tokens"] == 150
      assert manifest["router_usage"]["cost"] == 0.005
    end

    test "manifest stores null router_usage when nil", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run_ru_nil")

      Output.init_run(output_dir, perspectives(["a"]), nil)
      manifest = read_manifest(output_dir)

      assert is_nil(manifest["router_usage"])
    end
  end

  describe "write_perspective/4" do
    test "writes perspective file and updates manifest", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "wp1")
      Output.init_run(output_dir, perspectives(["security-analyst", "architect"]), nil)

      content = "## Security Analysis\n\nNo critical vulnerabilities found."
      assert :ok = Output.write_perspective(output_dir, "security-analyst", content, usage())

      # File written (priority-prefixed)
      path = Path.join(output_dir, "1-security-analyst.md")
      assert File.read!(path) == content

      # Manifest updated — model preserved
      manifest = read_manifest(output_dir)
      sa = Enum.find(manifest["perspectives"], &(&1["role"] == "security-analyst"))
      assert sa["status"] == "complete"
      assert sa["file"] == "1-security-analyst.md"
      assert is_binary(sa["completed_at"])
      assert is_binary(sa["model"])

      # Other perspective still pending
      arch = Enum.find(manifest["perspectives"], &(&1["role"] == "architect"))
      assert arch["status"] == "pending"
    end

    test "handles multiple completions incrementally", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "wp2")
      Output.init_run(output_dir, perspectives(["a", "b", "c"]), nil)

      Output.write_perspective(output_dir, "a", "content a", usage())
      manifest = read_manifest(output_dir)
      assert manifest["perspectives_completed"] == 1

      Output.write_perspective(output_dir, "b", "content b", usage())
      manifest = read_manifest(output_dir)
      assert manifest["perspectives_completed"] == 2
    end

    test "manifest includes usage per perspective", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "wp_usage")
      Output.init_run(output_dir, perspectives(["a", "b"]), nil)

      Output.write_perspective(output_dir, "a", "content a", usage(100, 200, 0.01))
      Output.write_perspective(output_dir, "b", "content b", usage(50, 80, 0.005))

      manifest = read_manifest(output_dir)

      a = Enum.find(manifest["perspectives"], &(&1["role"] == "a"))
      assert a["usage"]["prompt_tokens"] == 100
      assert a["usage"]["completion_tokens"] == 200
      assert a["usage"]["total_tokens"] == 300
      assert a["usage"]["cost"] == 0.01

      b = Enum.find(manifest["perspectives"], &(&1["role"] == "b"))
      assert b["usage"]["prompt_tokens"] == 50
      assert b["usage"]["completion_tokens"] == 80
      assert b["usage"]["total_tokens"] == 130
      assert b["usage"]["cost"] == 0.005
    end

    test "nil usage stored as null in manifest", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "wp_nil_usage")
      Output.init_run(output_dir, perspectives(["deep-agent"]), nil)

      Output.write_perspective(output_dir, "deep-agent", "deep content", nil)

      manifest = read_manifest(output_dir)
      p = Enum.find(manifest["perspectives"], &(&1["role"] == "deep-agent"))
      assert p["status"] == "complete"
      assert is_nil(p["usage"])
    end
  end

  describe "complete_run/1" do
    test "marks manifest as complete with final counts", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr1")
      Output.init_run(output_dir, perspectives(["a", "b"]), nil)
      Output.write_perspective(output_dir, "a", "done", usage())
      Output.write_perspective(output_dir, "b", "done", usage())

      assert :ok = Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)
      assert manifest["status"] == "complete"
      assert manifest["perspectives_completed"] == 2
      assert is_binary(manifest["completed_at"])
    end

    test "marks partial when not all perspectives finished", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr2")
      Output.init_run(output_dir, perspectives(["a", "b", "c"]), nil)
      Output.write_perspective(output_dir, "a", "done", usage())

      assert :ok = Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)
      assert manifest["status"] == "partial"
      assert manifest["perspectives_completed"] == 1
    end

    test "computes total_cost and total_tokens from all sources", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr_totals")
      router_usage = usage(50, 100, 0.005)
      Output.init_run(output_dir, perspectives(["a", "b"]), router_usage)

      Output.write_perspective(output_dir, "a", "done", usage(100, 200, 0.01))
      Output.write_perspective(output_dir, "b", "done", usage(80, 160, 0.008))
      Output.write_synthesis(output_dir, "synthesis", usage(40, 80, 0.004))

      Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)

      # 0.005 + 0.01 + 0.008 + 0.004 = 0.027
      assert_in_delta manifest["total_cost"], 0.027, 0.0001
      # (50+100) + (100+200) + (80+160) + (40+80) = 150 + 300 + 240 + 120 = 810
      assert manifest["total_tokens"] == 810
    end

    test "nil usage handled gracefully in totals", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr_nil")
      Output.init_run(output_dir, perspectives(["a", "b"]), nil)

      Output.write_perspective(output_dir, "a", "done", usage(100, 200, 0.01))
      Output.write_perspective(output_dir, "b", "done", nil)

      Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)

      # Only perspective "a" contributes
      assert_in_delta manifest["total_cost"], 0.01, 0.0001
      assert manifest["total_tokens"] == 300
    end

    test "totals without synthesis or router_usage", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr_minimal")
      Output.init_run(output_dir, perspectives(["a"]), nil)

      Output.write_perspective(output_dir, "a", "done", usage(10, 20, 0.001))

      Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)

      assert_in_delta manifest["total_cost"], 0.001, 0.0001
      assert manifest["total_tokens"] == 30
    end
  end

  describe "kill safety" do
    test "manifest is valid JSON after each write (atomic rename)", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "ks1")
      Output.init_run(output_dir, perspectives(["a", "b", "c"]), nil)

      # After init
      assert {:ok, _} = Jason.decode(File.read!(manifest_path(output_dir)))

      # After each write
      Output.write_perspective(output_dir, "a", "content", usage())
      assert {:ok, _} = Jason.decode(File.read!(manifest_path(output_dir)))

      Output.write_perspective(output_dir, "b", "content", usage())
      assert {:ok, _} = Jason.decode(File.read!(manifest_path(output_dir)))
    end

    test "no tmp file left after write", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "ks2")
      Output.init_run(output_dir, perspectives(["a"]), nil)
      Output.write_perspective(output_dir, "a", "content", usage())

      refute File.exists?(manifest_path(output_dir) <> ".tmp")
    end
  end

  describe "result_envelope/1" do
    test "returns structured envelope with model per perspective", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re1")
      Output.init_run(output_dir, perspectives(["a", "b"]), nil)
      Output.write_perspective(output_dir, "a", "content a", usage())
      Output.write_perspective(output_dir, "b", "content b", usage())
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      assert envelope.output_dir == output_dir
      assert envelope.status == "complete"
      assert length(envelope.perspectives) == 2
      assert Enum.all?(envelope.perspectives, &(&1.status == "complete"))
      assert Enum.all?(envelope.perspectives, &is_binary(&1.model))
      assert length(envelope.files) == 2
    end

    test "includes total_cost and total_tokens", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re_cost")
      Output.init_run(output_dir, perspectives(["a"]), usage(50, 100, 0.005))
      Output.write_perspective(output_dir, "a", "content", usage(100, 200, 0.01))
      Output.write_synthesis(output_dir, "syn", usage(30, 60, 0.003))
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      assert_in_delta envelope.total_cost, 0.018, 0.0001
      assert envelope.total_tokens == 540
    end
  end

  describe "write_synthesis/3" do
    test "writes synthesis file and updates manifest", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "syn1")
      Output.init_run(output_dir, perspectives(["a", "b"]), nil)
      Output.write_perspective(output_dir, "a", "content a", usage())

      synthesis = "## Agreement\nBoth agree.\n## Disagreement\nNone."
      assert :ok = Output.write_synthesis(output_dir, synthesis, usage(40, 80, 0.004))

      assert File.read!(Path.join(output_dir, "synthesis.md")) == synthesis

      manifest = read_manifest(output_dir)
      assert manifest["synthesis"]["status"] == "complete"
      assert manifest["synthesis"]["file"] == "synthesis.md"
      assert is_binary(manifest["synthesis"]["completed_at"])
      assert manifest["synthesis"]["usage"]["prompt_tokens"] == 40
      assert manifest["synthesis"]["usage"]["cost"] == 0.004
    end

    test "nil usage stored as null in synthesis manifest entry", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "syn_nil")
      Output.init_run(output_dir, perspectives(["a"]), nil)

      Output.write_synthesis(output_dir, "content", nil)
      manifest = read_manifest(output_dir)
      assert is_nil(manifest["synthesis"]["usage"])
    end
  end

  describe "result_envelope with synthesis" do
    test "includes synthesis in envelope when present", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re2")
      Output.init_run(output_dir, perspectives(["a"]), nil)
      Output.write_perspective(output_dir, "a", "content a", usage())
      Output.write_synthesis(output_dir, "synthesis content", usage())
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      assert envelope.synthesis.status == "complete"
      assert envelope.synthesis.file == "synthesis.md"
    end

    test "omits synthesis from envelope when not present", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re3")
      Output.init_run(output_dir, perspectives(["a"]), nil)
      Output.write_perspective(output_dir, "a", "content a", usage())
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      refute Map.has_key?(envelope, :synthesis)
    end
  end

  describe "write_perspective/4 — edge cases" do
    test "unknown role does not crash, perspectives list unchanged", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "unk1")
      Output.init_run(output_dir, perspectives(["a", "b"]), nil)

      assert :ok = Output.write_perspective(output_dir, "unknown-role", "content", nil)

      assert File.exists?(Path.join(output_dir, "0-unknown-role.md"))

      manifest = read_manifest(output_dir)
      assert length(manifest["perspectives"]) == 2
      assert Enum.all?(manifest["perspectives"], &(&1["status"] == "pending"))
      assert manifest["perspectives_completed"] == 0
    end

    test "duplicate roles get separate files and independent completion", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "dup1")

      # Two perspectives with the same role but different priorities
      dupes = [
        %Perspective{role: "analyst", model: "model-a", system_prompt: "First.", priority: 1},
        %Perspective{role: "analyst", model: "model-b", system_prompt: "Second.", priority: 2}
      ]

      Output.init_run(output_dir, dupes, nil)

      Output.write_perspective(output_dir, "analyst", "first output", usage(10, 20, 0.001))
      manifest = read_manifest(output_dir)
      assert manifest["perspectives_completed"] == 1
      assert File.exists?(Path.join(output_dir, "1-analyst.md"))

      Output.write_perspective(output_dir, "analyst", "second output", usage(30, 40, 0.002))
      manifest = read_manifest(output_dir)
      assert manifest["perspectives_completed"] == 2
      assert File.exists?(Path.join(output_dir, "2-analyst.md"))

      # Both files have distinct content
      assert File.read!(Path.join(output_dir, "1-analyst.md")) == "first output"
      assert File.read!(Path.join(output_dir, "2-analyst.md")) == "second output"
    end
  end

  describe "slugify/1" do
    test "converts role names to filesystem-safe slugs" do
      assert Output.slugify("Security Analyst") == "security-analyst"
      assert Output.slugify("performance_engineer") == "performance-engineer"
      assert Output.slugify("AI/ML Expert") == "ai-ml-expert"
      assert Output.slugify("  spaced  out  ") == "spaced-out"
    end

    test "empty string returns empty string" do
      assert Output.slugify("") == ""
    end

    test "unicode characters are stripped" do
      assert Output.slugify("café résumé") == "caf-r-sum"
    end

    test "consecutive special chars collapse to single hyphen" do
      assert Output.slugify("a///b---c   d") == "a-b-c-d"
    end
  end

  defp manifest_path(output_dir), do: Path.join(output_dir, "manifest.json")

  defp read_manifest(output_dir) do
    output_dir |> manifest_path() |> File.read!() |> Jason.decode!()
  end
end
