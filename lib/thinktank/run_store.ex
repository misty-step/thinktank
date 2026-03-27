defmodule Thinktank.RunStore do
  @moduledoc """
  Generic run artifact store for workflow executions.
  """

  alias Thinktank.{RunContract, WorkflowSpec}

  @manifest_file "manifest.json"

  @spec init_run(Path.t(), RunContract.t(), WorkflowSpec.t()) :: :ok
  def init_run(output_dir, %RunContract{} = contract, %WorkflowSpec{} = workflow) do
    File.mkdir_p!(output_dir)
    File.mkdir_p!(Path.join(output_dir, "stages"))
    File.mkdir_p!(Path.join(output_dir, "agents"))
    File.mkdir_p!(Path.join(output_dir, "artifacts"))

    manifest = %{
      "version" => version(),
      "workflow" => workflow.id,
      "mode" => to_string(contract.mode),
      "status" => "running",
      "workspace_root" => contract.workspace_root,
      "started_at" => now_iso8601(),
      "completed_at" => nil,
      "input" => normalize(contract.input),
      "adapter_context" => normalize(contract.adapter_context || %{}),
      "stages" =>
        Enum.map(workflow.stages, fn stage ->
          %{
            "name" => stage.name,
            "type" => to_string(stage.type),
            "kind" => stage.kind,
            "status" => "pending",
            "attempts" => 0,
            "file" => nil
          }
        end),
      "agents" => [],
      "artifacts" => []
    }

    write_manifest(output_dir, manifest)
    write_json(Path.join(output_dir, "contract.json"), RunContract.to_map(contract))
    record_artifact(output_dir, "contract", "contract.json", "json")
  end

  @spec record_stage(Path.t(), String.t(), String.t(), non_neg_integer(), map()) :: :ok
  def record_stage(output_dir, stage_name, status, attempts, data \\ %{}) do
    file = Path.join(["stages", "#{slugify(stage_name)}.json"])
    write_json(Path.join(output_dir, file), data)

    update_manifest(output_dir, fn manifest ->
      stages =
        Enum.map(manifest["stages"], fn stage ->
          if stage["name"] == stage_name do
            %{stage | "status" => status, "attempts" => attempts, "file" => file}
          else
            stage
          end
        end)

      %{manifest | "stages" => stages}
    end)
  end

  @spec record_agent_result(Path.t(), String.t(), String.t(), map()) :: :ok
  def record_agent_result(output_dir, agent_name, output, metadata \\ %{}) do
    file = Path.join(["agents", "#{slugify(agent_name)}.md"])
    File.write!(Path.join(output_dir, file), output)

    update_manifest(output_dir, fn manifest ->
      agents =
        manifest["agents"]
        |> Enum.reject(&(&1["name"] == agent_name))
        |> Kernel.++([
          %{
            "name" => agent_name,
            "file" => file,
            "metadata" => normalize(metadata)
          }
        ])

      %{manifest | "agents" => agents}
    end)
  end

  @spec write_text_artifact(Path.t(), String.t(), String.t(), String.t()) :: :ok
  def write_text_artifact(output_dir, name, filename, content) do
    path = resolve_artifact_path(output_dir, filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    record_artifact(output_dir, name, filename, "text")
  end

  @spec write_json_artifact(Path.t(), String.t(), String.t(), map()) :: :ok
  def write_json_artifact(output_dir, name, filename, data) do
    path = resolve_artifact_path(output_dir, filename)
    write_json(path, data)
    record_artifact(output_dir, name, filename, "json")
  end

  @spec complete_run(Path.t(), String.t()) :: :ok
  def complete_run(output_dir, status) do
    update_manifest(output_dir, fn manifest ->
      %{manifest | "status" => status, "completed_at" => now_iso8601()}
    end)
  end

  @spec result_envelope(Path.t()) :: map()
  def result_envelope(output_dir) do
    manifest = read_manifest(output_dir)

    %{
      output_dir: output_dir,
      workflow: manifest["workflow"],
      mode: manifest["mode"],
      status: manifest["status"],
      agents: manifest["agents"],
      artifacts: manifest["artifacts"]
    }
  end

  defp resolve_artifact_path(output_dir, filename) do
    if String.contains?(filename, "/") do
      Path.join(output_dir, filename)
    else
      Path.join(output_dir, filename)
    end
  end

  defp record_artifact(output_dir, name, filename, type) do
    update_manifest(output_dir, fn manifest ->
      artifacts =
        manifest["artifacts"]
        |> Enum.reject(&(&1["name"] == name))
        |> Kernel.++([
          %{
            "name" => name,
            "file" => filename,
            "type" => type
          }
        ])

      %{manifest | "artifacts" => artifacts}
    end)
  end

  defp update_manifest(output_dir, fun) do
    manifest = read_manifest(output_dir)
    write_manifest(output_dir, fun.(manifest))
  end

  defp normalize(%{} = value) do
    value
    |> Enum.map(fn {key, entry} -> {to_string(key), normalize(entry)} end)
    |> Enum.into(%{})
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp normalize(nil), do: nil
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: inspect(value)

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

  defp write_json(path, data) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(normalize(data), pretty: true))
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()
  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
