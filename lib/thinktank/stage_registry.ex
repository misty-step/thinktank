defmodule Thinktank.StageRegistry do
  @moduledoc """
  Registry and implementations for the built-in constrained stage kinds.
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
    Synthesis
  }

  alias Thinktank.Review.{Diff, Verdict}

  @handlers %{
    prepare: %{
      "research_input" => :research_input,
      "review_diff" => :review_diff
    },
    route: %{
      "research_router" => :research_router,
      "cerberus_review" => :cerberus_review,
      "static_agents" => :static_agents
    },
    fanout: %{
      "agents" => :fanout_agents
    },
    aggregate: %{
      "research_synthesis" => :research_synthesis,
      "cerberus_verdict" => :cerberus_verdict
    },
    emit: %{
      "artifacts" => :emit_artifacts
    }
  }

  @max_context_files 40
  @max_context_file_bytes 100_000

  @spec supported_kinds(atom()) :: [String.t()]
  def supported_kinds(type) when is_atom(type) do
    @handlers
    |> Map.get(type, %{})
    |> Map.keys()
    |> Enum.sort()
  end

  @spec run(StageSpec.t(), map(), RunContract.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run(%StageSpec{} = stage, context, %RunContract{} = contract, %Config{} = config, opts) do
    case get_in(@handlers, [stage.type, stage.kind]) do
      nil -> {:error, {:unsupported_stage, stage.kind}}
      handler -> apply(__MODULE__, handler, [stage, context, contract, config, opts])
    end
  end

  def research_input(_stage, _context, contract, _config, _opts) do
    input_text = input_value(contract.input, :input_text)
    paths = input_value(contract.input, :paths, [])
    context_files = read_context_files(paths)

    {:ok,
     %{
       input_text: input_text,
       paths: paths,
       context_files: context_files,
       context_block: build_context_block(context_files),
       no_synthesis: input_value(contract.input, :no_synthesis, false),
       should_synthesize: not input_value(contract.input, :no_synthesis, false),
       review_bundle: "",
       result_kind: :research
     }}
  end

  def review_diff(_stage, _context, contract, _config, _opts) do
    with {:ok, prepared} <- load_review_input(contract) do
      diff_path = persist_diff_file(contract.artifact_dir, prepared.diff_text)
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
         changed_paths_block: build_changed_paths_block(prepared.changed_paths),
         base_ref: prepared.base_ref,
         head_ref: prepared.head_ref,
         diff_path: diff_path,
         review_metadata: prepared.metadata,
         diff_summary: diff_summary,
         review_bundle:
           build_review_bundle(prepared, diff_summary, contract.workspace_root, diff_path),
         result_kind: :review
       }}
    end
  end

  def research_router(stage, context, contract, _config, opts) do
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

  def cerberus_review(stage, context, _contract, config, _opts) do
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

    with {:ok, agents} <- fetch_agents(config.agents, selected_names) do
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
  end

  def static_agents(stage, _context, _contract, config, _opts) do
    names = stage.options["agents"] || []

    with {:ok, agents} <- fetch_agents(config.agents, names) do
      {:ok, %{agents: agents}}
    end
  end

  def fanout_agents(stage, context, contract, config, opts) do
    agents = Map.get(context, :agents, [])

    results =
      Executor.run(agents, contract, context, config,
        concurrency: stage.concurrency || length(agents),
        agent_config_dir: opts[:agent_config_dir],
        runner: opts[:runner],
        openrouter_opts: opts[:openrouter_opts] || []
      )

    Enum.each(results, fn result ->
      output =
        case result.status do
          :ok ->
            result.output

          :error ->
            result.output <> if(result.error, do: "\n\nERROR: #{inspect(result.error)}", else: "")
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

  def research_synthesis(_stage, context, contract, _config, opts) do
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

  def cerberus_verdict(_stage, context, _contract, _config, _opts) do
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

  def emit_artifacts(_stage, context, contract, _config, _opts) do
    case context.result_kind do
      :research ->
        if context[:synthesis] do
          RunStore.write_text_artifact(
            contract.artifact_dir,
            "synthesis",
            "synthesis.md",
            context.synthesis.text
          )

          RunStore.write_json_artifact(
            contract.artifact_dir,
            "synthesis-usage",
            "artifacts/synthesis-usage.json",
            context.synthesis.usage
          )
        end

      :review ->
        Enum.each(context[:parsed_reviews] || [], fn review ->
          if review[:verdict] do
            filename = "artifacts/#{artifact_name(review.agent)}-verdict.json"

            RunStore.write_json_artifact(
              contract.artifact_dir,
              "#{review.agent}-verdict",
              filename,
              review.verdict
            )
          end
        end)

        if context[:final_verdict] do
          RunStore.write_json_artifact(
            contract.artifact_dir,
            "verdict",
            "verdict.json",
            context.final_verdict
          )
        end

        if context[:review_summary] do
          RunStore.write_text_artifact(
            contract.artifact_dir,
            "review",
            "review.md",
            context.review_summary
          )
        end
    end

    {:ok, %{}}
  end

  @doc false
  def aggregate_review_verdict(parsed_reviews) do
    valid_reviews =
      parsed_reviews
      |> Enum.filter(&match?(%{status: :ok, verdict: _}, &1))
      |> Enum.map(& &1.verdict)
      |> Enum.filter(&(&1.confidence >= 0.7))

    invalid_review_count = Enum.count(parsed_reviews, &(&1.status != :ok))

    fail_reviews = Enum.filter(valid_reviews, &(&1.verdict == "FAIL"))
    warn_reviews = Enum.filter(valid_reviews, &(&1.verdict == "WARN"))

    critical_fail? =
      Enum.any?(fail_reviews, fn review ->
        Enum.any?(review.findings, &(&1.severity == "critical"))
      end)

    verdict =
      cond do
        valid_reviews == [] and parsed_reviews == [] -> "SKIP"
        valid_reviews == [] -> "FAIL"
        critical_fail? -> "FAIL"
        length(fail_reviews) >= 2 -> "FAIL"
        warn_reviews != [] -> "WARN"
        length(fail_reviews) == 1 -> "WARN"
        true -> "PASS"
      end

    %{
      verdict: verdict,
      reviewers: Enum.count(valid_reviews),
      failing_reviewers: length(fail_reviews) + invalid_review_count,
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
        line = if is_integer(finding.line), do: Integer.to_string(finding.line), else: "?"
        "- [#{String.upcase(finding.severity)}] #{finding.title} (#{finding.file}:#{line})"
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

  defp select_models(input) do
    models = input_value(input, :models, [])
    tier = input_value(input, :tier, :standard)
    if models != [], do: models, else: Models.models_for_tier(tier)
  end

  defp read_context_files(paths) do
    paths
    |> Enum.flat_map(&expand_context_paths/1)
    |> Enum.uniq()
    |> Enum.take(@max_context_files)
    |> Enum.flat_map(&read_context_file/1)
  end

  defp expand_context_paths(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: false)
        |> Enum.filter(&File.regular?/1)
        |> Enum.take(@max_context_files)

      true ->
        []
    end
  end

  defp read_context_file(path) do
    with {:ok, %{size: size}} when size <= @max_context_file_bytes <- File.stat(path),
         {:ok, content} <- File.read(path) do
      [%{path: path, content: content}]
    else
      _ -> []
    end
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

    case {is_integer(pr_number), is_binary(repo) and repo != ""} do
      {true, true} ->
        load_pr_review_input(repo, pr_number, contract.workspace_root)

      {true, false} ->
        {:error, {:pr_review_requires_repo, pr_number}}

      {false, true} ->
        {:error, {:pr_review_requires_number, repo}}

      {false, false} ->
        load_local_review_input(contract.workspace_root, contract.input)
    end
  end

  defp load_pr_review_input(repo, pr_number, cwd) do
    with {:ok, diff_text} <-
           system_cmd("gh", ["pr", "diff", Integer.to_string(pr_number), "--repo", repo], cwd),
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
               "title,author,headRefName,headRefOid,baseRefName,body"
             ],
             cwd
           ),
         {:ok, metadata} <- Jason.decode(json),
         :ok <- ensure_local_pr_workspace(cwd, repo, metadata) do
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

    with :ok <- validate_git_ref(base_ref),
         :ok <- validate_git_ref(head_ref),
         {:ok, diff_text} <- system_cmd("git", ["diff", "--no-ext-diff", range], cwd),
         {:ok, changed_files} <- system_cmd("git", ["diff", "--name-only", range], cwd) do
      current_branch =
        case optional_cmd("git", ["branch", "--show-current"], cwd) do
          {:ok, branch} ->
            branch
            |> String.trim()
            |> case do
              "" -> nil
              trimmed -> trimmed
            end

          _ ->
            nil
        end

      {:ok,
       %{
         diff_text: diff_text,
         changed_paths: changed_files |> String.split("\n", trim: true),
         base_ref: base_ref,
         head_ref: head_ref,
         metadata: %{"current_branch" => current_branch}
       }}
    end
  end

  defp validate_git_ref(ref) when is_binary(ref) and ref != "" do
    if String.starts_with?(ref, "-") do
      {:error, {:invalid_git_ref, ref}}
    else
      :ok
    end
  end

  defp validate_git_ref(ref), do: {:error, {:invalid_git_ref, ref}}

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

  defp build_review_bundle(prepared, diff_summary, workspace_root, diff_path) do
    changed_files = build_changed_paths_block(prepared.changed_paths)
    title = get_in(prepared.metadata, ["title"]) || "n/a"
    pr_body = prepared.metadata |> Map.get("body", "") |> truncate(2_000)

    """
    Review target:
    - Workspace root: #{workspace_root}
    - Base ref: #{prepared.base_ref}
    - Head ref: #{prepared.head_ref}
    - Changed files: #{length(prepared.changed_paths)}
    - Size bucket: #{diff_summary.size_bucket}
    - Model tier: #{diff_summary.model_tier}
    - PR title: #{title}

    Changed paths:
    #{changed_files}

    PR body:
    #{if(String.trim(pr_body) == "", do: "(empty)", else: pr_body)}

    Inspect the checked-out workspace directly with your tools before making claims.
    In PR mode, the local workspace is expected to already be checked out at the PR head commit.
    Diff file:
    - #{diff_path}

    Useful tools and targets:
    - Read the diff file above for exact changed lines
    - Use `read` on changed files first, then on nearby supporting files under #{workspace_root}
    - Use `grep` or `find` for targeted follow-up on symbols referenced by changed paths
    - Use `ls` to orient inside the workspace when needed

    Review scope:
    - Keep the investigation diff-first and local to touched code unless the change clearly reaches farther
    - Treat v1 routing heuristics such as small<=50, medium<=200, large<=500, xlarge>500 as deliberate defaults
    - The aggregate verdict treats malformed or crashed reviewer outputs as invalid, so return valid JSON exactly once

    Do not rely only on this summary. Use the repo, diff, and nearby code to verify each finding.
    """
  end

  defp build_changed_paths_block(paths) do
    paths
    |> Enum.take(200)
    |> Enum.map_join("\n", &"* #{&1}")
    |> case do
      "" -> "(none)"
      block when length(paths) > 200 -> block <> "\n* ... [truncated]"
      block -> block
    end
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

  defp ensure_local_pr_workspace(cwd, repo, metadata) do
    head_ref = metadata["headRefName"] || "unknown"
    head_sha = metadata["headRefOid"] || ""

    case system_cmd("git", ["rev-parse", "--is-inside-work-tree"], cwd) do
      {:ok, _} ->
        case optional_cmd("git", ["config", "--get", "remote.origin.url"], cwd) do
          {:ok, remote} ->
            remote = String.trim(remote)

            cond do
              not repo_matches_origin?(remote, repo) ->
                {:error, {:pr_review_repo_mismatch, repo, remote}}

              true ->
                case system_cmd("git", ["rev-parse", "HEAD"], cwd) do
                  {:ok, local_head} ->
                    if String.trim(local_head) == head_sha do
                      :ok
                    else
                      {:error, {:pr_review_requires_checkout, repo, head_ref, head_sha}}
                    end

                  {:error, _reason} ->
                    {:error, {:pr_review_requires_git_workspace, repo}}
                end
            end

          {:error, _reason} ->
            {:error, {:pr_review_requires_git_workspace, repo}}
        end

      {:error, _reason} ->
        {:error, {:pr_review_requires_git_workspace, repo}}
    end
  end

  defp repo_matches_origin?(remote, repo) do
    remote == repo or
      String.ends_with?(remote, "/#{repo}.git") or
      String.ends_with?(remote, "/#{repo}") or
      String.ends_with?(remote, ":#{repo}.git") or
      String.ends_with?(remote, ":#{repo}")
  end

  defp artifact_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp fetch_agents(agents_by_name, names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      case Map.fetch(agents_by_name, name) do
        {:ok, agent} -> {:cont, {:ok, [agent | acc]}}
        :error -> {:halt, {:error, {:unknown_agent, name}}}
      end
    end)
    |> case do
      {:ok, agents} -> {:ok, Enum.reverse(agents)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_diff_file(output_dir, diff_text) do
    path = Path.join(output_dir, "inputs/review.diff")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, diff_text)
    path
  end

  defp system_cmd(cmd, args, cwd) do
    case System.cmd(cmd, args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, {cmd, output}}
    end
  rescue
    error ->
      {:error, {cmd, Exception.message(error)}}
  end

  defp optional_cmd(cmd, args, cwd), do: system_cmd(cmd, args, cwd)

  defp truncate(text, max_bytes) when byte_size(text) <= max_bytes, do: text
  defp truncate(text, max_bytes), do: binary_part(text, 0, max_bytes) <> "\n... [truncated]"

  defp input_value(input, key, default \\ nil) do
    case Map.fetch(input, key) do
      {:ok, nil} -> Map.get(input, Atom.to_string(key), default)
      {:ok, value} -> value
      :error -> Map.get(input, Atom.to_string(key), default)
    end
  end
end
