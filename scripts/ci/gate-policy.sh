#!/usr/bin/env bash

CI_POLICY_SYSTEM_CMD_PATTERN='System\.cmd\('
CI_POLICY_DYNAMIC_EXECUTION_API_PATTERN='Code\.(eval_|compile_)|:erlang\.binary_to_term\(|:os\.cmd\(|:erlang\.open_port\(|Port\.open\('
CI_POLICY_SHELL_SYSTEM_CMD_PATTERN='System\.cmd\("(/bin/)?(sh|bash)"'

CI_POLICY_SYSTEM_CMD_BOUNDARIES=(
  "lib/thinktank/executor/agentic.ex"
  "lib/thinktank/review/context.ex"
)

CI_POLICY_ACTIVE_BACKLOG_STATUSES=(
  "ready"
  "in-progress"
)

ci_policy_system_cmd_boundary_paths() {
  printf '%s\n' "${CI_POLICY_SYSTEM_CMD_BOUNDARIES[@]}"
}

ci_policy_is_active_backlog_status() {
  local candidate="$1"
  local status

  for status in "${CI_POLICY_ACTIVE_BACKLOG_STATUSES[@]}"; do
    if [[ "$candidate" == "$status" ]]; then
      return 0
    fi
  done

  return 1
}
