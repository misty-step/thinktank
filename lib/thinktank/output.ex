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
  initial manifest with all perspectives in pending state.
  """
  @spec init_run(Path.t(), [String.t()]) :: :ok
  def init_run(output_dir, roles) do
    File.mkdir_p!(output_dir)

    manifest = %{
      "version" => version(),
      "status" => "running",
      "started_at" => now_iso8601(),
      "completed_at" => nil,
      "perspectives_completed" => 0,
      "perspectives" =>
        Enum.map(roles, fn role ->
          %{
            "role" => role,
            "status" => "pending",
            "file" => nil,
            "completed_at" => nil
          }
        end)
    }

    write_manifest(output_dir, manifest)
  end

  @doc """
  Write a perspective's content to disk and update the manifest.
  """
  @spec write_perspective(Path.t(), String.t(), String.t()) :: :ok
  def write_perspective(output_dir, role, content) do
    filename = slugify(role) <> ".md"
    File.write!(Path.join(output_dir, filename), content)

    manifest = read_manifest(output_dir)

    perspectives =
      Enum.map(manifest["perspectives"], fn p ->
        if p["role"] == role do
          %{p | "status" => "complete", "file" => filename, "completed_at" => now_iso8601()}
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
  """
  @spec write_synthesis(Path.t(), String.t()) :: :ok
  def write_synthesis(output_dir, content) do
    filename = "synthesis.md"
    File.write!(Path.join(output_dir, filename), content)

    manifest = read_manifest(output_dir)

    write_manifest(
      output_dir,
      Map.put(manifest, "synthesis", %{
        "status" => "complete",
        "file" => filename,
        "completed_at" => now_iso8601()
      })
    )
  end

  @doc """
  Finalize the run. Sets status to "complete" if all perspectives
  finished, "partial" otherwise.
  """
  @spec complete_run(Path.t()) :: :ok
  def complete_run(output_dir) do
    manifest = read_manifest(output_dir)
    total = length(manifest["perspectives"])
    completed = Enum.count(manifest["perspectives"], &(&1["status"] == "complete"))

    status = if completed == total, do: "complete", else: "partial"

    write_manifest(output_dir, %{
      manifest
      | "status" => status,
        "completed_at" => now_iso8601()
    })
  end

  @doc """
  Build a result envelope for `--json` stdout output.
  """
  @spec result_envelope(Path.t()) :: map()
  def result_envelope(output_dir) do
    manifest = read_manifest(output_dir)

    files =
      manifest["perspectives"]
      |> Enum.filter(&(&1["file"] != nil))
      |> Enum.map(& &1["file"])

    perspectives =
      Enum.map(manifest["perspectives"], fn p ->
        %{role: p["role"], status: p["status"], file: p["file"]}
      end)

    base = %{
      output_dir: output_dir,
      status: manifest["status"],
      perspectives: perspectives,
      files: files
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

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()
end
