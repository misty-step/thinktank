defmodule Thinktank.StageRegistryTest do
  use ExUnit.Case, async: true

  alias Thinktank.StageRegistry

  test "aggregates critical and low-confidence reviewer verdicts correctly" do
    assert StageRegistry.aggregate_review_verdict([]).verdict == "FAIL"

    assert StageRegistry.aggregate_review_verdict([
             %{
               status: :ok,
               verdict: %{verdict: "FAIL", confidence: 0.95, findings: [%{severity: "critical"}]}
             },
             %{status: :ok, verdict: %{verdict: "PASS", confidence: 0.95, findings: []}}
           ]).verdict == "FAIL"

    assert StageRegistry.aggregate_review_verdict([
             %{
               status: :ok,
               verdict: %{verdict: "FAIL", confidence: 0.4, findings: [%{severity: "critical"}]}
             },
             %{status: :ok, verdict: %{verdict: "PASS", confidence: 0.95, findings: []}}
           ]).verdict == "FAIL"

    assert StageRegistry.aggregate_review_verdict([
             %{status: :ok, verdict: %{verdict: "WARN", confidence: 0.9, findings: []}}
           ]).verdict == "WARN"
  end

  test "does not count low-confidence but parseable reviews as invalid reviewers" do
    verdict =
      StageRegistry.aggregate_review_verdict([
        %{status: :ok, verdict: %{verdict: "PASS", confidence: 0.95, findings: []}},
        %{status: :ok, verdict: %{verdict: "PASS", confidence: 0.4, findings: []}},
        %{status: :ok, verdict: %{verdict: "WARN", confidence: 0.2, findings: []}}
      ])

    assert verdict.verdict == "WARN"
    assert verdict.reviewers == 1
    assert verdict.failing_reviewers == 0
    assert verdict.invalid_reviewers == 0
    assert verdict.warning_reviewers == 0
    assert verdict.low_confidence_reviewers == 2
    assert verdict.reason == "low_confidence_excluded"
  end

  test "fails review aggregation when no valid reviewer verdicts remain" do
    verdict =
      StageRegistry.aggregate_review_verdict([
        %{status: :parse_error, error: :bad_json},
        %{status: :runtime_error, error: %{category: :timeout}}
      ])

    assert verdict.verdict == "FAIL"
    assert verdict.reviewers == 0
    assert verdict.failing_reviewers == 1
    assert verdict.invalid_reviewers == 1
    assert verdict.reason == "no_valid_reviews"
  end

  test "returns handled errors when a runtime route references an unknown agent" do
    stage = %Thinktank.StageSpec{
      name: "route",
      type: :route,
      kind: "cerberus_review",
      options: %{}
    }

    config = %Thinktank.Config{agents: %{}, providers: %{}, workflows: %{}, sources: %{}}

    assert {:error, {:unknown_agent, "trace"}} =
             StageRegistry.cerberus_review(
               stage,
               %{diff_summary: %{code_changed: true, size_bucket: :small, model_tier: :standard}},
               nil,
               config,
               []
             )
  end
end
