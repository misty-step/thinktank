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

  @spec summary_file() :: String.t()
  def summary_file, do: @summary_file

  @spec review_file() :: String.t()
  def review_file, do: @review_file

  @spec synthesis_file() :: String.t()
  def synthesis_file, do: @synthesis_file

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

  @spec agents_dir() :: String.t()
  def agents_dir, do: @agents_dir

  @spec artifacts_dir() :: String.t()
  def artifacts_dir, do: @artifacts_dir

  @spec prompts_dir() :: String.t()
  def prompts_dir, do: @prompts_dir

  @spec pi_home_dir() :: String.t()
  def pi_home_dir, do: @pi_home_dir

  @spec scratchpads_dir() :: String.t()
  def scratchpads_dir, do: @scratchpads_dir

  @spec streams_dir() :: String.t()
  def streams_dir, do: @streams_dir

  @spec run_directories() :: [String.t()]
  def run_directories do
    [
      agents_dir(),
      artifacts_dir(),
      streams_dir(),
      prompts_dir(),
      pi_home_dir(),
      scratchpads_dir()
    ]
  end

  @spec agent_result_file(String.t()) :: String.t()
  def agent_result_file(instance_id), do: Path.join(agents_dir(), "#{instance_id}.md")

  @spec run_scratchpad_file() :: String.t()
  def run_scratchpad_file, do: Path.join(scratchpads_dir(), "run.md")

  @spec agent_scratchpad_file(String.t()) :: String.t()
  def agent_scratchpad_file(instance_id), do: Path.join(scratchpads_dir(), "#{instance_id}.md")

  @spec agent_stream_file(String.t()) :: String.t()
  def agent_stream_file(instance_id), do: Path.join(streams_dir(), "#{instance_id}.txt")

  @spec summary_artifacts(atom() | String.t() | nil) :: [{String.t(), String.t()}]
  def summary_artifacts(kind) do
    kind =
      if is_binary(kind) do
        try do
          String.to_existing_atom(kind)
        rescue
          ArgumentError -> nil
        end
      else
        kind
      end

    [{"summary", summary_file()} | kind_summary_artifacts(kind)]
  end

  defp kind_summary_artifacts(:review), do: [{"review", review_file()}]
  defp kind_summary_artifacts(:research), do: [{"synthesis", synthesis_file()}]
  defp kind_summary_artifacts(_kind), do: []
end
