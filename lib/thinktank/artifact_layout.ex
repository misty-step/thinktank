defmodule Thinktank.ArtifactLayout do
  @moduledoc """
  Canonical artifact paths for ThinkTank runs.
  """

  @manifest_file "manifest.json"
  @contract_file "contract.json"
  @task_file "task.md"
  @summary_file "summary.md"
  @review_file "review.md"
  @synthesis_file "synthesis.md"
  @research_findings_file "research/findings.json"
  @review_context_json_file "review/context.json"
  @review_context_text_file "review/context.md"
  @review_plan_json_file "review/plan.json"
  @review_plan_text_file "review/plan.md"
  @review_planner_file "review/planner.md"
  @agents_dir "agents"
  @artifacts_dir "artifacts"
  @prompts_dir "prompts"
  @pi_home_dir "pi-home"
  @scratchpads_dir "scratchpads"
  @streams_dir Path.join(@artifacts_dir, "streams")
  @run_scratchpad_file Path.join(@scratchpads_dir, "run.md")

  @artifact_files [
    @manifest_file,
    @contract_file,
    @task_file,
    @summary_file,
    @review_file,
    @synthesis_file,
    @research_findings_file,
    @review_context_json_file,
    @review_context_text_file,
    @review_plan_json_file,
    @review_plan_text_file,
    @review_planner_file,
    @run_scratchpad_file
  ]

  @artifact_directories [
    @agents_dir,
    @artifacts_dir,
    @streams_dir,
    @prompts_dir,
    @pi_home_dir,
    @scratchpads_dir
  ]

  @dynamic_artifact_files [
    Path.join(@agents_dir, "{instance_id}.md"),
    Path.join(@scratchpads_dir, "{instance_id}.md"),
    Path.join(@streams_dir, "{instance_id}.txt")
  ]

  @required_path_contract_entries @artifact_files ++
                                    @artifact_directories ++ @dynamic_artifact_files

  @spec manifest_file() :: String.t()
  def manifest_file, do: @manifest_file

  @spec contract_file() :: String.t()
  def contract_file, do: @contract_file

  @spec task_file() :: String.t()
  def task_file, do: @task_file

  @spec review_context_json_file() :: String.t()
  def review_context_json_file, do: @review_context_json_file

  @spec review_context_text_file() :: String.t()
  def review_context_text_file, do: @review_context_text_file

  @spec review_plan_json_file() :: String.t()
  def review_plan_json_file, do: @review_plan_json_file

  @spec review_plan_text_file() :: String.t()
  def review_plan_text_file, do: @review_plan_text_file

  @spec review_planner_file() :: String.t()
  def review_planner_file, do: @review_planner_file

  @spec research_findings_file() :: String.t()
  def research_findings_file, do: @research_findings_file

  @spec scratchpads_dir() :: String.t()
  def scratchpads_dir, do: @scratchpads_dir

  @spec path_contract() :: %{
          files: [String.t()],
          directories: [String.t()],
          dynamic_files: [String.t()]
        }
  def path_contract do
    %{
      files: @artifact_files,
      directories: @artifact_directories,
      dynamic_files: @dynamic_artifact_files
    }
  end

  @spec validate_path_contract(%{
          required(:files) => [String.t()],
          required(:directories) => [String.t()],
          required(:dynamic_files) => [String.t()]
        }) :: :ok | {:error, keyword([String.t()])}
  def validate_path_contract(contract \\ path_contract()) do
    paths = contract.files ++ contract.directories ++ contract.dynamic_files

    invalid =
      Enum.reject(paths, fn path ->
        Path.type(path) == :relative and path != "" and not String.contains?(path, "..")
      end)

    duplicates =
      paths
      |> Enum.frequencies()
      |> Enum.filter(fn {_path, count} -> count > 1 end)
      |> Enum.map(fn {path, _count} -> path end)

    errors =
      [
        invalid: invalid,
        duplicate: duplicates,
        missing: @required_path_contract_entries -- paths
      ]
      |> Enum.reject(fn {_kind, entries} -> entries == [] end)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  @spec run_directories() :: [String.t()]
  def run_directories, do: @artifact_directories

  @spec agent_result_file(String.t()) :: String.t()
  def agent_result_file(instance_id), do: Path.join(@agents_dir, "#{instance_id}.md")

  @spec run_scratchpad_file() :: String.t()
  def run_scratchpad_file, do: @run_scratchpad_file

  @spec agent_scratchpad_file(String.t()) :: String.t()
  def agent_scratchpad_file(instance_id), do: Path.join(@scratchpads_dir, "#{instance_id}.md")

  @spec agent_stream_file(String.t()) :: String.t()
  def agent_stream_file(instance_id), do: Path.join(@streams_dir, "#{instance_id}.txt")

  @spec summary_artifacts(atom() | String.t() | nil) :: [{String.t(), String.t()}]
  def summary_artifacts(:review), do: [{"summary", @summary_file}, {"review", @review_file}]

  def summary_artifacts(:research),
    do: [{"summary", @summary_file}, {"synthesis", @synthesis_file}]

  def summary_artifacts(kind) when is_binary(kind) do
    case kind do
      "review" -> summary_artifacts(:review)
      "research" -> summary_artifacts(:research)
      _ -> [{"summary", @summary_file}]
    end
  end

  def summary_artifacts(_kind), do: [{"summary", @summary_file}]
end
