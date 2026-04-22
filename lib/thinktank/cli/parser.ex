defmodule Thinktank.CLI.Parser do
  @moduledoc false

  alias Thinktank.{BenchSpec, Config}

  @option_spec [
    strict: [
      help: :boolean,
      version: :boolean,
      input: :string,
      paths: :keep,
      agents: :string,
      bench: :string,
      json: :boolean,
      full: :boolean,
      output: :string,
      dry_run: :boolean,
      no_synthesis: :boolean,
      trust_repo_config: :boolean,
      base: :string,
      head: :string,
      repo: :string,
      pr: :integer
    ],
    aliases: [
      h: :help,
      v: :version,
      o: :output
    ]
  ]

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
        build_fixed_bench_command(
          "research/default",
          parsed,
          resolve_input_text(parsed[:input], [])
        )

      true ->
        build_command(rest, parsed)
    end
  end

  @spec read_stdin(map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def read_stdin(command, opts \\ []) do
    if stdin_piped?(opts) do
      input =
        opts
        |> Keyword.get(:reader, &IO.read/2)
        |> then(& &1.(:stdio, :eof))
        |> case do
          data when is_binary(data) -> String.trim(data)
          _ -> ""
        end

      if input == "" do
        {:error, "input text is required"}
      else
        {:ok, put_in(command.input.input_text, input)}
      end
    else
      {:error, "input text is required"}
    end
  end

  defp build_command(["run", bench_id | remainder], parsed) do
    with {:ok, config, bench} <- resolve_bench(bench_id, parsed),
         :ok <- validate_review_pr_flags(bench, parsed) do
      input_text = resolve_input_text(parsed[:input], remainder)

      if input_text == nil and needs_stdin?(bench) do
        {:needs_stdin, build_run_command(bench, parsed, nil, config)}
      else
        {:ok, build_run_command(bench, parsed, input_text, config)}
      end
    end
  end

  defp build_command(["review", "eval", target], parsed) do
    {:ok,
     %{
       action: :review_eval,
       target: Path.expand(target),
       bench_id: parsed[:bench],
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       output: parsed[:output] && Path.expand(parsed[:output]),
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command(["review", "eval"], _parsed), do: {:error, "review eval requires a path"}

  defp build_command(["review" | remainder], parsed) do
    with {:ok, config, bench} <- resolve_bench("review/default", parsed),
         :ok <- validate_review_pr_flags(bench, parsed) do
      input_text = resolve_input_text(parsed[:input], remainder)

      if input_text == nil and needs_stdin?(bench) do
        {:needs_stdin, build_run_command(bench, parsed, nil, config)}
      else
        {:ok, build_run_command(bench, parsed, input_text, config)}
      end
    end
  end

  defp build_command(["research" | remainder], parsed) do
    input_text = resolve_input_text(parsed[:input], remainder)
    build_fixed_bench_command("research/default", parsed, input_text)
  end

  defp build_command(["run"], _parsed), do: {:error, "run requires a bench id"}

  defp build_command([group, "list"], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_list,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command(["runs", "list"], parsed) do
    {:ok,
     %{
       action: :runs_list,
       cwd: File.cwd!(),
       json: parsed[:json] || false
     }}
  end

  defp build_command(["runs", "show", target], parsed) do
    {:ok,
     %{
       action: :runs_show,
       target: target,
       cwd: File.cwd!(),
       json: parsed[:json] || false
     }}
  end

  defp build_command(["runs", "wait", target], parsed) do
    {:ok,
     %{
       action: :runs_wait,
       target: target,
       cwd: File.cwd!(),
       json: parsed[:json] || false
     }}
  end

  defp build_command(["runs" | _rest], _parsed) do
    {:error, "runs expects list, show <path-or-id>, or wait <path-or-id>"}
  end

  defp build_command([group, "show", bench_id], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_show,
       bench_id: bench_id,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       full: parsed[:full] || false,
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command([group, "validate"], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_validate,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command([group | _rest], _parsed) when group in ["benches", "workflows"] do
    {:error, "#{group} expects list, show <bench>, or validate"}
  end

  defp build_command(rest, parsed) do
    build_fixed_bench_command("research/default", parsed, Enum.join(rest, " "))
  end

  defp build_fixed_bench_command(bench_id, parsed, input_text) do
    with {:ok, config, bench} <- resolve_bench(bench_id, parsed),
         :ok <- validate_review_pr_flags(bench, parsed) do
      if input_text == nil and needs_stdin?(bench) do
        {:needs_stdin, build_run_command(bench, parsed, nil, config)}
      else
        {:ok, build_run_command(bench, parsed, input_text, config)}
      end
    end
  end

  defp build_run_command(%BenchSpec{} = bench, parsed, input_text, config) do
    command = build_common_command(parsed, bench.id, input_text || bench.default_task)
    command = Map.put(command, :config, config)

    if review_bench?(bench) do
      put_in(command.input, Map.merge(command.input, review_input(parsed)))
    else
      command
    end
  end

  defp build_common_command(parsed, bench_id, input_text) do
    cwd = File.cwd!()
    paths = normalize_paths(Keyword.get_values(parsed, :paths))

    %{
      action: :run,
      bench_id: bench_id,
      cwd: cwd,
      json: parsed[:json] || false,
      output: parsed[:output] && Path.expand(parsed[:output]),
      dry_run: parsed[:dry_run] || false,
      trust_repo_config: parsed[:trust_repo_config],
      warnings: path_scope_warnings(cwd, paths),
      input: %{
        input_text: input_text,
        paths: paths,
        agents: parse_agent_list(parsed[:agents]),
        no_synthesis: parsed[:no_synthesis] || false
      }
    }
  end

  defp review_input(parsed) do
    %{}
    |> maybe_put_value(:base, parsed[:base])
    |> maybe_put_value(:head, parsed[:head])
    |> maybe_put_value(:repo, parsed[:repo])
    |> maybe_put_value(:pr, parsed[:pr])
  end

  defp validate_review_pr_flags(%BenchSpec{id: bench_id} = bench, parsed) do
    parsed = if is_map(parsed), do: parsed, else: Map.new(parsed)

    cond do
      !review_bench?(bench) ->
        :ok

      parsed[:pr] && !parsed[:repo] ->
        {:error, "#{bench_id} requires --repo when --pr is provided"}

      true ->
        :ok
    end
  end

  defp resolve_bench(bench_id, parsed) do
    with {:ok, config} <-
           Config.load(cwd: File.cwd!(), trust_repo_config: parsed[:trust_repo_config]) do
      case Config.bench(config, bench_id) do
        {:ok, bench} -> {:ok, config, bench}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp needs_stdin?(%BenchSpec{default_task: default_task}), do: is_nil(default_task)

  defp review_bench?(%BenchSpec{kind: :review}), do: true
  defp review_bench?(_), do: false

  defp resolve_input_text(nil, []), do: nil
  defp resolve_input_text(value, _rest) when is_binary(value), do: value
  defp resolve_input_text(nil, rest), do: Enum.join(rest, " ")

  defp path_scope_warnings(cwd, paths) when is_list(paths) do
    Enum.flat_map(paths, fn path ->
      if outside_workspace?(cwd, path) do
        [
          "--paths includes #{path}, which is outside the current workspace #{Path.expand(cwd)}. " <>
            "ThinkTank agents reason from workspace root; rerun from that repo before using --paths."
        ]
      else
        []
      end
    end)
  end

  defp normalize_paths(paths) when is_list(paths), do: Enum.map(paths, &Path.expand/1)

  defp outside_workspace?(cwd, path) do
    workspace_segments = Path.expand(cwd) |> Path.split()
    path_segments = Path.expand(path) |> Path.split()
    not path_prefix?(workspace_segments, path_segments)
  end

  defp path_prefix?([], _path_segments), do: true
  defp path_prefix?(_workspace_segments, []), do: false

  defp path_prefix?([segment | workspace_rest], [segment | path_rest]) do
    path_prefix?(workspace_rest, path_rest)
  end

  defp path_prefix?(_workspace_segments, _path_segments), do: false

  defp parse_agent_list(nil), do: []

  defp parse_agent_list(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_agent_list(_), do: []

  defp maybe_put_value(map, _key, nil), do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp stdin_piped?(opts) do
    case Keyword.get(opts, :stdin_piped?, &stdin_piped?/0) do
      fun when is_function(fun, 0) -> fun.()
      value -> value
    end
  end

  defp stdin_piped? do
    match?({:error, _}, :io.columns(:standard_io))
  rescue
    _ -> false
  end
end
