defmodule Thinktank.Executor.Agentic do
  @moduledoc """
  Pi subprocess executor for tool-using agent runs.
  """

  alias Thinktank.{AgentSpec, Config, Progress, RunContract, RunStore, Template, TraceLog}
  alias Thinktank.Executor.OutputCollector

  @allowed_tools MapSet.new(~w(read bash edit write grep find ls))
  @default_tools ["bash", "read", "grep", "find", "ls"]
  @default_timeout :timer.minutes(30)

  @type result :: %{
          agent: AgentSpec.t(),
          instance_id: String.t(),
          status: :ok | :error,
          output: String.t(),
          started_at: String.t() | nil,
          completed_at: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          usage: map() | nil,
          error: map() | nil
        }

  @spec run([AgentSpec.t()], RunContract.t(), map(), Config.t(), keyword()) :: [result()]
  def run(agents, contract, context, config, opts \\ [])

  def run([], %RunContract{}, _context, %Config{}, _opts), do: []

  def run(agents, %RunContract{} = contract, context, %Config{} = config, opts) do
    runner = Keyword.get(opts, :runner) || default_runner()

    progress_phase =
      Keyword.get(opts, :progress_phase, Progress.phase_for_event("agents_started"))

    indexed_agents = Enum.with_index(agents, 1)

    Enum.each(indexed_agents, fn {agent, index} ->
      instance_id = agent_instance_id(agent, index)

      RunStore.init_agent_scratchpad(contract.artifact_dir, agent.name, instance_id, %{
        bench: contract.bench_id,
        model: agent.model,
        provider: agent.provider
      })
    end)

    timeout =
      Enum.max(
        Enum.map(agents, fn agent ->
          attempts = max(agent.retries + 1, 1)
          agent.timeout_ms * attempts + 250 * (attempts - 1)
        end),
        fn -> @default_timeout end
      )

    concurrency =
      normalize_concurrency(Keyword.get(opts, :concurrency, length(agents)), length(agents))

    indexed_agents
    |> Task.async_stream(
      fn {agent, index} ->
        run_agent(agent, index, contract, context, config, runner, progress_phase, opts)
      end,
      max_concurrency: concurrency,
      timeout: timeout + 5_000,
      ordered: true,
      on_timeout: :kill_task
    )
    |> Enum.zip(indexed_agents)
    |> Enum.map(fn
      {{:ok, result}, _indexed_agent} ->
        result

      {{:exit, reason}, {agent, index}} when reason in [:timeout, {:timeout, nil}] ->
        instance_id = agent_instance_id(agent, index)
        usage = session_usage(agent_home_path(contract, instance_id), agent.model)

        RunStore.append_agent_note(
          contract.artifact_dir,
          instance_id,
          "agent task timed out before the subprocess returned"
        )

        TraceLog.record_event(contract.artifact_dir, "agent_finished", %{
          "bench" => contract.bench_id,
          "agent_name" => agent.name,
          "instance_id" => instance_id,
          "provider" => agent.provider,
          "model" => agent.model,
          "status" => "error",
          "attempts" => 0,
          "error" => %{category: :timeout}
        })

        Progress.emit(opts, "agent_finished", %{
          phase: progress_phase,
          output_dir: contract.artifact_dir,
          agent_name: agent.name,
          instance_id: instance_id,
          status: "error"
        })

        untimed_result(agent, instance_id, :error, "", %{category: :timeout}, usage)

      {{:exit, reason}, {agent, index}} ->
        instance_id = agent_instance_id(agent, index)
        error = %{category: :crash, message: inspect(reason)}
        usage = session_usage(agent_home_path(contract, instance_id), agent.model)

        RunStore.append_agent_note(
          contract.artifact_dir,
          instance_id,
          "agent task crashed: #{inspect(reason)}"
        )

        TraceLog.record_event(contract.artifact_dir, "agent_finished", %{
          "bench" => contract.bench_id,
          "agent_name" => agent.name,
          "instance_id" => instance_id,
          "provider" => agent.provider,
          "model" => agent.model,
          "status" => "error",
          "attempts" => 0,
          "error" => error
        })

        Progress.emit(opts, "agent_finished", %{
          phase: progress_phase,
          output_dir: contract.artifact_dir,
          agent_name: agent.name,
          instance_id: instance_id,
          status: "error"
        })

        untimed_result(
          agent,
          instance_id,
          :error,
          "",
          error,
          usage
        )
    end)
  end

  defp run_agent(agent, index, contract, context, config, runner, progress_phase, opts) do
    instance_id = agent_instance_id(agent, index)
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    started_mono = System.monotonic_time(:millisecond)
    agent_home = agent_home_path(contract, instance_id)
    tools = tool_list(agent)

    trace_context = %{
      "bench" => contract.bench_id,
      "output_dir" => contract.artifact_dir,
      "agent_name" => agent.name,
      "instance_id" => instance_id,
      "provider" => agent.provider,
      "model" => agent.model,
      "runner" => runner_name(opts[:runner]),
      "timeout_ms" => agent.timeout_ms,
      "tool_names" => tools
    }

    TraceLog.record_event(contract.artifact_dir, "agent_started", trace_context)
    RunStore.append_agent_note(contract.artifact_dir, instance_id, "agent started")

    Progress.emit(opts, "agent_started", %{
      phase: progress_phase,
      output_dir: contract.artifact_dir,
      agent_name: agent.name,
      instance_id: instance_id,
      status: "running"
    })

    try do
      rendered_prompt =
        agent.task_prompt
        |> Template.render(
          contract.input
          |> Map.merge(context)
          |> Map.merge(stringify_keys(agent.metadata))
          |> Map.merge(%{
            "agent_name" => agent.name,
            "bench_id" => contract.bench_id,
            "workspace_root" => contract.workspace_root
          })
          |> stringify_keys()
        )

      prompt = "#{agent.system_prompt}\n\n#{rendered_prompt}"
      prompt_file = write_prompt_file(contract, instance_id, prompt)
      provider = config.providers[agent.provider]
      agent_home = build_agent_home(contract, instance_id, opts[:agent_config_dir])
      {cmd, args} = build_command(agent, prompt_file, tools, provider)

      cmd_opts =
        build_cmd_opts(agent, agent_home, instance_id, contract, provider)

      TraceLog.record_event(contract.artifact_dir, "prompt_written", %{
        "bench" => contract.bench_id,
        "agent_name" => agent.name,
        "instance_id" => instance_id,
        "prompt_file" => relative_artifact_path(prompt_file, contract.artifact_dir),
        "prompt_bytes" => byte_size(prompt),
        "prompt_sha256" => sha256_hex(prompt)
      })

      RunStore.append_agent_note(
        contract.artifact_dir,
        instance_id,
        "prompt rendered to #{relative_artifact_path(prompt_file, contract.artifact_dir)}"
      )

      max_attempts = max(agent.retries + 1, 1)

      case attempt(max_attempts, contract.artifact_dir, trace_context, fn attempt_number ->
             run_once(
               runner,
               cmd,
               args,
               cmd_opts,
               Map.merge(trace_context, %{
                 "attempt" => attempt_number,
                 "max_attempts" => max_attempts
               })
             )
           end) do
        {:ok, output, attempts_run} ->
          usage = session_usage(agent_home, agent.model)

          result =
            timed_result(agent, instance_id, :ok, output, started_at, started_mono, nil, usage)

          RunStore.append_agent_note(
            contract.artifact_dir,
            instance_id,
            "agent finished successfully after #{attempts_run} attempt(s)"
          )

          TraceLog.record_event(contract.artifact_dir, "agent_finished", %{
            "bench" => contract.bench_id,
            "agent_name" => agent.name,
            "instance_id" => instance_id,
            "provider" => agent.provider,
            "model" => agent.model,
            "status" => "ok",
            "attempts" => attempts_run,
            "started_at" => started_at,
            "completed_at" => result.completed_at,
            "duration_ms" => result.duration_ms,
            "output_bytes" => byte_size(output)
          })

          Progress.emit(opts, "agent_finished", %{
            phase: progress_phase,
            output_dir: contract.artifact_dir,
            agent_name: agent.name,
            instance_id: instance_id,
            status: "ok"
          })

          result

        {:error, %{output: output} = error, attempts_run} ->
          usage = session_usage(agent_home, agent.model)

          result =
            timed_result(
              agent,
              instance_id,
              :error,
              output,
              started_at,
              started_mono,
              Map.delete(error, :output),
              usage
            )

          RunStore.append_agent_note(
            contract.artifact_dir,
            instance_id,
            "agent finished with #{error[:category]} after #{attempts_run} attempt(s)"
          )

          TraceLog.record_event(contract.artifact_dir, "agent_finished", %{
            "bench" => contract.bench_id,
            "agent_name" => agent.name,
            "instance_id" => instance_id,
            "provider" => agent.provider,
            "model" => agent.model,
            "status" => "error",
            "attempts" => attempts_run,
            "started_at" => started_at,
            "completed_at" => result.completed_at,
            "duration_ms" => result.duration_ms,
            "output_bytes" => byte_size(output),
            "error" => Map.delete(error, :output)
          })

          Progress.emit(opts, "agent_finished", %{
            phase: progress_phase,
            output_dir: contract.artifact_dir,
            agent_name: agent.name,
            instance_id: instance_id,
            status: "error"
          })

          result
      end
    rescue
      error ->
        usage = session_usage(agent_home, agent.model)

        result =
          timed_result(
            agent,
            instance_id,
            :error,
            "",
            started_at,
            started_mono,
            %{category: :crash, message: Exception.message(error)},
            usage
          )

        RunStore.append_agent_note(
          contract.artifact_dir,
          instance_id,
          "agent crashed: #{Exception.message(error)}"
        )

        TraceLog.record_event(contract.artifact_dir, "agent_finished", %{
          "bench" => contract.bench_id,
          "agent_name" => agent.name,
          "instance_id" => instance_id,
          "provider" => agent.provider,
          "model" => agent.model,
          "status" => "error",
          "attempts" => 0,
          "started_at" => started_at,
          "completed_at" => result.completed_at,
          "duration_ms" => result.duration_ms,
          "error" => %{category: :crash, message: Exception.message(error)}
        })

        Progress.emit(opts, "agent_finished", %{
          phase: progress_phase,
          output_dir: contract.artifact_dir,
          agent_name: agent.name,
          instance_id: instance_id,
          status: "error"
        })

        result
    end
  end

  defp run_once(runner, cmd, args, cmd_opts, trace_context) do
    output_dir = trace_context["output_dir"] || cmd_opts[:cd]
    started_mono = System.monotonic_time(:millisecond)

    TraceLog.record_event(output_dir, "subprocess_started", %{
      "bench" => trace_context["bench"],
      "agent_name" => trace_context["agent_name"],
      "instance_id" => trace_context["instance_id"],
      "attempt" => trace_context["attempt"],
      "max_attempts" => trace_context["max_attempts"],
      "command" => cmd,
      "args" => args,
      "cwd" => cmd_opts[:cd],
      "timeout_ms" => cmd_opts[:timeout],
      "env_keys" => cmd_opts |> Keyword.get(:env, []) |> Enum.map(&elem(&1, 0))
    })

    case runner.(cmd, args, cmd_opts) do
      {output, 0} ->
        TraceLog.record_event(output_dir, "subprocess_finished", %{
          "bench" => trace_context["bench"],
          "agent_name" => trace_context["agent_name"],
          "instance_id" => trace_context["instance_id"],
          "attempt" => trace_context["attempt"],
          "status" => "ok",
          "exit_code" => 0,
          "duration_ms" => elapsed_ms(started_mono),
          "output_bytes" => byte_size(output)
        })

        {:ok, output}

      {output, :timeout} ->
        TraceLog.record_event(output_dir, "subprocess_finished", %{
          "bench" => trace_context["bench"],
          "agent_name" => trace_context["agent_name"],
          "instance_id" => trace_context["instance_id"],
          "attempt" => trace_context["attempt"],
          "status" => "timeout",
          "exit_code" => nil,
          "duration_ms" => elapsed_ms(started_mono),
          "output_bytes" => byte_size(output)
        })

        {:error, %{category: :timeout, output: output}}

      {output, exit_code} ->
        TraceLog.record_event(output_dir, "subprocess_finished", %{
          "bench" => trace_context["bench"],
          "agent_name" => trace_context["agent_name"],
          "instance_id" => trace_context["instance_id"],
          "attempt" => trace_context["attempt"],
          "status" => "error",
          "exit_code" => exit_code,
          "duration_ms" => elapsed_ms(started_mono),
          "output_bytes" => byte_size(output)
        })

        {:error, %{category: :crash, exit_code: exit_code, output: output}}
    end
  end

  defp timed_result(agent, instance_id, status, output, started_at, started_mono, error, usage) do
    runtime = %{
      started_at: started_at,
      completed_at: completed_at_iso8601(),
      duration_ms: elapsed_ms(started_mono),
      error: error,
      usage: usage
    }

    build_result(
      agent,
      instance_id,
      status,
      output,
      runtime
    )
  end

  defp completed_at_iso8601 do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp elapsed_ms(started_mono) do
    System.monotonic_time(:millisecond) - started_mono
  end

  defp untimed_result(agent, instance_id, status, output, error, usage) do
    build_result(agent, instance_id, status, output, %{
      started_at: nil,
      completed_at: nil,
      duration_ms: nil,
      error: error,
      usage: usage
    })
  end

  defp build_result(agent, instance_id, status, output, runtime) do
    %{
      agent: agent,
      instance_id: instance_id,
      status: status,
      output: output,
      started_at: runtime.started_at,
      completed_at: runtime.completed_at,
      duration_ms: runtime.duration_ms,
      usage: runtime.usage,
      error: runtime.error
    }
  end

  defp attempt(max_attempts, output_dir, trace_context, fun) when max_attempts > 0 do
    do_attempt(1, max_attempts, output_dir, trace_context, fun)
  end

  defp do_attempt(current, max_attempts, output_dir, trace_context, fun) do
    TraceLog.record_event(output_dir, "attempt_started", %{
      "bench" => trace_context["bench"],
      "agent_name" => trace_context["agent_name"],
      "instance_id" => trace_context["instance_id"],
      "attempt" => current,
      "max_attempts" => max_attempts
    })

    RunStore.append_agent_note(
      output_dir,
      trace_context["instance_id"],
      "attempt #{current}/#{max_attempts} started"
    )

    started_mono = System.monotonic_time(:millisecond)

    case fun.(current) do
      {:ok, output} ->
        TraceLog.record_event(output_dir, "attempt_finished", %{
          "bench" => trace_context["bench"],
          "agent_name" => trace_context["agent_name"],
          "instance_id" => trace_context["instance_id"],
          "attempt" => current,
          "max_attempts" => max_attempts,
          "status" => "ok",
          "duration_ms" => elapsed_ms(started_mono),
          "output_bytes" => byte_size(output)
        })

        RunStore.append_agent_note(
          output_dir,
          trace_context["instance_id"],
          "attempt #{current}/#{max_attempts} succeeded"
        )

        {:ok, output, current}

      {:error, error} ->
        trimmed_error = Map.delete(error, :output)

        TraceLog.record_event(output_dir, "attempt_finished", %{
          "bench" => trace_context["bench"],
          "agent_name" => trace_context["agent_name"],
          "instance_id" => trace_context["instance_id"],
          "attempt" => current,
          "max_attempts" => max_attempts,
          "status" => "error",
          "duration_ms" => elapsed_ms(started_mono),
          "output_bytes" => byte_size(Map.get(error, :output, "")),
          "error" => trimmed_error
        })

        RunStore.append_agent_note(
          output_dir,
          trace_context["instance_id"],
          "attempt #{current}/#{max_attempts} failed with #{trimmed_error[:category]}"
        )

        if current < max_attempts and retryable?(error) do
          next_attempt = current + 1

          TraceLog.record_event(output_dir, "attempt_retry_scheduled", %{
            "bench" => trace_context["bench"],
            "agent_name" => trace_context["agent_name"],
            "instance_id" => trace_context["instance_id"],
            "attempt" => current,
            "next_attempt" => next_attempt,
            "delay_ms" => 250,
            "error" => trimmed_error
          })

          RunStore.append_agent_note(
            output_dir,
            trace_context["instance_id"],
            "retrying after attempt #{current}; next attempt #{next_attempt} in 250 ms"
          )

          Process.sleep(250)
          do_attempt(next_attempt, max_attempts, output_dir, trace_context, fun)
        else
          {:error, error, current}
        end
    end
  end

  defp retryable?(%{category: :timeout}), do: false
  defp retryable?(%{category: :crash}), do: true
  defp retryable?(_), do: false

  defp build_command(agent, prompt_file, tools, provider) do
    {"sh",
     [
       "-c",
       "exec < /dev/null; exec \"$@\" 2>&1",
       "sh",
       "pi",
       "--no-skills",
       "--provider",
       to_string(provider.adapter),
       "--model",
       agent.model,
       "--thinking",
       agent.thinking_level,
       "--tools",
       Enum.join(tools, ","),
       "-p",
       "@#{prompt_file}"
     ]}
  end

  defp build_cmd_opts(agent, agent_home, instance_id, contract, provider) do
    provider_env = provider_env(provider)

    [
      stderr_to_stdout: true,
      timeout: agent.timeout_ms,
      output_sink: &RunStore.append_agent_output(contract.artifact_dir, instance_id, &1),
      env:
        [
          {"PI_CODING_AGENT_DIR", agent_home}
        ] ++
          provider_env,
      cd: contract.workspace_root
    ]
  end

  defp provider_env(%{adapter: :openrouter} = provider) do
    fallback_env = provider.defaults["fallback_env"]

    key =
      non_empty_env(provider.credential_env) ||
        if(is_binary(fallback_env) and fallback_env != "", do: non_empty_env(fallback_env))

    if is_binary(key) and key != "" do
      [{"OPENROUTER_API_KEY", key}]
    else
      []
    end
  end

  defp provider_env(_), do: []

  defp non_empty_env(name) when is_binary(name) and name != "" do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp non_empty_env(_), do: nil

  defp tool_list(%AgentSpec{tools: tools}) when is_list(tools) and tools != [] do
    sanitize_tools(tools)
  end

  defp tool_list(_), do: @default_tools

  defp sanitize_tools(tools) do
    tools
    |> Enum.filter(&MapSet.member?(@allowed_tools, &1))
    |> Enum.uniq()
  end

  defp write_prompt_file(contract, instance_id, prompt) do
    dir = Path.join(contract.artifact_dir, "prompts")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{instance_id}.md")
    File.write!(path, prompt)
    path
  end

  defp agent_home_path(contract, instance_id) do
    Path.join([contract.artifact_dir, "pi-home", instance_id])
  end

  defp build_agent_home(contract, instance_id, nil) do
    dir = agent_home_path(contract, instance_id)
    File.mkdir_p!(dir)
    dir
  end

  defp build_agent_home(contract, instance_id, base_dir) do
    dir = agent_home_path(contract, instance_id)

    unless File.exists?(dir) do
      validate_agent_config_dir!(base_dir)
      File.mkdir_p!(Path.dirname(dir))
      File.cp_r!(base_dir, dir)
    end

    dir
  end

  defp agent_instance_id(%AgentSpec{name: name}, index) do
    suffix =
      :crypto.hash(:sha256, name)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 8)

    "#{safe_name(name)}-#{suffix}-#{index}"
  end

  defp safe_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp validate_agent_config_dir!(base_dir) do
    case File.lstat(base_dir) do
      {:ok, %File.Stat{type: :symlink}} ->
        raise ArgumentError, "agent_config must not be a symlink: #{base_dir}"

      _ ->
        :ok
    end

    walk_reject_symlinks!(base_dir)
  end

  defp walk_reject_symlinks!(dir) do
    dir
    |> File.ls!()
    |> Enum.each(fn entry ->
      path = Path.join(dir, entry)

      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} ->
          raise ArgumentError, "agent_config must not contain symlinks: #{path}"

        {:ok, %File.Stat{type: :directory}} ->
          walk_reject_symlinks!(path)

        {:ok, _} ->
          :ok

        {:error, reason} ->
          raise ArgumentError,
                "agent_config validation failed at #{path}: #{:file.format_error(reason)}"
      end
    end)
  end

  defp normalize_concurrency(value, agent_count) when is_integer(value) and value > 0 do
    min(value, max(agent_count, 1))
  end

  defp normalize_concurrency(_, agent_count), do: max(agent_count, 1)

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end

  defp runner_name(nil) do
    if disable_muontrap?() or not muontrap_available?(), do: "system_cmd", else: "muontrap_cmd"
  end

  defp runner_name(_), do: "custom"

  defp session_usage(agent_home, model) do
    agent_home
    |> session_files()
    |> Enum.flat_map(&assistant_usages_from_session/1)
    |> aggregate_session_usage(model)
  end

  defp session_files(agent_home) do
    Path.wildcard(Path.join([agent_home, "sessions", "**", "*.jsonl"]))
  end

  defp assistant_usages_from_session(path) do
    path
    |> File.stream!(:line, [])
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "message", "message" => %{"role" => "assistant", "usage" => usage}}} ->
          [usage]

        _ ->
          []
      end
    end)
  rescue
    _ -> []
  end

  defp aggregate_session_usage([], _model), do: nil

  defp aggregate_session_usage(usages, model) do
    aggregate =
      Enum.reduce(
        usages,
        %{"input" => 0, "output" => 0, "cacheRead" => 0, "cacheWrite" => 0},
        fn usage, acc ->
          %{
            "input" => acc["input"] + usage_value(usage, "input"),
            "output" => acc["output"] + usage_value(usage, "output"),
            "cacheRead" => acc["cacheRead"] + usage_value(usage, "cacheRead"),
            "cacheWrite" => acc["cacheWrite"] + usage_value(usage, "cacheWrite")
          }
        end
      )

    total =
      aggregate["input"] +
        aggregate["output"] +
        aggregate["cacheRead"] +
        aggregate["cacheWrite"]

    Thinktank.Pricing.normalize_usage(model, Map.put(aggregate, "totalTokens", total))
  end

  defp usage_value(usage, key) do
    case Map.get(usage, key) do
      value when is_integer(value) and value >= 0 -> value
      value when is_float(value) and value >= 0 -> trunc(value)
      _ -> 0
    end
  end

  defp relative_artifact_path(path, output_dir) do
    Path.relative_to(path, output_dir)
  end

  defp sha256_hex(contents) do
    :crypto.hash(:sha256, contents)
    |> Base.encode16(case: :lower)
  end

  @doc false
  def default_runner do
    if disable_muontrap?() or not muontrap_available?(), do: &system_cmd/3, else: &muontrap_cmd/3
  end

  @doc false
  def muontrap_available? do
    path = MuonTrap.muontrap_path()
    File.exists?(path)
  rescue
    _ -> false
  end

  defp disable_muontrap? do
    case System.get_env("THINKTANK_DISABLE_MUONTRAP") do
      value when value in ["1", "true", "TRUE"] -> true
      _ -> false
    end
  end

  @doc false
  def system_cmd(cmd, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd)
    collector = %OutputCollector{sink: Keyword.get(opts, :output_sink)}

    cmd_opts =
      [stderr_to_stdout: true, env: env, into: collector] ++ if(cd, do: [cd: cd], else: [])

    task =
      Task.async(fn ->
        try do
          {:ok, System.cmd(cmd, args, cmd_opts)}
        rescue
          error -> {:error, Exception.message(error)}
        catch
          :exit, reason -> {:error, inspect(reason)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, {output, exit_code}}} -> {output, exit_code}
      {:ok, {:error, message}} -> {message, 1}
      nil -> {"", :timeout}
    end
  end

  @doc false
  def muontrap_cmd(cmd, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd)
    collector = %OutputCollector{sink: Keyword.get(opts, :output_sink)}

    cmd_opts =
      [stderr_to_stdout: true, timeout: timeout, env: env, into: collector] ++
        if(cd, do: [cd: cd], else: [])

    MuonTrap.cmd(cmd, args, cmd_opts)
  end
end
