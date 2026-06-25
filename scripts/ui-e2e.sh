#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-${NAMESPACE:-ontoportal}}"
RELEASE="${2:-${RELEASE:-ontoportal}}"
KUBECTL="${KUBECTL:-kubectl}"
UI_PORT="${UI_PORT:-13000}"
API_PORT="${API_PORT:-19393}"

cleanup() {
  for pid in ${PORT_FORWARD_PIDS:-}; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

wait_for_tcp() {
  local host="$1" port="$2" name="$3"
  python3 - "$host" "$port" "$name" <<'PY'
import socket
import sys
import time
host, port, name = sys.argv[1], int(sys.argv[2]), sys.argv[3]
deadline = time.time() + 90
last = None
while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=2):
            sys.exit(0)
    except OSError as exc:
        last = exc
        time.sleep(2)
print(f"ERROR: {name} did not open {host}:{port}: {last}", file=sys.stderr)
sys.exit(1)
PY
}

if [ -z "${UI_BASE_URL:-}" ]; then
  "$KUBECTL" -n "$NAMESPACE" port-forward "svc/${RELEASE}-ui" "${UI_PORT}:3000" >/tmp/ontoportal-ui-port-forward.log 2>&1 &
  PORT_FORWARD_PIDS="${PORT_FORWARD_PIDS:-} $!"
  export UI_BASE_URL="http://127.0.0.1:${UI_PORT}"
  wait_for_tcp 127.0.0.1 "$UI_PORT" ui
fi

if [ -z "${API_BASE_URL:-}" ]; then
  "$KUBECTL" -n "$NAMESPACE" port-forward "svc/${RELEASE}-api" "${API_PORT}:9393" >/tmp/ontoportal-api-port-forward.log 2>&1 &
  PORT_FORWARD_PIDS="${PORT_FORWARD_PIDS:-} $!"
  export API_BASE_URL="http://127.0.0.1:${API_PORT}"
  wait_for_tcp 127.0.0.1 "$API_PORT" api
fi

if [ ! -x node_modules/.bin/playwright ]; then
  echo "ERROR: Playwright is not installed. Run: npm install && npx playwright install chromium" >&2
  exit 127
fi

npm run test:ui -- "${@:3}"
