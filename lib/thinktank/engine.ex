defmodule Thinktank.Engine do
  @moduledoc """
  Workflow engine for constrained stage-graph execution.
  """

  alias Thinktank.{
    AgentSpec,
    Config,
    Executor,
    Models,
    Router,
    RunContract,
    RunStore,
    StageSpec,
    Synthesis,
    WorkflowSpec
  }

  alias Thinktank.Review.{Diff, Verdict}

  @type run_result :: %{
          contract: RunContract.t(),
          workflow: WorkflowSpec.t(),
          output_dir: String.t(),
          envelope: map(),
          context: map()
        }

  @spec run(String.t(), map(), keyword()) :: {:ok, run_result()} | {:error, term(), String.t() | nil}
  def run(workflow_id, input, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    with {:ok, config} <- Config.load(cwd: cwd),
         {:ok, workflow} <- Config.workflow(config, workflow_id),
         :ok <- validate_input(workflow, input) do
      mode = Keyword.get(opts, :mode, workflow.default_mode)
      output_dir = Keyword.get(opts, :output, generate_output_dir(workflow_id))

      contract = %RunContract{
        workflow_id: workflow_id,
        workspace_root: cwd,
        input: input,
        artifact_dir: output_dir,
        adapter_context: Keyword.get(opts, :adapter_context, %{}),
        mode: mode
      }

      RunStore.init_run(output_dir, contract, workflow)

      case execute_stages(workflow.stages, %{}, contract, config, 0, opts) do
        {:ok, context} ->
          RunStore.complete_run(output_dir, "complete")

          {:ok,
           %{
             contract: contract,
             workflow: workflow,
             output_dir: output_dir,
             envelope: RunStore.result_envelope(output_dir),
             context: context
           }}

        {:error, reason} ->
          RunStore.write_json_artifact(output_dir, "failure", "artifacts/failure.json", %{error: inspect(reason)})
          RunStore.complete_run(output_dir, "failed")
          {:error, reason, output_dir}
      end
    end
  end

  @spec generate_output_dir(String.t()) :: String.t()
  def generate_output_dir(workflow_id) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    workflow_slug = workflow_id |> String.replace("/", "-") |> String.replace(~r/[^a-zA-Z0-9-]/, "")
    Path.join(System.tmp_dir!(), "thinktank-#{workflow_slug}-#{timestamp}-#{suffix}")
  end

  defp execute_stages([], context, _contract, _config, _index, _opts), do: {:ok, context}

  defp execute_stages([stage | rest], context, contract, config, index, opts) do
    if should_run?(stage, context) do
      case run_stage_with_retry(stage, context, contract, config, opts) do
        {:ok, outputs, final_attempts} ->
          merged = Map.merge(context, outputs)
          RunStore.record_stage(contract.artifact_dir, stage.name, "complete", final_attempts, stage_snapshot(outputs))
          execute_stages(rest, merged, contract, config, index + 1, opts)

        {:error, reason, final_attempts} ->
          RunStore.record_stage(
            contract.artifact_dir,
            stage.name,
            "failed",
            final_attempts,
            %{error: inspect(reason)}
          )

          {:error, {:stage_failed, stage.name, reason}}
      end
    else
      RunStore.record_stage(contract.artifact_dir, stage.name, "skipped", 0, %{})
      execute_stages(rest, context, contract, config, index + 1, opts)
    end
  end

  defp run_stage_with_retry(stage, context, contract, config, opts, attempt \\ 1)

  defp run_stage_with_retry(stage, context, contract, config, opts, attempt) do
    case run_stage(stage, context, contract, config, opts) do
      {:ok, outputs} ->
        {:ok, outputs, attempt}

      {:error, reason} ->
        if attempt <= stage.retry do
          run_stage_with_retry(stage, context, contract, config, opts, attempt + 1)
        else
          {:error, reason, attempt}
        end
    end
  end

  defp run_stage(%StageSpec{type: :prepare, kind: "research_input"}, _context, contract, _config, _opts) do
    input_text = input_value(contract.input, :input_text)
    paths = input_value(contract.input, :paths, [])
    context_files = read_context_files(paths)

    {:ok,
     %{
       input_text: input_text,
       paths: paths,
       context_files: context_files,
       context_block: build_context_block(context_files),
       review_bundle: "",
       result_kind: :research
     }}
  end

  defp run_stage(%StageSpec{type: :prepare, kind: "review_diff"}, _context, contract, _config, _opts) do
    with {:ok, prepared} <- load_review_input(contract) do
      diff_summary = Diff.parse(prepared.diff_text)

      {:ok,
       %{
         input_text:
           input_value(
             contract.input,
             :input_text,
             "Review the current change and report only real issues with evidence."
           ),
         diff_text: prepared.diff_text,
         changed_paths: prepared.changed_paths,
         base_ref: prepared.base_ref,
         head_ref: prepared.head_ref,
         review_metadata: prepared.metadata,
         diff_summary: diff_summary,
         review_bundle: build_review_bundle(prepared, diff_summary),
         result_kind: :review
       }}
    end
  end

  defp run_stage(%StageSpec{type: :route, kind: "research_router"} = stage, context, contract, _config, opts) do
    available_models = select_models(contract.input)
    count = input_value(contract.input, :perspectives, stage.options["count"] || 4)
    tier = input_value(contract.input, :tier, :standard)
    roles = input_value(contract.input, :roles, [])

    {perspectives, usage} =
      if roles != [] do
        {Router.manual_perspectives(roles, available_models), nil}
      else
        case Router.generate_perspectives(
               context.input_text,
               context.paths,
               available_models: available_models,
               perspectives: count,
               tier: tier,
               openrouter_opts: opts[:openrouter_opts] || []
             ) do
          {:ok, generated, router_usage} -> {generated, router_usage}
          {:error, :no_models} -> {[], nil}
        end
      end

    agents =
      Enum.map(perspectives, fn perspective ->
        %AgentSpec{
          name: perspective.role,
          provider: "openrouter",
          model: perspective.model,
          system_prompt: perspective.system_prompt,
          prompt: "{{input_text}}\n\n{{context_block}}",
          tool_profile: if(contract.mode == :deep, do: "research", else: "default"),
          thinking_level: "medium",
          retries: 1,
          timeout_ms: if(contract.mode == :deep, do: :timer.minutes(20), else: :timer.minutes(5))
        }
      end)

    {:ok, %{agents: agents, router_usage: usage}}
  end

  defp run_stage(%StageSpec{type: :route, kind: "cerberus_review"} = stage, context, _contract, config, _opts) do
    panel_size = stage.options["panel_size"] || 4
    always_include = stage.options["always_include"] || ["trace"]
    include_if_code_changed = stage.options["include_if_code_changed"] || ["guard"]
    fallback_panel = stage.options["fallback_panel"] || ["atlas", "proof", "fuse", "craft"]

    selected_names =
      always_include ++
        if(context.diff_summary.code_changed, do: include_if_code_changed, else: [])

    selected_names =
      (selected_names ++ fallback_panel)
      |> Enum.uniq()
      |> Enum.take(panel_size)

    agents =
      Enum.map(selected_names, fn name ->
        Map.fetch!(config.agents, name)
      end)

    {:ok,
     %{
       agents: agents,
       review_route: %{
         panel: selected_names,
         size_bucket: context.diff_summary.size_bucket,
         model_tier: context.diff_summary.model_tier,
         code_changed: context.diff_summary.code_changed
       }
     }}
  end

  defp run_stage(%StageSpec{type: :route, kind: "static_agents"} = stage, _context, _contract, config, _opts) do
    names = stage.options["agents"] || []
    agents = Enum.map(names, &Map.fetch!(config.agents, &1))
    {:ok, %{agents: agents}}
  end

  defp run_stage(%StageSpec{type: :fanout, kind: "agents"} = stage, context, contract, config, opts) do
    agents = Map.get(context, :agents, [])

    results =
      Executor.run(agents, contract, context, config,
        concurrency: stage.concurrency || length(agents),
        agent_config_dir: opts[:agent_config_dir] || Thinktank.CLI.agent_config_dir(),
        runner: opts[:runner],
        openrouter_opts: opts[:openrouter_opts] || []
      )

    Enum.each(results, fn result ->
      output =
        case result.status do
          :ok -> result.output
          :error -> result.output <> if(result.error, do: "\n\nERROR: #{inspect(result.error)}", else: "")
        end

      RunStore.record_agent_result(contract.artifact_dir, result.agent.name, output, %{
        status: result.status,
        model: result.agent.model,
        provider: result.agent.provider,
        usage: result.usage,
        error: result.error
      })
    end)

    {:ok, %{agent_results: results}}
  end

  defp run_stage(%StageSpec{type: :aggregate, kind: "research_synthesis"}, context, contract, _config, opts) do
    successes =
      context.agent_results
      |> Enum.filter(&(&1.status == :ok and String.trim(&1.output) != ""))
      |> Enum.map(fn result -> {result.agent.name, result.output} end)

    if successes == [] do
      {:ok, %{synthesis: nil, workflow_exit_code: 1}}
    else
      tier = input_value(contract.input, :tier, :standard)

      case Synthesis.synthesize(successes, context.input_text,
             tier: tier,
             openrouter_opts: opts[:openrouter_opts] || []
           ) do
        {:ok, text, usage} ->
          {:ok, %{synthesis: %{text: text, usage: usage}, workflow_exit_code: 0}}

        {:error, error} ->
          {:error, {:synthesis_failed, error}}
      end
    end
  end

  defp run_stage(%StageSpec{type: :aggregate, kind: "cerberus_verdict"}, context, _contract, _config, _opts) do
    parsed_reviews =
      Enum.map(context.agent_results, fn result ->
        case result.status do
          :ok ->
            case Verdict.parse(result.output) do
              {:ok, verdict} ->
                %{agent: result.agent.name, status: :ok, verdict: verdict}

              {:error, reason} ->
                %{agent: result.agent.name, status: :parse_error, error: reason}
            end

          :error ->
            %{agent: result.agent.name, status: :runtime_error, error: result.error}
        end
      end)

    final_verdict = aggregate_review_verdict(parsed_reviews)

    {:ok,
     %{
       parsed_reviews: parsed_reviews,
       final_verdict: final_verdict,
       review_summary: render_review_summary(parsed_reviews, final_verdict, context),
       workflow_exit_code: if(final_verdict.verdict == "FAIL", do: 1, else: 0)
     }}
  end

  defp run_stage(%StageSpec{type: :emit, kind: "artifacts"}, context, contract, _config, _opts) do
    case context.result_kind do
      :research ->
        if context[:synthesis] do
          RunStore.write_text_artifact(contract.artifact_dir, "synthesis", "synthesis.md", context.synthesis.text)
          RunStore.write_json_artifact(contract.artifact_dir, "synthesis-usage", "artifacts/synthesis-usage.json", context.synthesis.usage)
        end

      :review ->
        Enum.each(context.parsed_reviews, fn review ->
          if review[:verdict] do
            filename = "artifacts/#{review.agent}-verdict.json"
            RunStore.write_json_artifact(contract.artifact_dir, "#{review.agent}-verdict", filename, review.verdict)
          end
        end)

        RunStore.write_json_artifact(contract.artifact_dir, "verdict", "verdict.json", context.final_verdict)
        RunStore.write_text_artifact(contract.artifact_dir, "review", "review.md", context.review_summary)
    end

    {:ok, %{}}
  end

  defp run_stage(stage, _context, _contract, _config, _opts) do
    {:error, {:unsupported_stage, stage.kind}}
  end

  defp should_run?(%StageSpec{when: true}, _context), do: true
  defp should_run?(%StageSpec{when: false}, _context), do: false
  defp should_run?(%StageSpec{when: nil}, _context), do: true

  defp should_run?(%StageSpec{when: path}, context) when is_binary(path) do
    case resolve_path(context, path) do
      nil -> false
      false -> false
      "" -> false
      [] -> false
      _ -> true
    end
  end

  defp validate_input(%WorkflowSpec{input_schema: %{"required" => required}}, input) when is_list(required) do
    missing =
      Enum.filter(required, fn key ->
        Map.get(input, String.to_atom(key)) in [nil, ""] and Map.get(input, key) in [nil, ""]
      end)

    if missing == [], do: :ok, else: {:error, {:missing_input_keys, missing}}
  end

  defp validate_input(_workflow, _input), do: :ok

  defp select_models(input) do
    models = input_value(input, :models, [])
    tier = input_value(input, :tier, :standard)
    if models != [], do: models, else: Models.models_for_tier(tier)
  end

  defp read_context_files(paths) do
    Enum.flat_map(paths, fn path ->
      with true <- File.regular?(path),
           {:ok, %{size: size}} when size <= 100_000 <- File.stat(path),
           {:ok, content} <- File.read(path) do
        [%{path: path, content: content}]
      else
        _ -> []
      end
    end)
  end

  defp build_context_block([]), do: "No context files provided."

  defp build_context_block(files) do
    blocks =
      Enum.map_join(files, "\n\n", fn file ->
        "## #{Path.basename(file.path)}\n```\n#{file.content}\n```"
      end)

    "Context files:\n\n#{blocks}"
  end

  defp load_review_input(contract) do
    pr_number = input_value(contract.input, :pr)
    repo = input_value(contract.input, :repo)

    if is_integer(pr_number) and is_binary(repo) and repo != "" do
      load_pr_review_input(repo, pr_number, contract.workspace_root)
    else
      load_local_review_input(contract.workspace_root, contract.input)
    end
  end

  defp load_pr_review_input(repo, pr_number, cwd) do
    with {:ok, diff_text} <- system_cmd("gh", ["pr", "diff", Integer.to_string(pr_number), "--repo", repo], cwd),
         {:ok, json} <-
           system_cmd(
             "gh",
             [
               "pr",
               "view",
               Integer.to_string(pr_number),
               "--repo",
               repo,
               "--json",
               "title,author,headRefName,baseRefName,body"
             ],
             cwd
           ),
         {:ok, metadata} <- Jason.decode(json) do
      changed_paths = extract_changed_paths(diff_text)

      {:ok,
       %{
         diff_text: diff_text,
         changed_paths: changed_paths,
         base_ref: metadata["baseRefName"] || "unknown",
         head_ref: metadata["headRefName"] || "unknown",
         metadata: metadata
       }}
    end
  end

  defp load_local_review_input(cwd, input) do
    base_ref = input_value(input, :base, resolve_default_base(cwd))
    head_ref = input_value(input, :head, "HEAD")
    range = "#{base_ref}...#{head_ref}"

    with {:ok, diff_text} <- system_cmd("git", ["diff", "--no-ext-diff", range], cwd),
         {:ok, changed_files} <- system_cmd("git", ["diff", "--name-only", range], cwd),
         {:ok, current_branch} <- optional_cmd("git", ["branch", "--show-current"], cwd) do
      {:ok,
       %{
         diff_text: diff_text,
         changed_paths: changed_files |> String.split("\n", trim: true),
         base_ref: base_ref,
         head_ref: head_ref,
         metadata: %{"current_branch" => String.trim(current_branch)}
       }}
    end
  end

  defp resolve_default_base(cwd) do
    case optional_cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD"], cwd) do
      {:ok, "refs/remotes/" <> ref} ->
        String.trim(ref)

      _ ->
        cond do
          git_ref?(cwd, "origin/main") -> "origin/main"
          git_ref?(cwd, "main") -> "main"
          git_ref?(cwd, "master") -> "master"
          true -> "HEAD~1"
        end
    end
  end

  defp git_ref?(cwd, ref) do
    match?({:ok, _}, optional_cmd("git", ["rev-parse", "--verify", ref], cwd))
  end

  defp build_review_bundle(prepared, diff_summary) do
    changed_files =
      prepared.changed_paths
      |> Enum.map_join("\n", &"* #{&1}")

    diff_text = truncate(prepared.diff_text, 120_000)

    """
    Review context:
    - Base ref: #{prepared.base_ref}
    - Head ref: #{prepared.head_ref}
    - Changed files: #{length(prepared.changed_paths)}
    - Size bucket: #{diff_summary.size_bucket}
    - Model tier: #{diff_summary.model_tier}

    Changed paths:
    #{changed_files}

    Diff:
    ```diff
    #{diff_text}
    ```
    """
  end

  defp extract_changed_paths(diff_text) do
    diff_text
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      if String.starts_with?(line, "diff --git ") do
        case String.split(line, " ") do
          [_diff, _git, _a, "b/" <> path] -> [path]
          _ -> []
        end
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp aggregate_review_verdict(parsed_reviews) do
    valid_reviews =
      parsed_reviews
      |> Enum.filter(&match?(%{status: :ok, verdict: _}, &1))
      |> Enum.map(& &1.verdict)
      |> Enum.filter(&(&1.confidence >= 0.7))

    fail_reviews = Enum.filter(valid_reviews, &(&1.verdict == "FAIL"))
    warn_reviews = Enum.filter(valid_reviews, &(&1.verdict == "WARN"))

    critical_fail? =
      Enum.any?(fail_reviews, fn review ->
        Enum.any?(review.findings, &(&1.severity == "critical"))
      end)

    verdict =
      cond do
        valid_reviews == [] -> "SKIP"
        critical_fail? -> "FAIL"
        length(fail_reviews) >= 2 -> "FAIL"
        warn_reviews != [] -> "WARN"
        length(fail_reviews) == 1 -> "WARN"
        true -> "PASS"
      end

    %{
      verdict: verdict,
      reviewers: Enum.count(valid_reviews),
      failing_reviewers: length(fail_reviews),
      warning_reviewers: length(warn_reviews)
    }
  end

  defp render_review_summary(parsed_reviews, final_verdict, context) do
    reviewer_lines =
      Enum.map_join(parsed_reviews, "\n", fn review ->
        case review do
          %{status: :ok, verdict: verdict} ->
            "- #{review.agent}: #{verdict.verdict} (confidence #{Float.round(verdict.confidence, 2)}) — #{verdict.summary}"

          %{status: :parse_error, error: error} ->
            "- #{review.agent}: SKIP — could not parse reviewer output (#{inspect(error)})"

          %{status: :runtime_error, error: error} ->
            "- #{review.agent}: SKIP — runtime failure #{inspect(error)}"
        end
      end)

    key_findings =
      parsed_reviews
      |> Enum.filter(&match?(%{status: :ok}, &1))
      |> Enum.flat_map(fn review ->
        Enum.take(review.verdict.findings, 2)
      end)
      |> Enum.take(8)
      |> Enum.map_join("\n", fn finding ->
        "- [#{String.upcase(finding.severity)}] #{finding.title} (#{finding.file}:#{finding.line})"
      end)

    """
    # Cerberus Review

    Final verdict: **#{final_verdict.verdict}**

    Routed panel: #{Enum.join(context.review_route.panel, ", ")}
    Size bucket: #{context.diff_summary.size_bucket}
    Model tier: #{context.diff_summary.model_tier}

    ## Reviewers
    #{reviewer_lines}

    ## Key Findings
    #{if(key_findings == "", do: "- None", else: key_findings)}
    """
  end

  defp resolve_path(context, path) do
    Enum.reduce_while(String.split(path, "."), context, fn segment, current ->
      cond do
        is_map(current) and Map.has_key?(current, String.to_atom(segment)) ->
          {:cont, Map.get(current, String.to_atom(segment))}

        is_map(current) and Map.has_key?(current, segment) ->
          {:cont, Map.get(current, segment)}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp stage_snapshot(outputs) do
    outputs
    |> Map.drop([:diff_text, :review_bundle, :context_block, :context_files, :agent_results, :parsed_reviews, :review_summary, :synthesis])
    |> normalize_snapshot()
  end

  defp normalize_snapshot(%AgentSpec{name: name, model: model, provider: provider}) do
    %{name: name, model: model, provider: provider}
  end

  defp normalize_snapshot(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_snapshot(value)} end)
    |> Enum.into(%{})
  end

  defp normalize_snapshot(list) when is_list(list), do: Enum.map(list, &normalize_snapshot/1)
  defp normalize_snapshot(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_snapshot(value), do: value

  defp system_cmd(cmd, args, cwd) do
    case System.cmd(cmd, args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, {cmd, output}}
    end
  rescue
    error ->
      {:error, {cmd, Exception.message(error)}}
  end

  defp optional_cmd(cmd, args, cwd) do
    system_cmd(cmd, args, cwd)
  end

  defp truncate(text, max_bytes) when byte_size(text) <= max_bytes, do: text

  defp truncate(text, max_bytes) do
    binary_part(text, 0, max_bytes) <> "\n... [truncated]"
  end

  defp input_value(input, key, default \\ nil) do
    case Map.fetch(input, key) do
      {:ok, nil} -> Map.get(input, Atom.to_string(key), default)
      {:ok, value} -> value
      :error -> Map.get(input, Atom.to_string(key), default)
    end
  end
end
