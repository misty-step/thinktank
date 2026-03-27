defmodule Thinktank.Review.VerdictTest do
  use ExUnit.Case, async: true

  alias Thinktank.Review.Verdict

  test "parses markdown fallback reviewer output" do
    text = """
    **Reviewer:** proof
    **Perspective:** testing
    **Verdict:** WARN
    **Confidence:** 0.9
    **Summary:** Coverage gaps remain.

    | Severity | Category | Title | Description | Suggestion | File | Line |
    |----------|----------|-------|-------------|------------|------|------|
    | major | testing | Missing test | Add a test | Write one | `lib/app.ex` | 12 |

    **Stats:**
    ```json
    {"files_reviewed":1,"files_with_issues":1,"critical":0,"major":1,"minor":0,"info":0}
    ```
    """

    assert {:ok, verdict} = Verdict.parse(text)
    assert verdict.reviewer == "proof"

    assert verdict.findings == [
             %{
               severity: "major",
               category: "testing",
               title: "Missing test",
               description: "Add a test",
               suggestion: "Write one",
               file: "lib/app.ex",
               line: 12
             }
           ]
  end

  test "rejects invalid confidence and severity values" do
    assert {:error, :invalid_confidence} =
             Verdict.validate(%{
               "reviewer" => "proof",
               "perspective" => "testing",
               "verdict" => "WARN",
               "confidence" => 101,
               "summary" => "bad confidence",
               "findings" => [],
               "stats" => %{
                 "files_reviewed" => 1,
                 "files_with_issues" => 0,
                 "critical" => 0,
                 "major" => 0,
                 "minor" => 0,
                 "info" => 0
               }
             })

    assert {:error, {:invalid_severity, "severe"}} =
             Verdict.validate(%{
               "reviewer" => "proof",
               "perspective" => "testing",
               "verdict" => "WARN",
               "confidence" => 0.9,
               "summary" => "bad severity",
               "findings" => [
                 %{
                   "severity" => "severe",
                   "category" => "testing",
                   "title" => "bad",
                   "description" => "bad",
                   "suggestion" => "fix",
                   "file" => "lib/app.ex",
                   "line" => 1
                 }
               ],
               "stats" => %{
                 "files_reviewed" => 1,
                 "files_with_issues" => 1,
                 "critical" => 0,
                 "major" => 1,
                 "minor" => 0,
                 "info" => 0
               }
             })
  end

  test "rejects negative line numbers" do
    assert {:error, {:invalid_line, -1}} =
             Verdict.validate(%{
               "reviewer" => "proof",
               "perspective" => "testing",
               "verdict" => "WARN",
               "confidence" => 0.9,
               "summary" => "bad line",
               "findings" => [
                 %{
                   "severity" => "major",
                   "category" => "testing",
                   "title" => "bad",
                   "description" => "bad",
                   "suggestion" => "fix",
                   "file" => "lib/app.ex",
                   "line" => -1
                 }
               ],
               "stats" => %{
                 "files_reviewed" => 1,
                 "files_with_issues" => 1,
                 "critical" => 0,
                 "major" => 1,
                 "minor" => 0,
                 "info" => 0
               }
             })
  end
end
