defmodule Thinktank.Output do
  @moduledoc """
  Kill-safe artifact writer with incremental manifest.

  Persists each perspective's output to disk as it completes.
  Manifest is atomically updated (tmp + rename) so it's always
  valid JSON, even if the process is killed mid-write.
  """

  @manifest_file "manifest.json"

  @doc """
  Initialize an output run: create the directory and write the
  initial manifest with full perspective configuration.

  `router_usage` is the usage map from the routing LLM call, or nil.
  """
  @spec init_run(Path.t(), [Thinktank.Perspective.t()], map() | nil) :: :ok
  def init_run(output_dir, perspectives, router_usage) do
    File.mkdir_p!(output_dir)

    manifest = %{
      "version" => version(),
      "status" => "running",
      "started_at" => now_iso8601(),
      "completed_at" => nil,
      "perspectives_completed" => 0,
      "router_usage" => normalize_usage(router_usage),
      "perspectives" =>
        Enum.map(perspectives, fn p ->
          %{
            "role" => p.role,
            "model" => p.model,
            "system_prompt" => p.system_prompt,
            "priority" => p.priority,
            "status" => "pending",
            "file" => nil,
            "completed_at" => nil,
            "usage" => nil
          }
        end)
    }

    write_manifest(output_dir, manifest)
  end

  @doc """
  Write a perspective's content to disk and update the manifest.

  `usage` is the usage map from the LLM call, or nil (deep mode).
  """
  @spec write_perspective(Path.t(), String.t(), String.t(), map() | nil) :: :ok
  def write_perspective(output_dir, role, content, usage) do
    filename = slugify(role) <> ".md"
    File.write!(Path.join(output_dir, filename), content)

    manifest = read_manifest(output_dir)

    perspectives =
      Enum.map(manifest["perspectives"], fn p ->
        if p["role"] == role do
          %{
            p
            | "status" => "complete",
              "file" => filename,
              "completed_at" => now_iso8601(),
              "usage" => normalize_usage(usage)
          }
        else
          p
        end
      end)

    completed = Enum.count(perspectives, &(&1["status"] == "complete"))

    write_manifest(output_dir, %{
      manifest
      | "perspectives" => perspectives,
        "perspectives_completed" => completed
    })
  end

  @doc """
  Write synthesis output and update manifest.

  `usage` is the usage map from the synthesis LLM call, or nil.
  """
  @spec write_synthesis(Path.t(), String.t(), map() | nil) :: :ok
  def write_synthesis(output_dir, content, usage) do
    filename = "synthesis.md"
    File.write!(Path.join(output_dir, filename), content)

    manifest = read_manifest(output_dir)

    write_manifest(
      output_dir,
      Map.put(manifest, "synthesis", %{
        "status" => "complete",
        "file" => filename,
        "completed_at" => now_iso8601(),
        "usage" => normalize_usage(usage)
      })
    )
  end

  @doc """
  Finalize the run. Sets status to "complete" if all perspectives
  finished, "partial" otherwise. Computes total_cost and total_tokens
  by summing all usage sources (router, perspectives, synthesis).
  """
  @spec complete_run(Path.t()) :: :ok
  def complete_run(output_dir) do
    manifest = read_manifest(output_dir)
    total = length(manifest["perspectives"])
    completed = Enum.count(manifest["perspectives"], &(&1["status"] == "complete"))

    status = if completed == total, do: "complete", else: "partial"

    usages =
      [manifest["router_usage"]] ++
        Enum.map(manifest["perspectives"], & &1["usage"]) ++
        [get_in(manifest, ["synthesis", "usage"])]

    {total_cost, total_tokens} = sum_usages(usages)

    write_manifest(
      output_dir,
      %{
        manifest
        | "status" => status,
          "completed_at" => now_iso8601()
      }
      |> Map.put("total_cost", total_cost)
      |> Map.put("total_tokens", total_tokens)
    )
  end

  @type perspective_summary :: %{
          role: String.t(),
          model: String.t(),
          status: String.t(),
          file: String.t() | nil
        }

  @type envelope :: %{
          output_dir: Path.t(),
          status: String.t(),
          perspectives: [perspective_summary()],
          files: [String.t()],
          total_cost: float(),
          total_tokens: non_neg_integer()
        }

  @doc """
  Build a result envelope for `--json` stdout output.
  """
  @spec result_envelope(Path.t()) :: envelope()
  def result_envelope(output_dir) do
    manifest = read_manifest(output_dir)

    files =
      manifest["perspectives"]
      |> Enum.filter(&(&1["file"] != nil))
      |> Enum.map(& &1["file"])

    perspectives =
      Enum.map(manifest["perspectives"], fn p ->
        %{role: p["role"], model: p["model"], status: p["status"], file: p["file"]}
      end)

    base = %{
      output_dir: output_dir,
      status: manifest["status"],
      perspectives: perspectives,
      files: files,
      total_cost: manifest["total_cost"] || 0.0,
      total_tokens: manifest["total_tokens"] || 0
    }

    case manifest["synthesis"] do
      %{"file" => file} when is_binary(file) ->
        Map.put(base, :synthesis, %{
          status: manifest["synthesis"]["status"],
          file: file
        })

      _ ->
        base
    end
  end

  @doc """
  Convert a role name to a filesystem-safe slug.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  # -- Private --

  defp manifest_path(output_dir), do: Path.join(output_dir, @manifest_file)

  defp read_manifest(output_dir) do
    output_dir |> manifest_path() |> File.read!() |> Jason.decode!()
  end

  defp write_manifest(output_dir, manifest) do
    path = manifest_path(output_dir)
    tmp = path <> ".tmp"
    File.write!(tmp, Jason.encode!(manifest, pretty: true))
    File.rename!(tmp, path)
    :ok
  end

  # Normalize usage map to string keys for JSON serialization.
  # Handles both atom-keyed maps (from OpenRouter) and string-keyed (from manifest reads).
  defp normalize_usage(nil), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    %{
      "prompt_tokens" => usage[:prompt_tokens] || usage["prompt_tokens"] || 0,
      "completion_tokens" => usage[:completion_tokens] || usage["completion_tokens"] || 0,
      "total_tokens" => usage[:total_tokens] || usage["total_tokens"] || 0,
      "cost" => (usage[:cost] || usage["cost"] || 0) * 1.0
    }
  end

  # Sum cost and tokens from a list of usage maps (nils filtered out).
  defp sum_usages(usages) do
    usages
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce({0.0, 0}, fn u, {cost, tokens} ->
      {cost + (u["cost"] || 0), tokens + (u["total_tokens"] || 0)}
    end)
  end

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()
end
