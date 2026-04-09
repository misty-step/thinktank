defmodule Thinktank.Prompts.ReviewTest do
  use ExUnit.Case, async: true

  alias Thinktank.Prompts.Review

  test "task/0 contains required placeholders" do
    task = Review.task()

    for placeholder <-
          ~w(
            {{input_text}}
            {{workspace_root}}
            {{repo}}
            {{pr}}
            {{base}}
            {{head}}
            {{paths_hint}}
            {{review_role}}
            {{review_brief}}
            {{review_context}}
            {{review_plan}}
          ) do
      assert task =~ placeholder, "review task prompt missing #{placeholder}"
    end
  end

  test "plan_task/0 contains required placeholders" do
    plan = Review.plan_task()

    for placeholder <-
          ~w(
            {{input_text}}
            {{workspace_root}}
            {{repo}}
            {{pr}}
            {{base}}
            {{head}}
            {{paths_hint}}
            {{review_context}}
            {{review_roster}}
          ) do
      assert plan =~ placeholder, "review plan_task prompt missing #{placeholder}"
    end
  end

  for name <- [
        :marshal,
        :trace,
        :guard,
        :atlas,
        :proof,
        :vector,
        :pulse,
        :scout,
        :forge,
        :orbit,
        :sentry
      ] do
    test "#{name}/0 returns a non-empty binary" do
      result = apply(Review, unquote(name), [])
      assert is_binary(result) and byte_size(result) > 0
    end
  end
end
