defmodule Thinktank.Review.ContextTest do
  use ExUnit.Case, async: true

  alias Thinktank.Review.Context

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true, env: [{"LEFTHOOK", "0"}]) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  test "returns an unavailable context outside a git repository" do
    cwd = unique_tmp_dir("thinktank-review-context-non-git")
    context = Context.capture(cwd, %{})

    assert get_in(context, ["git", "available"]) == false
    assert get_in(context, ["change", "file_count"]) == 0
  end

  test "captures changed files and signals inside a git repository" do
    cwd = unique_tmp_dir("thinktank-review-context-git")
    git!(cwd, ["init"])
    git!(cwd, ["config", "user.email", "thinktank@example.com"])
    git!(cwd, ["config", "user.name", "ThinkTank Test"])

    File.mkdir_p!(Path.join(cwd, "lib"))
    File.write!(Path.join(cwd, "lib/demo.ex"), "defmodule Demo do\n  def run, do: :ok\nend\n")
    git!(cwd, ["add", "."])
    git!(cwd, ["commit", "-m", "initial"])

    File.write!(
      Path.join(cwd, "lib/demo.ex"),
      "defmodule Demo do\n  def run, do: :updated\nend\n"
    )

    context = Context.capture(cwd, %{})

    assert get_in(context, ["git", "available"]) == true
    assert get_in(context, ["change", "file_count"]) >= 1
    assert get_in(context, ["change", "signals", "touches_code"]) == true
  end
end
