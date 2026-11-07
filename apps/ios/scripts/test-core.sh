#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-swift}"
TASK_CACHE="${ZERO_RED_TEST_CACHE:-${TMPDIR:-/tmp}/zero-red-test-cache}"
mkdir -p "$TASK_CACHE"
export XDG_CACHE_HOME="$TASK_CACHE"
export CLANG_MODULE_CACHE_PATH="$TASK_CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_CACHE/modules"
python3 "$TASK_ROOT/scripts/verify_project.py"
python3 "$TASK_ROOT/scripts/fixture_server.py" --port 8765 > "$TASK_CACHE/fixture.log" 2>&1 &
TASK_SERVER_PID=$!
trap 'kill "$TASK_SERVER_PID" 2>/dev/null || true' EXIT
python3 - "$TASK_SERVER_PID" <<'PY'
import os,sys,time,urllib.request
pid=int(sys.argv[1])
for attempt in range(50):
    os.kill(pid,0)
    try:
        with urllib.request.urlopen("http://127.0.0.1:8765/sample.mp4",timeout=1) as response:
            assert response.status == 200
        break
    except OSError: time.sleep(0.1)
else: raise SystemExit("Fixture server did not become ready; inspect fixture.log")
PY
export ZERO_RED_FIXTURE_URL=http://127.0.0.1:8765
"$SWIFT_BIN" test --package-path "$TASK_ROOT" --scratch-path "$TASK_CACHE/build" --cache-path "$TASK_CACHE/swiftpm" --config-path "$TASK_CACHE/config" --security-path "$TASK_CACHE/security" -Xswiftc -warnings-as-errors
