defmodule Thinktank.Research.FindingsTest do
  use ExUnit.Case, async: true

  alias Thinktank.Research.Findings

  test "parses a valid payload and normalizes confidences" do
    output =
      Jason.encode!(%{
        thesis: "  The launcher boundary is already thin.  ",
        findings: [
          %{
            claim: "  Artifacts are persisted through RunStore.  ",
            evidence: [" lib/thinktank/run_store.ex "],
            confidence: " HIGH "
          }
        ],
        evidence: [
          %{
            source: " lib/thinktank/run_store.ex ",
            summary: " RunStore records findings artifacts. "
          }
        ],
        open_questions: [" Should downstream tools consume findings directly? "],
        confidence: " Medium "
      })

    findings = Findings.from_synthesis_output(output)

    assert findings["status"] == "complete"
    assert findings["thesis"] == "The launcher boundary is already thin."
    assert findings["confidence"] == "medium"
    assert hd(findings["findings"])["claim"] == "Artifacts are persisted through RunStore."
    assert hd(findings["findings"])["evidence"] == ["lib/thinktank/run_store.ex"]
    assert hd(findings["findings"])["confidence"] == "high"
  end

  test "returns invalid artifact for invalid json" do
    findings = Findings.from_synthesis_output("not json")

    assert findings["status"] == "invalid"
    assert findings["error"]["category"] == "invalid_json"
  end

  test "returns invalid artifact for invalid shape" do
    output =
      Jason.encode!(%{
        thesis: "Missing required list fields.",
        confidence: "high"
      })

    findings = Findings.from_synthesis_output(output)

    assert findings["status"] == "invalid"
    assert findings["error"]["category"] == "invalid_shape"
  end

  test "returns invalid artifact when a finding is missing confidence" do
    output =
      Jason.encode!(%{
        thesis: "Missing per-finding confidence should fail.",
        findings: [
          %{
            claim: "A claim",
            evidence: ["source"]
          }
        ],
        evidence: [
          %{
            source: "source",
            summary: "summary"
          }
        ],
        open_questions: [],
        confidence: "high"
      })

    findings = Findings.from_synthesis_output(output)

    assert findings["status"] == "invalid"
    assert findings["error"]["category"] == "invalid_shape"
  end

  test "returns invalid artifact when a finding has invalid confidence" do
    output =
      Jason.encode!(%{
        thesis: "Invalid per-finding confidence should fail.",
        findings: [
          %{
            claim: "A claim",
            evidence: ["source"],
            confidence: "certainly"
          }
        ],
        evidence: [
          %{
            source: "source",
            summary: "summary"
          }
        ],
        open_questions: [],
        confidence: "high"
      })

    findings = Findings.from_synthesis_output(output)

    assert findings["status"] == "invalid"
    assert findings["error"]["category"] == "invalid_shape"
  end

  test "renders markdown for complete findings" do
    markdown =
      Findings.to_markdown(%{
        "status" => "complete",
        "thesis" => "The launcher is thin.",
        "findings" => [
          %{
            "claim" => "RunStore records artifacts.",
            "evidence" => ["lib/thinktank/run_store.ex"],
            "confidence" => "high"
          }
        ],
        "evidence" => [
          %{
            "source" => "lib/thinktank/run_store.ex",
            "summary" => "Artifact writes are centralized."
          }
        ],
        "open_questions" => ["Should this flow expose stronger contracts?"],
        "confidence" => "high"
      })

    assert markdown =~ "# Research Synthesis"
    assert markdown =~ "RunStore records artifacts."
    assert markdown =~ "Evidence: lib/thinktank/run_store.ex."
    assert markdown =~ "Confidence: high"
  end

  test "renders empty sections with explicit placeholders" do
    markdown =
      Findings.to_markdown(%{
        "status" => "complete",
        "thesis" => "No findings yet.",
        "findings" => [],
        "evidence" => [],
        "open_questions" => [],
        "confidence" => "unknown"
      })

    assert markdown =~ "_No findings were returned._"
    assert markdown =~ "_No evidence was returned._"
    assert markdown =~ "_No open questions._"
  end
end
