defmodule Thinktank.RunStore do
  @moduledoc """
  Artifact store for bench executions.
  """

  alias Thinktank.{BenchSpec, RunContract}

  @manifest_file "manifest.json"

  @spec init_run(Path.t(), RunContract.t(), BenchSpec.t()) :: :ok
  def init_run(output_dir, %RunContract{} = contract, %BenchSpec{} = bench) do
    mkdir_private!(output_dir)
    mkdir_private!(Path.join(output_dir, "agents"))
    mkdir_private!(Path.join(output_dir, "artifacts"))
    mkdir_private!(Path.join(output_dir, "prompts"))
    mkdir_private!(Path.join(output_dir, "pi-home"))

    manifest = %{
      "version" => version(),
      "bench" => bench.id,
      "status" => "running",
      "workspace_root" => contract.workspace_root,
      "started_at" => now_iso8601(),
      "completed_at" => nil,
      "input" => normalize(contract.input),
      "adapter_context" => normalize(contract.adapter_context || %{}),
      "planned_agents" => bench.agents,
      "synthesizer" => bench.synthesizer,
      "agents" => [],
      "artifacts" => []
    }

    write_manifest(output_dir, manifest)
    write_json(Path.join(output_dir, "contract.json"), RunContract.to_map(contract))
    record_artifact(output_dir, "contract", "contract.json", "json")
  end

  @spec record_agent_result(Path.t(), String.t(), String.t(), map()) :: :ok
  def record_agent_result(output_dir, agent_name, output, metadata \\ %{}) do
    metadata = normalize(metadata)
    instance_id = agent_instance_id(agent_name, metadata)
    file = Path.join(["agents", "#{instance_id}.md"])
    File.write!(Path.join(output_dir, file), output)

    update_manifest(output_dir, fn manifest ->
      agents =
        manifest["agents"]
        |> Enum.reject(&(&1["id"] == instance_id))
        |> Kernel.++([
          %{
            "id" => instance_id,
            "name" => agent_name,
            "file" => file,
            "metadata" => metadata
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

  @spec set_planned_agents(Path.t(), [String.t()]) :: :ok
  def set_planned_agents(output_dir, planned_agents) when is_list(planned_agents) do
    names = Enum.filter(planned_agents, &is_binary/1)

    update_manifest(output_dir, fn manifest ->
      %{manifest | "planned_agents" => names}
    end)
  end

  @spec result_envelope(Path.t()) :: map()
  def result_envelope(output_dir) do
    manifest = read_manifest(output_dir)

    artifacts =
      Enum.map(manifest["artifacts"], fn artifact ->
        Map.put(artifact, "content_type", content_type(artifact["type"], artifact["file"]))
      end)

    %{
      output_dir: output_dir,
      bench: manifest["bench"],
      status: manifest["status"],
      agents: manifest["agents"],
      artifacts: artifacts,
      synthesis: read_synthesis(output_dir, artifacts)
    }
  end

  defp content_type("json", _file), do: "application/json"

  defp content_type("text", file) when is_binary(file) do
    if String.ends_with?(file, ".md"), do: "text/markdown", else: "text/plain"
  end

  defp content_type(_type, _file), do: "application/octet-stream"

  defp read_synthesis(output_dir, artifacts) do
    case Enum.find(artifacts, &(&1["name"] == "synthesis")) do
      nil ->
        nil

      %{"file" => file} ->
        path = Path.join(output_dir, file)
        if File.exists?(path), do: File.read!(path), else: nil
    end
  end

  defp resolve_artifact_path(output_dir, filename) do
    output_root = Path.expand(output_dir)
    path = Path.expand(filename, output_root)

    if path == output_root or String.starts_with?(path, output_root <> "/") do
      path
    else
      raise ArgumentError, "artifact path escapes output dir: #{filename}"
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

  defp stable_slug(name) do
    suffix =
      :crypto.hash(:sha256, name)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 8)

    "#{slugify(name)}-#{suffix}"
  end

  defp agent_instance_id(agent_name, metadata) do
    Map.get(metadata, "instance_id") || stable_slug(agent_name)
  end

  defp mkdir_private!(path) do
    File.mkdir_p!(path)
    File.chmod!(path, 0o700)
  end

  defp version do
    case Application.spec(:thinktank, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
