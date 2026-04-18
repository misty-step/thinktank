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

  @spec scratchpads_dir() :: String.t()
  def scratchpads_dir, do: @scratchpads_dir

  @spec run_directories() :: [String.t()]
  def run_directories do
    [@agents_dir, @artifacts_dir, @streams_dir, @prompts_dir, @pi_home_dir, @scratchpads_dir]
  end

  @spec agent_result_file(String.t()) :: String.t()
  def agent_result_file(instance_id), do: Path.join(@agents_dir, "#{instance_id}.md")

  @spec run_scratchpad_file() :: String.t()
  def run_scratchpad_file, do: Path.join(@scratchpads_dir, "run.md")

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
