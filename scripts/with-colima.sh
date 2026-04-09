#!/usr/bin/env bash
set -euo pipefail

PROFILE="${THINKTANK_COLIMA_PROFILE:-default}"
SOCKET_PATH="${HOME}/.colima/${PROFILE}/docker.sock"

require_command() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    echo "thinktank: ${name} is required for the Colima local runtime." >&2
    exit 1
  fi
}

docker_cli_healthcheck() {
  python3 - <<'PY'
import subprocess
import sys

try:
    subprocess.run(
        ["docker", "version", "--format", "{{json .Client.Version}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
        check=True,
    )
except Exception:
    sys.exit(1)

sys.exit(0)
PY
}

require_command python3
require_command colima
require_command docker
require_command curl

docker_path="$(command -v docker)"
docker_realpath="$(python3 - <<'PY' "$docker_path"
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
)"

if [[ "$docker_realpath" == /Applications/Docker.app/* ]]; then
  echo "thinktank: docker CLI still points at Docker Desktop (${docker_realpath})." >&2
  echo "thinktank: Colima migration expects a standalone docker client, e.g. \`brew install docker\`." >&2
  exit 1
fi

if ! docker_cli_healthcheck; then
  echo "thinktank: docker CLI is not healthy enough for Colima-backed Dagger." >&2
  echo "thinktank: verify the standalone docker client works before retrying." >&2
  exit 1
fi

if ! colima status "$PROFILE" >/dev/null 2>&1; then
  echo "thinktank: Colima profile '${PROFILE}' is not running." >&2
  echo "thinktank: start it with \`colima start ${PROFILE}\` and retry." >&2
  exit 1
fi

if [ ! -S "$SOCKET_PATH" ]; then
  echo "thinktank: Colima docker socket not found at ${SOCKET_PATH}." >&2
  exit 1
fi

if ! curl --silent --show-error --max-time 2 --unix-socket "$SOCKET_PATH" http://localhost/_ping >/dev/null; then
  echo "thinktank: Colima docker socket at ${SOCKET_PATH} is not responding." >&2
  exit 1
fi

export DOCKER_HOST="unix://${SOCKET_PATH}"
unset DOCKER_CONTEXT
unset DOCKER_TLS_VERIFY
unset DOCKER_CERT_PATH

exec "$@"
