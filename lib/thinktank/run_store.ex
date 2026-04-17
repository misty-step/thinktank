defmodule Thinktank.RunStore do
  @moduledoc """
  Artifact store for bench executions.
  """

  require Logger

  alias Thinktank.{BenchSpec, RunContract}
  alias Thinktank.Pricing
  alias Thinktank.TraceLog

  @manifest_file "manifest.json"
  @scratchpad_dir "scratchpads"
  @stream_dir "artifacts/streams"

  @spec init_run(Path.t(), RunContract.t(), BenchSpec.t()) :: :ok
  def init_run(output_dir, %RunContract{} = contract, %BenchSpec{} = bench) do
    mkdir_private!(output_dir)
    mkdir_private!(Path.join(output_dir, "agents"))
    mkdir_private!(Path.join(output_dir, "artifacts"))
    mkdir_private!(Path.join(output_dir, @stream_dir))
    mkdir_private!(Path.join(output_dir, "prompts"))
    mkdir_private!(Path.join(output_dir, "pi-home"))
    mkdir_private!(Path.join(output_dir, @scratchpad_dir))
    started_at = now_iso8601()

    manifest = %{
      "version" => version(),
      "bench" => bench.id,
      "kind" => Atom.to_string(bench.kind),
      "status" => "running",
      "workspace_root" => contract.workspace_root,
      "started_at" => started_at,
      "completed_at" => nil,
      "input" => normalize(contract.input),
      "adapter_context" => normalize(contract.adapter_context || %{}),
      "planned_agents" => bench.agents,
      "synthesizer" => bench.synthesizer,
      "agents" => [],
      "artifacts" => [],
      "usd_cost_total" => 0.0,
      "usd_cost_by_model" => %{},
      "pricing_gaps" => []
    }

    write_manifest(output_dir, manifest)
    write_json(Path.join(output_dir, "contract.json"), RunContract.to_map(contract))
    record_artifact(output_dir, "contract", "contract.json", "json")

    TraceLog.init_run(output_dir, %{
      "bench" => bench.id,
      "workspace_root" => contract.workspace_root,
      "started_at" => started_at,
      "status" => "running"
    })

    record_artifact(output_dir, "trace-events", TraceLog.events_file(), "jsonl")
    record_artifact(output_dir, "trace-summary", TraceLog.summary_file(), "json")
    init_run_scratchpad(output_dir, contract, bench, started_at)
  end

  @spec record_agent_result(Path.t(), String.t(), String.t(), map()) :: :ok
  def record_agent_result(output_dir, agent_name, output, metadata \\ %{}) do
    metadata =
      metadata
      |> normalize()
      |> normalize_usage()

    instance_id = agent_instance_id(agent_name, metadata)
    metadata = attach_agent_artifact_refs(metadata, instance_id)
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

      manifest
      |> Map.put("agents", agents)
      |> Map.merge(pricing_summary(agents))
    end)
  end

  @spec init_agent_scratchpad(Path.t(), String.t(), String.t(), map()) :: :ok
  def init_agent_scratchpad(output_dir, agent_name, instance_id, metadata \\ %{}) do
    scratchpad = render_agent_scratchpad(agent_name, instance_id, metadata)

    if manifest_exists?(output_dir) do
      write_text_artifact(
        output_dir,
        "agent-scratchpad-#{instance_id}",
        agent_scratchpad_file(instance_id),
        scratchpad
      )

      write_text_artifact(
        output_dir,
        "agent-stream-#{instance_id}",
        agent_stream_file(instance_id),
        ""
      )
    else
      write_artifact_file(output_dir, agent_scratchpad_file(instance_id), scratchpad)
      write_artifact_file(output_dir, agent_stream_file(instance_id), "")
    end
  end

  @spec append_run_note(Path.t(), String.t()) :: :ok
  def append_run_note(output_dir, note) when is_binary(note) do
    append_text(output_dir, run_scratchpad_file(), format_note(note))
  end

  @spec append_agent_note(Path.t(), String.t(), String.t()) :: :ok
  def append_agent_note(output_dir, instance_id, note)
      when is_binary(instance_id) and is_binary(note) do
    append_text(output_dir, agent_scratchpad_file(instance_id), format_note(note))
  end

  @spec append_agent_output(Path.t(), String.t(), String.t()) :: :ok
  def append_agent_output(output_dir, instance_id, chunk)
      when is_binary(instance_id) and is_binary(chunk) do
    if chunk != "" do
      append_text(output_dir, agent_stream_file(instance_id), chunk)
    else
      :ok
    end
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
    completed_at = now_iso8601()

    update_manifest(output_dir, fn manifest ->
      %{manifest | "status" => status, "completed_at" => completed_at}
    end)

    TraceLog.complete_run(output_dir, %{"status" => status, "completed_at" => completed_at})
  end

  @spec set_planned_agents(Path.t(), [String.t()]) :: :ok
  def set_planned_agents(output_dir, planned_agents) when is_list(planned_agents) do
    names = Enum.filter(planned_agents, &is_binary/1)

    update_manifest(output_dir, fn manifest ->
      %{manifest | "planned_agents" => names}
    end)
  end

  @spec ensure_partial_summary(Path.t()) :: :ok
  def ensure_partial_summary(output_dir) do
    manifest = read_manifest(output_dir)

    if summary_artifact(manifest["artifacts"]) == nil do
      content = render_partial_summary(output_dir, manifest)

      write_text_artifact(output_dir, "summary", "summary.md", content)

      case manifest["kind"] do
        "review" ->
          write_text_artifact(output_dir, "review", "review.md", content)

        "research" ->
          write_text_artifact(output_dir, "synthesis", "synthesis.md", content)

        _ ->
          :ok
      end
    else
      :ok
    end
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
      started_at: manifest["started_at"],
      completed_at: manifest["completed_at"],
      duration_ms: duration_ms(manifest["started_at"], manifest["completed_at"]),
      agents: manifest["agents"],
      artifacts: artifacts,
      usd_cost_total: manifest["usd_cost_total"],
      usd_cost_by_model: manifest["usd_cost_by_model"],
      pricing_gaps: manifest["pricing_gaps"],
      synthesis: read_synthesis(output_dir, artifacts)
    }
  end

  defp content_type("json", _file), do: "application/json"
  defp content_type("jsonl", _file), do: "application/x-ndjson"

  defp content_type("text", file) when is_binary(file) do
    if String.ends_with?(file, ".md"), do: "text/markdown", else: "text/plain"
  end

  defp content_type(_type, _file), do: "application/octet-stream"

  defp read_synthesis(output_dir, artifacts) do
    artifacts
    |> summary_artifact()
    |> read_artifact(output_dir)
  end

  defp summary_artifact(artifacts) do
    Enum.find_value(["synthesis", "review", "summary"], fn name ->
      Enum.find(artifacts, &(&1["name"] == name))
    end)
  end

  defp read_artifact(nil, _output_dir), do: nil

  defp read_artifact(%{"file" => file}, output_dir) do
    path = Path.join(output_dir, file)
    if File.exists?(path), do: File.read!(path), else: nil
  end

  defp init_run_scratchpad(output_dir, contract, bench, started_at) do
    write_text_artifact(
      output_dir,
      "run-scratchpad",
      run_scratchpad_file(),
      render_run_scratchpad(contract, bench, started_at)
    )
  end

  defp render_run_scratchpad(contract, bench, started_at) do
    paths =
      contract.input
      |> Map.get("paths", [])
      |> Enum.map_join("\n", &"- #{&1}")

    """
    # Run Scratchpad

    - status: running
    - mode: #{Atom.to_string(bench.kind)}
    - bench: #{bench.id}
    - started_at: #{started_at}
    - output_dir: #{contract.artifact_dir}
    - workspace_root: #{contract.workspace_root}
    - planned_agents: #{Enum.join(bench.agents, ", ")}
    - synthesizer: #{bench.synthesizer || "none"}
    - task: #{Map.get(contract.input, "input_text", "")}
    - paths:
    #{if paths == "", do: "- none", else: paths}

    ## Journal

    #{format_note("run initialized")}
    """
  end

  defp render_agent_scratchpad(agent_name, instance_id, metadata) do
    model = Map.get(metadata, :model) || Map.get(metadata, "model") || "unknown"
    provider = Map.get(metadata, :provider) || Map.get(metadata, "provider") || "unknown"
    bench = Map.get(metadata, :bench) || Map.get(metadata, "bench") || "unknown"
    started_at = Map.get(metadata, :started_at) || Map.get(metadata, "started_at") || "pending"

    """
    # Agent Scratchpad

    - agent: #{agent_name}
    - instance_id: #{instance_id}
    - status: running
    - started_at: #{started_at}
    - bench: #{bench}
    - model: #{model}
    - provider: #{provider}
    - stream: #{agent_stream_file(instance_id)}

    ## Journal

    #{format_note("scratchpad initialized")}
    """
  end

  defp render_partial_summary(output_dir, manifest) do
    task =
      case read_file_if_present(Path.join(output_dir, "task.md")) do
        nil -> "_No task artifact was written before the run ended._"
        body -> body
      end

    agent_sections =
      manifest
      |> partial_agent_entries(output_dir)
      |> Enum.map_join("\n\n", &render_partial_agent_section(output_dir, &1))

    """
    # Partial Result

    ThinkTank finalized this run as `partial` because the bench ended before a complete result could be synthesized.

    - Bench: #{manifest["bench"]}
    - Mode: #{manifest["kind"]}
    - Started: #{manifest["started_at"]}
    - Completed: #{manifest["completed_at"] || "pending"}
    - USD Cost: #{render_usd_cost(manifest["usd_cost_total"], manifest["pricing_gaps"])}
    - Run scratchpad: `#{run_scratchpad_file()}`

    ## Task

    #{task}

    ## Available Artifacts

    #{if agent_sections == "", do: "_No agent artifacts were captured before the run ended._", else: agent_sections}
    """
    |> String.trim()
  end

  defp partial_agent_entries(manifest, output_dir) do
    manifest_entries =
      Enum.map(manifest["agents"], fn agent ->
        %{
          "id" => agent["id"],
          "name" => agent["name"],
          "status" => get_in(agent, ["metadata", "status"]) || "unknown",
          "result_file" => agent["file"],
          "scratchpad_file" =>
            get_in(agent, ["metadata", "scratchpad"]) || agent_scratchpad_file(agent["id"]),
          "stream_file" => get_in(agent, ["metadata", "stream"]) || agent_stream_file(agent["id"])
        }
      end)

    scratchpad_entries =
      output_dir
      |> Path.join(Path.join(@scratchpad_dir, "*.md"))
      |> Path.wildcard()
      |> Enum.reject(&(Path.basename(&1) == "run.md"))
      |> Enum.map(fn path ->
        instance_id = Path.basename(path, ".md")

        %{
          "id" => instance_id,
          "name" => instance_id,
          "status" => "incomplete",
          "result_file" => nil,
          "scratchpad_file" => Path.relative_to(path, output_dir),
          "stream_file" => agent_stream_file(instance_id)
        }
      end)

    (manifest_entries ++ scratchpad_entries)
    |> Enum.uniq_by(& &1["id"])
  end

  defp render_partial_agent_section(output_dir, entry) do
    excerpt =
      entry
      |> partial_excerpt(output_dir)
      |> case do
        nil -> "_No captured output yet._"
        body -> "```text\n#{body}\n```"
      end

    """
    ### #{entry["name"]}

    - Status: #{entry["status"]}
    - Scratchpad: `#{entry["scratchpad_file"]}`
    - Stream: `#{entry["stream_file"]}`

    #{excerpt}
    """
    |> String.trim()
  end

  defp partial_excerpt(entry, output_dir) do
    [entry["stream_file"], entry["result_file"], entry["scratchpad_file"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.find_value(fn file ->
      case read_file_if_present(Path.join(output_dir, file)) do
        nil -> nil
        "" -> nil
        body -> excerpt(body, 1_200)
      end
    end)
  end

  defp read_file_if_present(path) when is_binary(path) do
    if File.exists?(path), do: File.read!(path), else: nil
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

  defp attach_agent_artifact_refs(metadata, instance_id) do
    metadata
    |> Map.put_new("scratchpad", agent_scratchpad_file(instance_id))
    |> Map.put_new("stream", agent_stream_file(instance_id))
  end

  defp normalize_usage(metadata) do
    model = Map.get(metadata, "model")

    case Pricing.normalize_usage(model, Map.get(metadata, "usage")) do
      nil ->
        metadata

      usage ->
        maybe_warn_pricing_gap(model, usage["pricing_gap"])
        Map.put(metadata, "usage", usage)
    end
  end

  defp maybe_warn_pricing_gap(_model, nil), do: :ok

  defp maybe_warn_pricing_gap(model, gap) when is_binary(gap) do
    Logger.warning("pricing unavailable for #{model}: #{gap}")
  end

  defp pricing_summary(agents) do
    initial = %{models: %{}, pricing_gaps: MapSet.new(), usd_cost_total: 0.0}

    summary =
      Enum.reduce(agents, initial, fn agent, acc ->
        case get_in(agent, ["metadata", "usage"]) do
          %{} = usage ->
            merge_usage_summary(acc, usage)

          _ ->
            acc
        end
      end)

    %{
      "usd_cost_total" =>
        if(MapSet.size(summary.pricing_gaps) == 0,
          do: round_usd(summary.usd_cost_total),
          else: nil
        ),
      "usd_cost_by_model" => summary.models,
      "pricing_gaps" => summary.pricing_gaps |> MapSet.to_list() |> Enum.sort()
    }
  end

  defp merge_usage_summary(acc, usage) do
    model = usage["model"] || "unknown"
    entry = Map.get(acc.models, model, empty_model_summary(model))

    merged_entry =
      entry
      |> Map.update!("input_tokens", &(&1 + usage["input_tokens"]))
      |> Map.update!("output_tokens", &(&1 + usage["output_tokens"]))
      |> Map.update!("cache_read_tokens", &(&1 + usage["cache_read_tokens"]))
      |> Map.update!("cache_write_tokens", &(&1 + usage["cache_write_tokens"]))
      |> Map.update!("total_tokens", &(&1 + usage["total_tokens"]))
      |> merge_model_cost(usage["usd_cost"])
      |> merge_model_gap(usage["pricing_gap"])

    %{
      acc
      | models: Map.put(acc.models, model, merged_entry),
        pricing_gaps: maybe_put_gap(acc.pricing_gaps, usage["pricing_gap"], model),
        usd_cost_total:
          if(is_number(usage["usd_cost"]),
            do: acc.usd_cost_total + usage["usd_cost"],
            else: acc.usd_cost_total
          )
    }
  end

  defp merge_model_cost(entry, nil), do: Map.put(entry, "usd_cost", nil)
  defp merge_model_cost(%{"usd_cost" => nil} = entry, _usd_cost), do: entry

  defp merge_model_cost(entry, usd_cost) when is_number(usd_cost) do
    Map.update!(entry, "usd_cost", &round_usd(&1 + usd_cost))
  end

  defp merge_model_gap(entry, nil), do: entry
  defp merge_model_gap(entry, gap), do: Map.put(entry, "pricing_gap", gap)

  defp maybe_put_gap(gaps, nil, _model), do: gaps
  defp maybe_put_gap(gaps, _gap, model), do: MapSet.put(gaps, model)

  defp empty_model_summary(model) do
    %{
      "model" => model,
      "input_tokens" => 0,
      "output_tokens" => 0,
      "cache_read_tokens" => 0,
      "cache_write_tokens" => 0,
      "total_tokens" => 0,
      "usd_cost" => 0.0,
      "pricing_gap" => nil
    }
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
  defp manifest_exists?(output_dir), do: File.exists?(manifest_path(output_dir))

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

  defp write_artifact_file(output_dir, filename, content) do
    path = resolve_artifact_path(output_dir, filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    File.chmod!(path, 0o600)
    :ok
  end

  defp append_text(output_dir, filename, content) do
    path = resolve_artifact_path(output_dir, filename)
    ensure_private_parent!(path)

    created? = not File.exists?(path)

    File.open!(path, [:append, :binary], fn io ->
      IO.binwrite(io, content)
      :file.sync(io)
    end)

    if created? do
      File.chmod!(path, 0o600)
    end

    :ok
  end

  defp format_note(note) do
    "[#{now_iso8601()}] #{String.trim(note)}\n"
  end

  defp excerpt(body, max_bytes) when is_binary(body) and is_integer(max_bytes) do
    body
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max_bytes)
    end
  end

  defp run_scratchpad_file, do: Path.join(@scratchpad_dir, "run.md")
  defp agent_scratchpad_file(instance_id), do: Path.join(@scratchpad_dir, "#{instance_id}.md")
  defp agent_stream_file(instance_id), do: Path.join(@stream_dir, "#{instance_id}.txt")

  defp render_usd_cost(total, []), do: "$" <> format_usd(total)

  defp render_usd_cost(_total, pricing_gaps) do
    "unavailable (pricing gap: #{Enum.join(pricing_gaps, ", ")})"
  end

  defp format_usd(total) when is_number(total), do: :erlang.float_to_binary(total, decimals: 6)
  defp format_usd(_total), do: "0.000000"

  defp round_usd(value) when is_number(value), do: Float.round(value, 12)

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

  defp ensure_private_parent!(path) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    dir
  end

  defp version do
    case Application.spec(:thinktank, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp duration_ms(started_at, completed_at)
       when is_binary(started_at) and is_binary(completed_at) do
    with {:ok, start_dt, _} <- DateTime.from_iso8601(started_at),
         {:ok, end_dt, _} <- DateTime.from_iso8601(completed_at) do
      DateTime.diff(end_dt, start_dt, :millisecond)
    else
      _ -> nil
    end
  end

  defp duration_ms(_, _), do: nil
end
