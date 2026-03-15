defmodule Thinktank.OutputTest do
  use ExUnit.Case, async: true

  alias Thinktank.Output

  @moduletag :tmp_dir

  describe "init_run/2" do
    test "creates output dir and initial manifest", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run1")
      perspectives = ["security-analyst", "performance-engineer", "architect"]

      assert :ok = Output.init_run(output_dir, perspectives)
      assert File.dir?(output_dir)

      manifest = read_manifest(output_dir)
      assert manifest["status"] == "running"
      assert length(manifest["perspectives"]) == 3

      for p <- manifest["perspectives"] do
        assert p["status"] == "pending"
        assert is_nil(p["file"])
      end
    end

    test "manifest contains run metadata", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "run2")
      assert :ok = Output.init_run(output_dir, ["analyst"])

      manifest = read_manifest(output_dir)
      assert is_binary(manifest["started_at"])
      assert manifest["version"] == Thinktank.MixProject.project()[:version]
    end
  end

  describe "write_perspective/4" do
    test "writes perspective file and updates manifest", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "wp1")
      Output.init_run(output_dir, ["security-analyst", "architect"])

      content = "## Security Analysis\n\nNo critical vulnerabilities found."
      assert :ok = Output.write_perspective(output_dir, "security-analyst", content)

      # File written
      path = Path.join(output_dir, "security-analyst.md")
      assert File.read!(path) == content

      # Manifest updated
      manifest = read_manifest(output_dir)
      sa = Enum.find(manifest["perspectives"], &(&1["role"] == "security-analyst"))
      assert sa["status"] == "complete"
      assert sa["file"] == "security-analyst.md"
      assert is_binary(sa["completed_at"])

      # Other perspective still pending
      arch = Enum.find(manifest["perspectives"], &(&1["role"] == "architect"))
      assert arch["status"] == "pending"
    end

    test "handles multiple completions incrementally", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "wp2")
      Output.init_run(output_dir, ["a", "b", "c"])

      Output.write_perspective(output_dir, "a", "content a")
      manifest = read_manifest(output_dir)
      assert manifest["perspectives_completed"] == 1

      Output.write_perspective(output_dir, "b", "content b")
      manifest = read_manifest(output_dir)
      assert manifest["perspectives_completed"] == 2
    end
  end

  describe "complete_run/1" do
    test "marks manifest as complete with final counts", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr1")
      Output.init_run(output_dir, ["a", "b"])
      Output.write_perspective(output_dir, "a", "done")
      Output.write_perspective(output_dir, "b", "done")

      assert :ok = Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)
      assert manifest["status"] == "complete"
      assert manifest["perspectives_completed"] == 2
      assert is_binary(manifest["completed_at"])
    end

    test "marks partial when not all perspectives finished", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "cr2")
      Output.init_run(output_dir, ["a", "b", "c"])
      Output.write_perspective(output_dir, "a", "done")

      assert :ok = Output.complete_run(output_dir)
      manifest = read_manifest(output_dir)
      assert manifest["status"] == "partial"
      assert manifest["perspectives_completed"] == 1
    end
  end

  describe "kill safety" do
    test "manifest is valid JSON after each write (atomic rename)", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "ks1")
      Output.init_run(output_dir, ["a", "b", "c"])

      # After init
      assert {:ok, _} = Jason.decode(File.read!(manifest_path(output_dir)))

      # After each write
      Output.write_perspective(output_dir, "a", "content")
      assert {:ok, _} = Jason.decode(File.read!(manifest_path(output_dir)))

      Output.write_perspective(output_dir, "b", "content")
      assert {:ok, _} = Jason.decode(File.read!(manifest_path(output_dir)))
    end

    test "no tmp file left after write", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "ks2")
      Output.init_run(output_dir, ["a"])
      Output.write_perspective(output_dir, "a", "content")

      refute File.exists?(manifest_path(output_dir) <> ".tmp")
    end
  end

  describe "result_envelope/1" do
    test "returns structured JSON envelope for --json output", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re1")
      Output.init_run(output_dir, ["a", "b"])
      Output.write_perspective(output_dir, "a", "content a")
      Output.write_perspective(output_dir, "b", "content b")
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      assert envelope.output_dir == output_dir
      assert envelope.status == "complete"
      assert length(envelope.perspectives) == 2
      assert Enum.all?(envelope.perspectives, &(&1.status == "complete"))
      assert length(envelope.files) == 2
    end
  end

  describe "write_synthesis/2" do
    test "writes synthesis file and updates manifest", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "syn1")
      Output.init_run(output_dir, ["a", "b"])
      Output.write_perspective(output_dir, "a", "content a")

      synthesis = "## Agreement\nBoth agree.\n## Disagreement\nNone."
      assert :ok = Output.write_synthesis(output_dir, synthesis)

      assert File.read!(Path.join(output_dir, "synthesis.md")) == synthesis

      manifest = read_manifest(output_dir)
      assert manifest["synthesis"]["status"] == "complete"
      assert manifest["synthesis"]["file"] == "synthesis.md"
      assert is_binary(manifest["synthesis"]["completed_at"])
    end
  end

  describe "result_envelope with synthesis" do
    test "includes synthesis in envelope when present", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re2")
      Output.init_run(output_dir, ["a"])
      Output.write_perspective(output_dir, "a", "content a")
      Output.write_synthesis(output_dir, "synthesis content")
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      assert envelope.synthesis.status == "complete"
      assert envelope.synthesis.file == "synthesis.md"
    end

    test "omits synthesis from envelope when not present", %{tmp_dir: tmp} do
      output_dir = Path.join(tmp, "re3")
      Output.init_run(output_dir, ["a"])
      Output.write_perspective(output_dir, "a", "content a")
      Output.complete_run(output_dir)

      envelope = Output.result_envelope(output_dir)
      refute Map.has_key?(envelope, :synthesis)
    end
  end

  describe "slugify/1" do
    test "converts role names to filesystem-safe slugs" do
      assert Output.slugify("Security Analyst") == "security-analyst"
      assert Output.slugify("performance_engineer") == "performance-engineer"
      assert Output.slugify("AI/ML Expert") == "ai-ml-expert"
      assert Output.slugify("  spaced  out  ") == "spaced-out"
    end
  end

  defp manifest_path(output_dir), do: Path.join(output_dir, "manifest.json")

  defp read_manifest(output_dir) do
    output_dir |> manifest_path() |> File.read!() |> Jason.decode!()
  end
end
