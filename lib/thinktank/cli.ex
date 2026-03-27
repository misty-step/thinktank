defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for ThinkTank workflows.
  """

  alias Thinktank.{Config, Engine}

  @exit_codes %{
    success: 0,
    generic_error: 1,
    auth_error: 2,
    rate_limit: 3,
    invalid_request: 4,
    server_error: 5,
    network_error: 6,
    input_error: 7,
    content_filtered: 8,
    insufficient_credits: 9,
    cancelled: 10
  }

  @option_spec [
    strict: [
      help: :boolean,
      version: :boolean,
      input: :string,
      paths: :keep,
      json: :boolean,
      output: :string,
      quick: :boolean,
      deep: :boolean,
      models: :string,
      roles: :string,
      perspectives: :integer,
      tier: :string,
      dry_run: :boolean,
      no_synthesis: :boolean,
      base: :string,
      head: :string,
      repo: :string,
      pr: :integer
    ],
    aliases: [
      h: :help,
      v: :version,
      q: :quick,
      d: :deep,
      o: :output,
      t: :tier
    ]
  ]

  @spec exit_codes() :: %{atom() => non_neg_integer()}
  def exit_codes, do: @exit_codes

  @spec main([String.t()]) :: no_return()
  def main(args) do
    exit_code =
      args
      |> parse_args()
      |> then(fn
        {:needs_stdin, parsed} -> maybe_read_stdin(parsed)
        other -> other
      end)
      |> execute()

    System.halt(exit_code)
  end

  @spec execute({:ok, map()} | {:error, String.t()} | {:help, map()} | {:version, map()}) ::
          non_neg_integer()
  def execute({:help, _}) do
    IO.puts(usage_text())
    @exit_codes.success
  end

  def execute({:version, _}) do
    IO.puts("thinktank #{version()}")
    @exit_codes.success
  end

  def execute({:error, message}) do
    IO.puts(:stderr, "Error: #{message}")
    @exit_codes.input_error
  end

  def execute({:ok, %{action: :workflows_list} = command}) do
    with {:ok, config} <- Config.load(cwd: command.cwd) do
      Config.list_workflows(config)
      |> Enum.each(fn workflow ->
        IO.puts("#{workflow.id}\t#{workflow.description}")
      end)

      @exit_codes.success
    else
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :workflows_show, workflow_id: workflow_id} = command}) do
    with {:ok, config} <- Config.load(cwd: command.cwd),
         {:ok, workflow} <- Config.workflow(config, workflow_id) do
      rendered =
        %{
          id: workflow.id,
          description: workflow.description,
          default_mode: workflow.default_mode,
          execution_mode: workflow.execution_mode,
          stages:
            Enum.map(workflow.stages, fn stage ->
              %{
                name: stage.name,
                type: stage.type,
                kind: stage.kind,
                when: stage.when,
                retry: stage.retry,
                concurrency: stage.concurrency
              }
            end)
        }
        |> Jason.encode!(pretty: true)

      IO.puts(rendered)
      @exit_codes.success
    else
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :workflows_validate} = command}) do
    case Config.load(cwd: command.cwd) do
      {:ok, config} ->
        IO.puts("Validated #{length(Config.list_workflows(config))} workflows")
        @exit_codes.success

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :run} = command}) do
    if command.dry_run do
      emit(command, dry_run_output(command))
      @exit_codes.success
    else
      run_workflow(command)
    end
  end

  @doc false
  @spec parse_args([String.t()]) ::
          {:ok, map()}
          | {:error, String.t()}
          | {:help, map()}
          | {:version, map()}
          | {:needs_stdin, map()}
  def parse_args(args) do
    {parsed, rest, invalid} = OptionParser.parse(args, @option_spec)

    cond do
      invalid != [] ->
        [{flag, _} | _] = invalid
        {:error, "unknown flag: #{flag}"}

      parsed[:help] ->
        {:help, %{}}

      parsed[:version] ->
        {:version, %{}}

      rest == [] ->
        {:needs_stdin, build_research_command(parsed, nil)}

      true ->
        build_command(rest, parsed)
    end
  end

  @doc """
  Dry-run output for the workflow engine CLI.
  """
  @spec dry_run_output(map()) :: String.t()
  def dry_run_output(command) do
    Jason.encode!(%{
      action: command.action,
      workflow: command.workflow_id,
      mode: command.mode,
      input: command.input,
      output: command.output,
      json: command.json
    })
  end

  defp build_command(["run", workflow_id | remainder], parsed) do
    if workflow_id == "review/cerberus" and parsed[:quick] do
      {:error, "review/cerberus is agentic-only; remove --quick"}
    else
      with :ok <- validate_review_pr_flags(workflow_id, parsed),
           {:ok, tier} <- parse_tier(parsed[:tier]) do
        input_text = resolve_input_text(parsed[:input], remainder)

        if input_text == nil do
          {:needs_stdin, build_run_command(workflow_id, parsed, nil, tier)}
        else
          {:ok, build_run_command(workflow_id, parsed, input_text, tier)}
        end
      end
    end
  end

  defp build_command(["review" | remainder], parsed) do
    if parsed[:quick] do
      {:error, "thinktank review is agentic-only; remove --quick"}
    else
      with :ok <- validate_review_pr_flags("review/cerberus", parsed),
           {:ok, tier} <- parse_tier(parsed[:tier]) do
        {:ok, build_review_command(parsed, resolve_input_text(parsed[:input], remainder), tier)}
      end
    end
  end

  defp build_command(["research" | remainder], parsed) do
    case parse_tier(parsed[:tier]) do
      {:ok, tier} ->
        input_text = resolve_input_text(parsed[:input], remainder)

        if input_text == nil do
          {:needs_stdin, build_research_command(parsed, nil, tier)}
        else
          {:ok, build_research_command(parsed, input_text, tier)}
        end

      {:error, _} = error ->
        error
    end
  end

  defp build_command(["workflows", "list"], parsed) do
    {:ok, %{action: :workflows_list, cwd: File.cwd!(), json: parsed[:json] || false}}
  end

  defp build_command(["workflows", "show", workflow_id], parsed) do
    {:ok,
     %{
       action: :workflows_show,
       workflow_id: workflow_id,
       cwd: File.cwd!(),
       json: parsed[:json] || false
     }}
  end

  defp build_command(["workflows", "validate"], parsed) do
    {:ok, %{action: :workflows_validate, cwd: File.cwd!(), json: parsed[:json] || false}}
  end

  defp build_command(rest, parsed) do
    case parse_tier(parsed[:tier]) do
      {:ok, tier} -> {:ok, build_research_command(parsed, Enum.join(rest, " "), tier)}
      {:error, _} = error -> error
    end
  end

  defp resolve_input_text(value, _remainder) when is_binary(value) and value != "", do: value
  defp resolve_input_text(_, []), do: nil
  defp resolve_input_text(_, remainder), do: Enum.join(remainder, " ")

  defp build_run_command(workflow_id, parsed, input_text, tier) do
    common = build_common_command(parsed, workflow_id, tier)
    Map.put(common, :input, build_input(parsed, input_text, tier))
  end

  defp build_research_command(parsed, input_text, tier \\ :standard) do
    common = build_common_command(parsed, "research/default", tier)
    Map.put(common, :input, build_input(parsed, input_text, tier))
  end

  defp build_review_command(parsed, input_text, tier) do
    common = build_common_command(parsed, "review/cerberus", tier)

    input =
      build_input(parsed, input_text, tier)
      |> maybe_put(:base, parsed[:base])
      |> maybe_put(:head, parsed[:head])
      |> maybe_put(:repo, parsed[:repo])
      |> maybe_put(:pr, parsed[:pr])

    Map.put(common, :input, input)
  end

  defp build_common_command(parsed, workflow_id, tier) do
    %{
      action: :run,
      workflow_id: workflow_id,
      mode: mode_for(parsed),
      json: parsed[:json] || false,
      output: if(parsed[:output], do: Path.expand(parsed[:output])),
      dry_run: parsed[:dry_run] || false,
      cwd: File.cwd!(),
      tier: tier
    }
  end

  defp build_input(parsed, input_text, tier) do
    %{}
    |> maybe_put(:input_text, input_text)
    |> Map.put(:paths, parsed |> Keyword.get_values(:paths) |> Enum.map(&Path.expand/1))
    |> Map.put(:models, parse_csv(parsed[:models]))
    |> Map.put(:roles, parse_csv(parsed[:roles]))
    |> Map.put(:tier, tier)
    |> maybe_put(:perspectives, parsed[:perspectives])
    |> Map.put(:no_synthesis, parsed[:no_synthesis] || false)
  end

  defp maybe_put_stdin(command, input_text) do
    put_in(command, [:input, :input_text], input_text)
  end

  defp maybe_read_stdin(command) do
    with true <- stdin_piped?(),
         data when is_binary(data) <- IO.read(:stdio, :eof),
         trimmed = String.trim(data),
         false <- trimmed == "" do
      {:ok, maybe_put_stdin(command, trimmed)}
    else
      _ -> {:error, "input required"}
    end
  end

  defp run_workflow(command) do
    opts =
      [
        cwd: command.cwd,
        mode: command.mode,
        output: command.output,
        agent_config_dir: agent_config_dir()
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Engine.run(command.workflow_id, command.input, opts) do
      {:ok, result} ->
        emit(command, successful_payload(command, result))
        Map.get(result.context, :workflow_exit_code, 0)

      {:error, reason, output_dir} ->
        if output_dir do
          IO.puts(:stderr, "Output: #{output_dir}")
        end

        IO.puts(:stderr, "Error: #{format_reason(reason)}")
        @exit_codes.generic_error
    end
  end

  defp successful_payload(command, result) do
    payload =
      result.envelope
      |> Map.put(:workflow, result.workflow.id)
      |> Map.put(:output_dir, result.output_dir)

    payload =
      case result.context[:final_verdict] do
        nil -> payload
        verdict -> Map.put(payload, :final_verdict, verdict)
      end

    payload =
      case result.context[:synthesis] do
        nil ->
          payload

        synthesis ->
          Map.put(payload, :synthesis_file, "synthesis.md")
          |> Map.put(:synthesis_usage, synthesis.usage)
      end

    if command.json, do: Jason.encode!(payload), else: render_success(payload)
  end

  defp render_success(payload) do
    lines = [
      "Workflow: #{payload.workflow}",
      "Output: #{payload.output_dir}",
      "Status: #{payload.status}"
    ]

    lines =
      case payload[:final_verdict] do
        nil -> lines
        verdict -> lines ++ ["Verdict: #{verdict.verdict}"]
      end

    Enum.join(lines, "\n")
  end

  defp emit(_command, payload) when is_binary(payload) do
    IO.puts(payload)
  end

  defp emit(_command, payload) do
    IO.puts(payload)
  end

  defp format_reason({:stage_failed, stage_name, reason}),
    do: "stage #{stage_name} failed: #{inspect(reason)}"

  defp format_reason({:mode_not_allowed, workflow_id, requested, required}),
    do: "#{workflow_id} requires #{required} mode; got #{requested}"

  defp format_reason({:invalid_workflow_mode_config, workflow_id, default_mode, required}),
    do: "#{workflow_id} default_mode #{default_mode} conflicts with execution_mode #{required}"

  defp format_reason({:pr_review_requires_git_workspace, repo}),
    do: "remote PR review for #{repo} requires running inside a local checkout of that repository"

  defp format_reason({:pr_review_repo_mismatch, repo, remote}),
    do:
      "remote PR review for #{repo} requires a matching local checkout; current origin is #{remote}"

  defp format_reason({:pr_review_requires_checkout, repo, head_ref, head_sha}),
    do:
      "remote PR review for #{repo} requires the local workspace to be checked out at #{head_ref} (#{head_sha})"

  defp format_reason({:pr_review_requires_repo, pr_number}),
    do: "PR review #{pr_number} requires a --repo value"

  defp format_reason({:pr_review_requires_number, repo}),
    do: "PR review for #{repo} requires a --pr value"

  defp format_reason(reason), do: inspect(reason)

  defp mode_for(parsed) do
    cond do
      parsed[:quick] -> :quick
      parsed[:deep] -> :deep
      true -> nil
    end
  end

  @doc """
  Resolve agent config directory for deep mode Pi agents.

  Checks `THINKTANK_AGENT_CONFIG` first.
  Repository-local `agent_config` requires explicit opt-in via
  `THINKTANK_TRUST_REPO_AGENT_CONFIG=1`.
  """
  @spec agent_config_dir() :: String.t() | nil
  def agent_config_dir do
    case System.get_env("THINKTANK_AGENT_CONFIG") do
      nil ->
        maybe_repo_agent_config_dir()

      dir ->
        dir
    end
  end

  defp maybe_repo_agent_config_dir do
    if trust_repo_agent_config?() do
      dir = Path.join(File.cwd!(), "agent_config")
      if File.dir?(dir), do: dir
    end
  end

  defp trust_repo_agent_config? do
    System.get_env("THINKTANK_TRUST_REPO_AGENT_CONFIG") in ["1", "true", "TRUE", "yes", "YES"]
  end

  @doc """
  Returns the usage help text.
  """
  @spec usage_text() :: String.t()
  def usage_text do
    """
    thinktank — workflow engine for multi-agent research and review

    USAGE
      thinktank run <workflow> --input "..." [options]
      thinktank research "prompt" [options]
      thinktank review [--base main --head HEAD] [options]
      thinktank workflows list|show|validate

    OPTIONS
      --input TEXT     Workflow input text
      --paths PATH     Files or directories for context (repeatable)
      --quick, -q      Direct API fanout executor
      --deep, -d       Agentic Pi subprocess executor
      --tier, -t TIER  Model tier: cheap, standard, premium
      --models LIST    Comma-separated model overrides
      --roles LIST     Comma-separated routed research roles
      --perspectives N Routed research perspective count
      --json           Emit JSON to stdout
      --output, -o     Output directory
      --dry-run        Print the workflow contract without executing
      --base REF       Review base ref
      --head REF       Review head ref
      --repo REPO      GitHub repository for PR review mode
      --pr N           GitHub pull request number for PR review mode
      --help, -h       Show this help
      --version, -v    Show version

    EXAMPLES
      thinktank run research/default --input "compare these architectures" --paths ./lib --json
      thinktank research "audit this auth flow" --paths ./lib/auth --deep
      thinktank review --base origin/main --head HEAD
      thinktank workflows show review/cerberus
    """
  end

  defp parse_tier(nil), do: {:ok, :standard}
  defp parse_tier("cheap"), do: {:ok, :cheap}
  defp parse_tier("standard"), do: {:ok, :standard}
  defp parse_tier("premium"), do: {:ok, :premium}

  defp parse_tier(other),
    do: {:error, "invalid tier: #{other} (must be cheap, standard, or premium)"}

  defp validate_review_pr_flags(workflow_id, parsed) do
    case {parsed[:pr], parsed[:repo]} do
      {nil, _} ->
        :ok

      {_pr, repo} when is_binary(repo) and repo != "" ->
        :ok

      {_pr, _repo} ->
        {:error, "#{workflow_id} requires --repo when --pr is provided"}
    end
  end

  defp parse_csv(nil), do: []
  defp parse_csv(""), do: []

  defp parse_csv(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()

  defp stdin_piped? do
    match?({:error, _}, :io.columns(:standard_io))
  rescue
    _ -> false
  end
end
