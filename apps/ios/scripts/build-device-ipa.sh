#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/TestResults/device-install"
mkdir -p "$OUT"
xcodebuild -project "$ROOT/ZeroRed.xcodeproj" -scheme ZeroRed -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$OUT/build.log" 2>&1
STAGE="$(mktemp -d "$OUT/package.XXXXXX")"
mkdir "$STAGE/Payload"
ditto "$OUT/DerivedData/Build/Products/Release-iphoneos/ZeroRed.app" "$STAGE/Payload/ZeroRed.app"
(cd "$STAGE" && /usr/bin/zip -qry "$OUT/ZeroRed-unsigned.ipa" Payload)
shasum -a 256 "$OUT/ZeroRed-unsigned.ipa" > "$OUT/ZeroRed-unsigned.sha256"
echo "$OUT/ZeroRed-unsigned.ipa"