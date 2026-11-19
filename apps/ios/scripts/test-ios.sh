#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS tests require macOS, full Xcode, and an installed iPhone simulator runtime.' >&2
  exit 2
fi
if ! command -v xcodebuild >/dev/null; then
  echo 'Install Xcode and select it in Xcode > Settings > Locations > Command Line Tools.' >&2
  exit 2
fi
if [[ -z "${IOS_SIMULATOR_ID:-}" ]]; then
  echo 'Set IOS_SIMULATOR_ID to an installed iPhone simulator UDID from: xcrun simctl list devices available' >&2
  exit 2
fi
TASK_RESULTS="${ZERO_RED_IOS_RESULTS:-$TASK_ROOT/TestResults/ios-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$TASK_RESULTS"
python3 "$TASK_ROOT/scripts/verify_project.py"
python3 "$TASK_ROOT/scripts/fixture_server.py" > "$TASK_RESULTS/fixture.log" 2>&1 &
TASK_SERVER_PID=$!
trap 'kill "$TASK_SERVER_PID" 2>/dev/null || true' EXIT
python3 - "$TASK_SERVER_PID" <<'PY'
import os,sys,time,urllib.request
for attempt in range(50):
    os.kill(int(sys.argv[1]),0)
    try:
        with urllib.request.urlopen("http://localhost:8765/sample.mp4",timeout=1) as r: assert r.status == 200
        break
    except OSError: time.sleep(0.1)
else: raise SystemExit("Fixture server did not become ready")
PY
xcodebuild -version > "$TASK_RESULTS/xcode-version.txt"
xcrun simctl list runtimes > "$TASK_RESULTS/simulator-runtimes.txt"
# ONLY_TESTING 只跑指定用例（空格分隔的用例名），用于云端单独取视觉验收截图；
# 默认跑完整 ZeroRedUITests。
ONLY_FLAGS=""
if [[ -n "${ONLY_TESTING:-}" ]]; then
  for name in $ONLY_TESTING; do ONLY_FLAGS="$ONLY_FLAGS -only-testing:ZeroRedUITests/ZeroRedUITests/$name"; done
fi
xcodebuild -project "$TASK_ROOT/ZeroRed.xcodeproj" -scheme ZeroRed -configuration Debug -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" -derivedDataPath "$TASK_RESULTS/DerivedData" -resultBundlePath "$TASK_RESULTS/UITests.xcresult" CODE_SIGNING_ALLOWED=NO test $ONLY_FLAGS 2>&1 | tee "$TASK_RESULTS/xcodebuild.log"
xcodebuild -project "$TASK_ROOT/ZeroRed.xcodeproj" -scheme ZeroRed -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "$TASK_RESULTS/ReleaseDerivedData" CODE_SIGNING_ALLOWED=NO build analyze 2>&1 | tee "$TASK_RESULTS/release-analyze.log"
