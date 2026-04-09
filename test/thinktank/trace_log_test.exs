defmodule Thinktank.TraceLogTest do
  use ExUnit.Case, async: false
  import Bitwise
  import ExUnit.CaptureLog

  alias Thinktank.TraceLog

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp read_jsonl(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

  defp with_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      if is_nil(previous) do
        System.delete_env(name)
      else
        System.put_env(name, previous)
      end
    end
  end

  test "complete_run is best effort when the summary is corrupted" do
    output_dir = Path.join(unique_tmp_dir("thinktank-trace-log"), "run")
    TraceLog.init_run(output_dir, %{"bench" => "review/default"})
    File.write!(Path.join(output_dir, "trace/summary.json"), "{not-json")

    log =
      capture_log(fn ->
        assert :ok == TraceLog.complete_run(output_dir, %{"status" => "complete"})
      end)

    assert log =~ "trace log complete_run failed"

    summary = read_json(Path.join(output_dir, "trace/summary.json"))
    assert summary["dropped_events"] == 1
    assert summary["last_trace_error"]["operation"] == "complete_run"
  end

  test "global mirrored logs are written with private permissions" do
    output_dir = Path.join(unique_tmp_dir("thinktank-trace-log-run"), "run")
    log_dir = unique_tmp_dir("thinktank-trace-log-global")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")
    System.put_env("THINKTANK_LOG_DIR", log_dir)

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end
    end)

    TraceLog.record_event(output_dir, "run_started", %{"bench" => "review/default"})

    [global_log] = Path.wildcard(Path.join(log_dir, "*.jsonl"))

    assert (File.stat!(log_dir).mode &&& 0o777) == 0o700
    assert (File.stat!(global_log).mode &&& 0o777) == 0o600
  end

  test "global mirror can be disabled with THINKTANK_LOG_DIR=off" do
    output_dir = Path.join(unique_tmp_dir("thinktank-trace-log-off"), "run")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")
    System.put_env("THINKTANK_LOG_DIR", "off")

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end
    end)

    TraceLog.record_event(output_dir, "run_started", %{"bench" => "review/default"})

    assert File.exists?(Path.join(output_dir, "trace/events.jsonl"))

    assert [] ==
             Path.wildcard(Path.join(output_dir, "**/*.jsonl")) --
               [Path.join(output_dir, "trace/events.jsonl")]
  end

  test "default global log path falls back to XDG_STATE_HOME when THINKTANK_LOG_DIR is unset" do
    output_dir = Path.join(unique_tmp_dir("thinktank-trace-log-default"), "run")
    xdg_state_home = unique_tmp_dir("thinktank-trace-log-xdg")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")
    previous_xdg = System.get_env("XDG_STATE_HOME")
    System.delete_env("THINKTANK_LOG_DIR")
    System.put_env("XDG_STATE_HOME", xdg_state_home)

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end

      if is_nil(previous_xdg) do
        System.delete_env("XDG_STATE_HOME")
      else
        System.put_env("XDG_STATE_HOME", previous_xdg)
      end
    end)

    TraceLog.record_event(output_dir, "run_started", %{"bench" => "review/default"})

    [global_log] = Path.wildcard(Path.join(xdg_state_home, "thinktank/logs/*.jsonl"))
    assert File.exists?(global_log)
  end

  test "global-only events do not require per-run trace initialization" do
    log_dir = unique_tmp_dir("thinktank-trace-log-global-only")
    output_dir = Path.join(unique_tmp_dir("thinktank-trace-log-missing-run"), "run")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")
    System.put_env("THINKTANK_LOG_DIR", log_dir)

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end
    end)

    TraceLog.record_global_event("bootstrap_failed", %{
      "bench" => "research/quick",
      "output_dir" => output_dir,
      "error" => %{"message" => "no space left on device"}
    })

    [global_log] = Path.wildcard(Path.join(log_dir, "*.jsonl"))
    [event] = read_jsonl(global_log)

    assert event["event"] == "bootstrap_failed"
    assert event["run_id"] == "run"
    assert event["output_dir"] == Path.expand(output_dir)
    refute File.exists?(Path.join(output_dir, "trace/events.jsonl"))
  end

  test "global-only events normalize timestamp fallbacks and opaque values" do
    log_dir = unique_tmp_dir("thinktank-trace-log-fallbacks")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")
    System.put_env("THINKTANK_LOG_DIR", log_dir)
    today = Date.utc_today()

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end
    end)

    TraceLog.record_global_event("bootstrap_failed", %{
      "timestamp" => "not-a-timestamp",
      "date" => today,
      "opaque" => {:slow, 120},
      "signal" => :sigterm,
      "steps" => [%{"name" => :capture}, :done]
    })

    [global_log] = Path.wildcard(Path.join(log_dir, "*.jsonl"))
    [event] = read_jsonl(global_log)

    assert Path.basename(global_log) == "#{Date.to_iso8601(today)}.jsonl"
    assert event["date"]["year"] == today.year
    assert event["opaque"] == "{:slow, 120}"
    assert event["signal"] == "sigterm"
    assert event["steps"] == [%{"name" => "capture"}, "done"]
    refute Map.has_key?(event, "run_id")
  end

  test "record_event degrades when a live lock holder exceeds the timeout" do
    output_dir = Path.join(unique_tmp_dir("thinktank-trace-log-lock-timeout"), "run")
    TraceLog.init_run(output_dir, %{"bench" => "review/default"})

    owner =
      spawn(fn ->
        Process.sleep(:timer.seconds(5))
      end)

    on_exit(fn ->
      Process.exit(owner, :kill)
    end)

    events_path = Path.join(output_dir, TraceLog.events_file())
    lock_key = {Thinktank.TraceLog, Path.expand(events_path)}

    case :ets.whereis(:thinktank_trace_log_locks) do
      :undefined ->
        :ets.new(:thinktank_trace_log_locks, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end

    :ets.insert(:thinktank_trace_log_locks, {lock_key, owner})

    log =
      capture_log(fn ->
        with_env("THINKTANK_TRACE_LOCK_TIMEOUT_MS", "10", fn ->
          assert :ok ==
                   TraceLog.record_event(output_dir, "run_completed", %{"status" => "complete"})
        end)
      end)

    summary = read_json(Path.join(output_dir, "trace/summary.json"))

    assert log =~ "trace log record_event failed"
    assert summary["dropped_events"] == 1
    assert summary["last_trace_error"]["operation"] == "record_event"
    refute Enum.any?(read_jsonl(events_path), &(&1["event"] == "run_completed"))
  end
end
