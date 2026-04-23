defmodule Thinktank.Prompts.Synthesis do
  @moduledoc false

  alias Thinktank.Research.Findings

  @research_system """
  You synthesize multiple research agent reports into one structured findings contract.
  Preserve disagreements. Do not invent consensus. Favor grounded recommendations over rhetoric.
  Return valid JSON only. Do not wrap the JSON in Markdown fences.
  """

  @review_system """
  You synthesize multiple code review reports into one actionable review document.

  Deduplicate: when multiple reviewers flag the same issue, consolidate into one
  finding and credit all reviewers who caught it. Prioritize by severity and impact,
  not by reviewer order. Preserve genuine disagreements — if reviewers contradict
  each other, present both positions rather than picking a winner.

  If the bench found no real issues, say that plainly. Do not manufacture concerns
  to fill space. Write a clear human review, not structured JSON.
  """

  @research_task_prefix """
  Original task:
  {{input_text}}

  Workspace root: {{workspace_root}}
  Focus paths:
  {{paths_hint}}

  Agent outputs:
  {{agent_outputs}}
  """

  @review_task """
  Original task:
  {{input_text}}

  Workspace root: {{workspace_root}}
  Repo: {{repo}}
  PR: {{pr}}
  Base ref: {{base}}
  Head ref: {{head}}
  Focus paths:
  {{paths_hint}}

  Review context:
  {{review_context}}

  Review plan:
  {{review_plan}}

  Synthesis brief from planner:
  {{synthesis_brief}}

  Agent outputs:
  {{agent_outputs}}
  """

  def research_system, do: @research_system
  def review_system, do: @review_system

  def research_task do
    """
    #{@research_task_prefix}

    Return JSON only with this shape:
    #{Findings.schema_prompt()}
    """
  end

  def review_task, do: @review_task
end
