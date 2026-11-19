#!/bin/bash
# zero red 真机 IPA 打包：只在 macOS 运行器执行，产物写入 build/ipa。
# 校验真实产物而不是信任构建成功：App 目录、平台、架构、最低系统与未签名状态都从 IPA 内部读取。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in xcodebuild xcrun python3 ditto plutil; do
    command -v "$tool" >/dev/null || { echo "缺少工具: $tool" >&2; exit 1; }
done
mkdir -p build/ipa
build_id=$(date -u +%Y%m%dT%H%M%SZ)
derived="$ROOT/build/DeviceDerivedData"
xcodebuild -project apps/ios/ZeroRed.xcodeproj -scheme ZeroRed -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO ENABLE_DEBUG_DYLIB=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
    build 2>&1 | tee build/ipa/build.log
app="$derived/Build/Products/Release-iphoneos/ZeroRed.app"
test -d "$app" || { echo '未找到真机 App 产物' >&2; exit 1; }
stage=$(mktemp -d "$ROOT/build/ipa-stage.XXXXXX")
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/ZeroRed.app"
# 转成 XML plist，Windows 交付脚本才能直接读取真实 IPA 内的 Info.plist。
plutil -convert xml1 "$stage/Payload/ZeroRed.app/Info.plist"
python3 - "$stage/Payload/ZeroRed.app" "$ROOT/build/ipa" "$build_id" "$ROOT/apps/ios/ZeroRed.xcodeproj/project.pbxproj" <<'PY'
import hashlib, json, pathlib, plistlib, re, subprocess, sys, zipfile

app, output, build_id = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
project = pathlib.Path(sys.argv[4]).read_text(encoding='utf-8')
bundle_match = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', project)
min_os_match = re.search(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9]+(?:\.[0-9]+)+);', project)
assert bundle_match, 'project.pbxproj 缺少 PRODUCT_BUNDLE_IDENTIFIER'
assert min_os_match, 'project.pbxproj 缺少 IPHONEOS_DEPLOYMENT_TARGET'
expected_bundle, expected_min_os = bundle_match.group(1).strip(), min_os_match.group(1)

info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == expected_bundle, info['CFBundleIdentifier']
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], '不能打包模拟器 App'
assert info['MinimumOSVersion'] == expected_min_os, f"最低系统 {info['MinimumOSVersion']} 与工程 {expected_min_os} 不一致"
assert info['UIDeviceFamily'] == [1], '必须是 iPhone 应用'
assert not (app / 'embedded.mobileprovision').exists(), '未签名包不应带描述文件'
assert not (app / '_CodeSignature').exists(), '未签名包不应带签名目录'
assert not (app / 'PlugIns').exists(), '本安装流程只支持单一 App，不应包含扩展'

executable = app / info['CFBundleExecutable']
archs = subprocess.check_output(['xcrun', 'lipo', '-archs', str(executable)], text=True).strip()
assert archs == 'arm64', f'真机可执行文件架构异常: {archs}'
build_version = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(executable)], text=True)
assert 'platform IOS\n' in build_version, build_version

version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', version), f'版本号异常: {version}'
assert build.isdigit(), f'构建号异常: {build}'
name = f'ZeroRed-{version}-{build}-{build_id}-unsigned.ipa'
ipa = output / name
assert not ipa.exists(), '同名构建已经存在，请稍后重试'
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app.parent), str(ipa)], check=True)
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert 'Payload/ZeroRed.app/Info.plist' in names
    assert f"Payload/ZeroRed.app/{info['CFBundleExecutable']}" in names, names

metadata = dict(
    fileName=name, sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
    sizeBytes=ipa.stat().st_size, version=version, build=build, buildID=build_id,
    bundleIdentifier=info['CFBundleIdentifier'], executable=info['CFBundleExecutable'],
    appDirectory='Payload/ZeroRed.app', minimumOSVersion=info['MinimumOSVersion'],
    architecture='arm64', platform='iPhoneOS', signingState='unsigned-needs-resigning')
payload = json.dumps(metadata, ensure_ascii=False, indent=2) + '\n'
(output / (name + '.json')).write_text(payload, encoding='utf-8')
(output / (name + '.sha256')).write_text(metadata['sha256'] + '  ' + name + '\n', encoding='utf-8')
(output / 'latest.json').write_text(payload, encoding='utf-8')
print(payload)
PY
rm -rf "$stage"