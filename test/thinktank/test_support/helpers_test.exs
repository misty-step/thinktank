defmodule Thinktank.TestSupport.HelpersTest do
  use ExUnit.Case, async: false

  alias Thinktank.Test.FakePi
  alias Thinktank.Test.Workspace

  setup do
    host_path = System.get_env("PATH")
    host_mode = System.get_env("THINKTANK_TEST_PI_MODE")

    on_exit(fn ->
      restore_env("PATH", host_path)
      restore_env("THINKTANK_TEST_PI_MODE", host_mode)
    end)

    :ok
  end

  test "with_fake_pi handles an unset PATH without introducing an empty segment" do
    System.delete_env("PATH")
    System.delete_env("THINKTANK_TEST_PI_MODE")

    FakePi.with_fake_pi("success", fn env ->
      assert env.mode == "success"
      assert System.get_env("PATH") == env.path
      refute String.contains?(env.path, ":")
      assert File.exists?(Path.join(env.path, "pi"))
      assert File.regular?(Path.join(env.path, "pi"))

      env_list = FakePi.subprocess_env(env, [{"EXTRA", "1"}])

      assert Enum.take(env_list, 7) == [
               {"PATH", env.path},
               {"THINKTANK_TEST_PI_MODE", "success"},
               {"OPENROUTER_API_KEY", ""},
               {"THINKTANK_OPENROUTER_API_KEY", ""},
               {"THINKTANK_DISABLE_MUONTRAP", "1"},
               {"MIX_ENV", nil},
               {"HOME", System.get_env("HOME") || ""}
             ]

      assert List.last(env_list) == {"EXTRA", "1"}
    end)
  end

  test "with_fake_pi prepends an existing PATH and workspace bootstrapping initializes git" do
    System.put_env("PATH", "/usr/bin")
    System.put_env("THINKTANK_TEST_PI_MODE", "existing")

    FakePi.with_fake_pi("degraded", fn env ->
      assert String.ends_with?(env.path, ":/usr/bin")
      assert System.get_env("THINKTANK_TEST_PI_MODE") == "degraded"

      path_entries =
        env
        |> FakePi.subprocess_env([{"PATH", "/override"}])
        |> Enum.filter(&(elem(&1, 0) == "PATH"))
        |> Enum.map(&elem(&1, 1))

      assert path_entries == [env.path, "/override"]
    end)

    workspace = Workspace.unique_tmp_dir("thinktank-workspace-helper")
    assert Workspace.init_git_repo!(workspace) == :ok
    assert File.dir?(Path.join(workspace, ".git"))

    {sha, 0} =
      System.cmd("git", ["rev-parse", "HEAD"],
        cd: workspace,
        stderr_to_stdout: true,
        env: [{"LEFTHOOK", "0"}]
      )

    assert String.trim(sha) =~ ~r/^[0-9a-f]{40}$/
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
