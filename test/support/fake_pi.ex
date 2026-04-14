defmodule Thinktank.Test.FakePi do
  @moduledoc """
  Test helper that installs a fake `pi` binary on `PATH` and returns the
  resolved environment for hermetic subprocess invocations.

  Modes:
    * `"success"`  — every prompt yields a stub response.
    * `"degraded"` — `systems-*` prompts succeed, all others exit non-zero.
    * `"fail"`     — every prompt exits non-zero.

  When called inside an ExUnit test, mutations to `PATH` /
  `THINKTANK_TEST_PI_MODE` are restored via `on_exit/1`. The callback
  receives an `env` map describing the fake shim's `PATH` and mode, so
  callers that need to launch external subprocesses (e.g. the built
  escript) can thread the same configuration into `System.cmd/3` or
  `Port.open/2` via `subprocess_env/2`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @type mode :: String.t()
  @type env :: %{
          required(:mode) => mode(),
          required(:path) => String.t()
        }

  @spec with_fake_pi(mode(), (env() -> any())) :: any()
  def with_fake_pi(mode, fun) when is_binary(mode) and is_function(fun, 1) do
    tmp = unique_tmp_dir("thinktank-fake-pi")
    pi_path = Path.join(tmp, "pi")

    File.write!(pi_path, script())
    File.chmod!(pi_path, 0o755)

    original_path = System.get_env("PATH")
    original_mode = System.get_env("THINKTANK_TEST_PI_MODE")
    new_path = "#{tmp}:#{original_path}"
    System.put_env("PATH", new_path)
    System.put_env("THINKTANK_TEST_PI_MODE", mode)

    on_exit(fn ->
      System.put_env("PATH", original_path || "")

      if is_nil(original_mode) do
        System.delete_env("THINKTANK_TEST_PI_MODE")
      else
        System.put_env("THINKTANK_TEST_PI_MODE", original_mode)
      end
    end)

    fun.(%{mode: mode, path: new_path})
  end

  @doc """
  Assemble a hermetic env list for `System.cmd/3` or `Port.open/2`.

  Given the env map yielded by `with_fake_pi/2`, returns a list of
  `{name, value}` tuples that:

    * puts the fake `pi` shim first on `PATH`,
    * propagates the selected `THINKTANK_TEST_PI_MODE`,
    * disables MuonTrap so the subprocess can run without a port wrapper,
    * clears `MIX_ENV` so the escript does not inherit a dev/test env,
    * scrubs every OpenRouter API-key variable (defense in depth: both
      `OPENROUTER_API_KEY` and `THINKTANK_OPENROUTER_API_KEY` must be
      empty so a live network call cannot be made even if one name is
      missed elsewhere),
    * passes through `HOME` so `Path.expand/1` and similar resolve.

  Callers can pass `extra` entries to append or override values.
  """
  @spec subprocess_env(env(), [{String.t(), String.t() | nil}]) ::
          [{String.t(), String.t() | nil}]
  def subprocess_env(env, extra \\ []) when is_map(env) and is_list(extra) do
    base = [
      {"PATH", env.path},
      {"THINKTANK_TEST_PI_MODE", env.mode},
      {"OPENROUTER_API_KEY", ""},
      {"THINKTANK_OPENROUTER_API_KEY", ""},
      {"THINKTANK_DISABLE_MUONTRAP", "1"},
      {"MIX_ENV", nil},
      {"HOME", System.get_env("HOME") || ""}
    ]

    base ++ extra
  end

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp script do
    """
    #!/bin/sh
    mode="${THINKTANK_TEST_PI_MODE:-success}"
    prev=""
    prompt_file=""

    for arg in "$@"; do
      if [ "$prev" = "-p" ]; then
        prompt_file="$arg"
        break
      fi

      prev="$arg"
    done

    prompt_name="$(basename "${prompt_file#@}" .md)"
    prompt="$(cat "${prompt_file#@}")"

    if [ "$mode" = "fail" ]; then
      echo "simulated failure"
      exit 1
    fi

    if [ "$mode" = "degraded" ]; then
      case "$prompt_name" in
        systems-*)
          echo "Raw agent output"
          exit 0
          ;;
        *)
          echo "simulated failure"
          exit 1
          ;;
      esac
    fi

    case "$prompt_name" in
      marshal-*)
      printf '%s\\n' \\
        '{"summary":"Planner summary.",' \\
        '"selected_agents":[{"name":"trace","brief":"Check correctness."}],' \\
        '"synthesis_brief":"Use grounded evidence."}'
      ;;
      review-synth-*|research-synth-*)
      echo "Synthesized summary"
      ;;
      *)
      echo "Raw agent output"
      ;;
    esac
    """
  end
end
