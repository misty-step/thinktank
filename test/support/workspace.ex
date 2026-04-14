defmodule Thinktank.Test.Workspace do
  @moduledoc """
  Shared workspace helpers for integration and e2e tests: hermetic tmp
  directories and minimal git bootstrapping.

  `unique_tmp_dir/1` registers an `on_exit/1` callback to remove the
  directory at the end of the test so workspaces do not accumulate under
  `System.tmp_dir!/0`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @spec unique_tmp_dir(String.t()) :: String.t()
  def unique_tmp_dir(prefix) when is_binary(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  @spec git!(String.t(), [String.t()]) :: :ok
  def git!(cwd, args) when is_binary(cwd) and is_list(args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true, env: [{"LEFTHOOK", "0"}]) do
      {_output, 0} ->
        :ok

      {output, status} ->
        ExUnit.Assertions.flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  @spec init_git_repo!(String.t()) :: :ok
  def init_git_repo!(cwd) when is_binary(cwd) do
    git!(cwd, ["init"])
    git!(cwd, ["config", "user.email", "thinktank@example.com"])
    git!(cwd, ["config", "user.name", "ThinkTank Test"])
    File.write!(Path.join(cwd, ".gitkeep"), "")
    git!(cwd, ["add", "."])
    git!(cwd, ["commit", "-m", "initial"])
    :ok
  end
end
