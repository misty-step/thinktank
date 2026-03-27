defmodule Thinktank.StageRegistryTest do
  use ExUnit.Case, async: true

  alias Thinktank.StageRegistry

  test "aggregates critical and low-confidence reviewer verdicts correctly" do
    assert StageRegistry.aggregate_review_verdict([]).verdict == "SKIP"

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
           ]).verdict == "PASS"

    assert StageRegistry.aggregate_review_verdict([
             %{status: :ok, verdict: %{verdict: "WARN", confidence: 0.9, findings: []}}
           ]).verdict == "WARN"
  end

  test "fails review aggregation when no valid reviewer verdicts remain" do
    verdict =
      StageRegistry.aggregate_review_verdict([
        %{status: :parse_error, error: :bad_json},
        %{status: :runtime_error, error: %{category: :timeout}}
      ])

    assert verdict.verdict == "FAIL"
    assert verdict.reviewers == 0
    assert verdict.failing_reviewers == 2
  end
end
