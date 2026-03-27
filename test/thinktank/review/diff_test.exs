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
end
