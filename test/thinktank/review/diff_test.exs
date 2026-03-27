defmodule Thinktank.Review.DiffTest do
  use ExUnit.Case, async: true

  alias Thinktank.Review.Diff

  test "classifies changed files and model tier from diff content" do
    diff = """
    diff --git a/lib/auth_thing.ex b/lib/auth_thing.ex
    index 1111111..2222222 100644
    --- a/lib/auth_thing.ex
    +++ b/lib/auth_thing.ex
    @@ -1,1 +1,2 @@
    -def ok, do: :ok
    +def ok, do: :ok
    +System.put_env("SECRET", "1")
    diff --git a/test/thing_test.exs b/test/thing_test.exs
    index 1111111..2222222 100644
    --- a/test/thing_test.exs
    +++ b/test/thing_test.exs
    @@ -1,1 +1,1 @@
    -assert true
    +assert true
    """

    summary = Diff.parse(diff)

    assert summary.code_changed
    assert summary.security_hint
    assert summary.size_bucket in [:small, :medium, :large, :xlarge]
    assert summary.model_tier in [:standard, :pro]
  end

  test "classifies doc, test, and code paths explicitly" do
    assert Diff.classify_file("README.md") == {true, false, false}
    assert Diff.classify_file("test/thing_test.exs") == {false, true, false}
    assert Diff.classify_file("lib/thing.ex") == {false, false, true}
  end

  test "classifies size bucket boundaries" do
    assert Diff.classify_size(%{total_changed_lines: 50}) == :small
    assert Diff.classify_size(%{total_changed_lines: 51}) == :medium
    assert Diff.classify_size(%{total_changed_lines: 200}) == :medium
    assert Diff.classify_size(%{total_changed_lines: 201}) == :large
    assert Diff.classify_size(%{total_changed_lines: 501}) == :xlarge
  end

  test "classifies flash and pro review tiers" do
    assert Diff.classify_model_tier(%{
             total_changed_lines: 10,
             code_files: 0,
             test_files: 1,
             doc_files: 0,
             security_hint: false
           }) == :flash

    assert Diff.classify_model_tier(%{
             total_changed_lines: 10,
             code_files: 1,
             test_files: 0,
             doc_files: 0,
             security_hint: true
           }) == :pro
  end
end
