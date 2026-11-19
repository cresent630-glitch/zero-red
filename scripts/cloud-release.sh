#!/bin/bash
# zero red 模拟器 Release 编译与静态分析：只在 macOS 运行器执行。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ "$(uname -s)" = Darwin ] || { echo '需要 macOS 与完整 Xcode。' >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo '未找到 xcodebuild。' >&2; exit 2; }
mkdir -p build
xcodebuild -project apps/ios/ZeroRed.xcodeproj -scheme ZeroRed -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$ROOT/build/SimulatorDerivedData" \
    CODE_SIGNING_ALLOWED=NO build analyze 2>&1 | tee build/simulator-release.log