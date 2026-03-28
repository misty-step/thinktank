defmodule Thinktank.Review.Context do
  @moduledoc false

  @max_files 200

  @type t :: map()

  @spec capture(String.t(), map(), keyword()) :: t()
  def capture(workspace_root, input, opts \\ [])
      when is_binary(workspace_root) and is_map(input) do
    git_runner = Keyword.get(opts, :git_runner, &default_git_runner/2)

    if git_available?(workspace_root, git_runner) do
      build_git_context(workspace_root, stringify_keys(input), git_runner)
    else
      unavailable_context(workspace_root)
    end
  end

  @spec render(t()) :: String.t()
  def render(context) when is_map(context) do
    git = Map.get(context, "git", %{})
    change = Map.get(context, "change", %{})
    signals = Map.get(change, "signals", %{})
    line_stats = Map.get(change, "line_stats", %{})

    files =
      change
      |> Map.get("files", [])
      |> Enum.take(12)

    file_lines =
      case files do
        [] -> "- none"
        list -> Enum.map_join(list, "\n", &"- #{&1}")
      end

    """
    Review context:
    - Git context available: #{yes_no(git["available"])}
    - Branch: #{git["branch"] || "unknown"}
    - Diff scope: #{git["range"] || "workspace changes"}
    - Files changed: #{change["file_count"] || 0}
    - Directories changed: #{change["directory_count"] || 0}
    - Line churn: +#{line_stats["added"] || 0} / -#{line_stats["deleted"] || 0}

    Change signals:
    - touches_code: #{yes_no(signals["touches_code"])}
    - touches_tests: #{yes_no(signals["touches_tests"])}
    - touches_docs: #{yes_no(signals["touches_docs"])}
    - touches_ci: #{yes_no(signals["touches_ci"])}
    - touches_dependencies: #{yes_no(signals["touches_dependencies"])}
    - touches_security_surface: #{yes_no(signals["touches_security_surface"])}

    Changed files (sample):
    #{file_lines}
    """
    |> String.trim()
  end

  defp build_git_context(workspace_root, input, git_runner) do
    base = present_string(input["base"])
    head = present_string(input["head"]) || "HEAD"
    range = if(base, do: "#{base}...#{head}", else: nil)

    {files, file_warnings} = collect_files(workspace_root, range, git_runner)
    {line_stats, line_warnings} = collect_line_stats(workspace_root, range, git_runner)

    directories =
      files
      |> Enum.map(&top_directory/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    warnings = file_warnings ++ line_warnings

    %{
      "version" => 1,
      "git" => %{
        "available" => true,
        "branch" => git_output(workspace_root, ~w(rev-parse --abbrev-ref HEAD), git_runner),
        "head_sha" => git_output(workspace_root, ~w(rev-parse HEAD), git_runner),
        "base" => base,
        "head" => head,
        "range" => range,
        "merge_base" => merge_base(workspace_root, base, head, git_runner)
      },
      "change" => %{
        "file_count" => length(files),
        "directory_count" => length(directories),
        "directories" => directories,
        "files" => Enum.take(files, @max_files),
        "files_truncated" => length(files) > @max_files,
        "line_stats" => line_stats,
        "signals" => change_signals(files)
      },
      "warnings" => warnings
    }
  end

  defp unavailable_context(workspace_root) do
    %{
      "version" => 1,
      "git" => %{
        "available" => false,
        "branch" => nil,
        "head_sha" => nil,
        "base" => nil,
        "head" => nil,
        "range" => nil,
        "merge_base" => nil
      },
      "change" => %{
        "file_count" => 0,
        "directory_count" => 0,
        "directories" => [],
        "files" => [],
        "files_truncated" => false,
        "line_stats" => %{"added" => 0, "deleted" => 0, "binary_files" => 0},
        "signals" => empty_signals()
      },
      "warnings" => ["git context unavailable for #{workspace_root}"]
    }
  end

  defp collect_files(workspace_root, nil, git_runner) do
    {tracked, tracked_warnings} =
      git_lines(workspace_root, ~w(diff --name-only --diff-filter=ACMRTUXB HEAD), git_runner)

    {untracked, untracked_warnings} =
      git_lines(workspace_root, ~w(ls-files --others --exclude-standard), git_runner)

    {Enum.uniq(tracked ++ untracked), tracked_warnings ++ untracked_warnings}
  end

  defp collect_files(workspace_root, range, git_runner) do
    args = ["diff", "--name-only", "--diff-filter=ACMRTUXB", range]

    case git_output(workspace_root, args, git_runner, with_status: true) do
      {:ok, output} ->
        files = output |> String.split("\n", trim: true) |> Enum.uniq()
        {files, []}

      {:error, reason} ->
        collect_files(workspace_root, nil, git_runner)
        |> then(fn {files, warnings} ->
          {files, ["failed to inspect diff range #{range}: #{reason}" | warnings]}
        end)
    end
  end

  defp collect_line_stats(workspace_root, nil, git_runner) do
    case git_output(workspace_root, ~w(diff --numstat HEAD), git_runner, with_status: true) do
      {:ok, output} -> {parse_numstat(output), []}
      {:error, reason} -> {%{"added" => 0, "deleted" => 0, "binary_files" => 0}, [reason]}
    end
  end

  defp collect_line_stats(workspace_root, range, git_runner) do
    args = ["diff", "--numstat", range]

    case git_output(workspace_root, args, git_runner, with_status: true) do
      {:ok, output} ->
        {parse_numstat(output), []}

      {:error, reason} ->
        collect_line_stats(workspace_root, nil, git_runner)
        |> then(fn {stats, warnings} ->
          {stats, ["failed to collect line stats for #{range}: #{reason}" | warnings]}
        end)
    end
  end

  defp parse_numstat(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{"added" => 0, "deleted" => 0, "binary_files" => 0}, fn line, acc ->
      case String.split(line, "\t", parts: 3) do
        [added, deleted, _path] ->
          acc
          |> Map.update!("added", &(&1 + parse_numstat_number(added)))
          |> Map.update!("deleted", &(&1 + parse_numstat_number(deleted)))
          |> Map.update!("binary_files", fn count ->
            if added == "-" or deleted == "-", do: count + 1, else: count
          end)

        _ ->
          acc
      end
    end)
  end

  defp parse_numstat_number("-"), do: 0

  defp parse_numstat_number(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> 0
    end
  end

  defp change_signals(files) do
    %{
      "touches_code" => Enum.any?(files, &code_path?/1),
      "touches_tests" => Enum.any?(files, &test_path?/1),
      "touches_docs" => Enum.any?(files, &docs_path?/1),
      "touches_ci" => Enum.any?(files, &ci_path?/1),
      "touches_dependencies" => Enum.any?(files, &dependency_path?/1),
      "touches_security_surface" => Enum.any?(files, &security_path?/1)
    }
  end

  defp empty_signals do
    %{
      "touches_code" => false,
      "touches_tests" => false,
      "touches_docs" => false,
      "touches_ci" => false,
      "touches_dependencies" => false,
      "touches_security_surface" => false
    }
  end

  defp code_path?(path), do: String.starts_with?(path, "lib/")

  defp test_path?(path) do
    String.starts_with?(path, "test/") or
      String.starts_with?(path, "spec/") or
      String.contains?(path, "/test/") or
      String.contains?(path, "/tests/") or
      String.ends_with?(path, "_test.exs")
  end

  defp docs_path?(path) do
    String.starts_with?(path, "docs/") or
      String.starts_with?(path, "doc/") or
      String.starts_with?(path, "README") or
      String.ends_with?(path, ".md")
  end

  defp ci_path?(path) do
    String.starts_with?(path, ".github/workflows/") or
      String.starts_with?(path, ".circleci/") or
      path == "Dockerfile" or
      String.starts_with?(path, "ci/")
  end

  defp dependency_path?(path) do
    path in [
      "mix.exs",
      "mix.lock",
      "package.json",
      "pnpm-lock.yaml",
      "yarn.lock",
      "go.mod",
      "go.sum"
    ]
  end

  defp security_path?(path) do
    lower = String.downcase(path)

    Enum.any?(
      ["auth", "token", "secret", "oauth", "crypto", "permission", "acl", "policy"],
      fn marker ->
        String.contains?(lower, marker)
      end
    )
  end

  defp top_directory(path) do
    path
    |> String.split("/", parts: 2)
    |> List.first()
    |> to_string()
  end

  defp merge_base(_workspace_root, nil, _head, _git_runner), do: nil

  defp merge_base(workspace_root, base, head, git_runner) do
    git_output(workspace_root, ["merge-base", base, head], git_runner)
  end

  defp git_available?(workspace_root, git_runner) do
    case git_output(workspace_root, ~w(rev-parse --is-inside-work-tree), git_runner,
           with_status: true
         ) do
      {:ok, "true"} -> true
      _ -> false
    end
  end

  defp git_output(workspace_root, args, git_runner, opts \\ []) do
    {output, exit_code} = git_runner.(workspace_root, args)
    trimmed = String.trim(output)

    if opts[:with_status] do
      if exit_code == 0 do
        {:ok, trimmed}
      else
        {:error, "git #{Enum.join(args, " ")} failed (#{exit_code}): #{trimmed}"}
      end
    else
      if exit_code == 0, do: trimmed, else: nil
    end
  end

  defp default_git_runner(workspace_root, args) do
    System.cmd("git", args, cd: workspace_root, stderr_to_stdout: true)
  end

  defp git_lines(workspace_root, args, git_runner) do
    case git_output(workspace_root, args, git_runner, with_status: true) do
      {:ok, output} ->
        {String.split(output, "\n", trim: true), []}

      {:error, reason} ->
        {[], [reason]}
    end
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end

  defp present_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp present_string(_), do: nil

  defp yes_no(true), do: "yes"
  defp yes_no(_), do: "no"
end
