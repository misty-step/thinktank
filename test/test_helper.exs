System.put_env("THINKTANK_DISABLE_MUONTRAP", "1")

System.put_env(
  "THINKTANK_LOG_DIR",
  Path.join(System.tmp_dir!(), "thinktank-test-logs-#{System.unique_integer([:positive])}")
)

ExUnit.start()
