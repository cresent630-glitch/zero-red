#!/usr/bin/env python3
"""Prepare an isolated QA ledger, source manifest and fixtures; never reset App data."""
import argparse
from datetime import datetime, timezone
from functools import partial
import hashlib
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import threading
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / "apps/ios"
CASES = ROOT / "docs/ZERO_RED_TEST_CASES.md"


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def command(args, cwd=ROOT, timeout=120):
    try:
        done = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=timeout)
        return {"status": "PASS" if done.returncode == 0 else "FAIL",
                "exit_code": done.returncode, "command": args,
                "output": done.stdout + done.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"status": "BLOCKED", "command": args, "output": str(error)}


def case_records():
    records = []
    for line in CASES.read_text(encoding="utf-8").splitlines():
        if not re.match(r"\| ZR-[A-I]\d{2} \|", line):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != 6:
            raise ValueError("Invalid case row: " + line)
        case_id, priority, environment, precondition, steps, expected = cells
        records.append({"case_id": case_id, "priority": priority,
                        "environment_requirement": environment,
                        "precondition": precondition, "steps": steps, "expected": expected,
                        "status": "NOT_RUN", "app_build": "", "source_manifest": "source-manifest.json",
                        "device": "", "os_version": "", "network": "", "language": "",
                        "parameters": {}, "started_at": "", "finished_at": "", "tester": "",
                        "actual": "", "evidence": [], "defect_id": "", "notes": ""})
    if not records or len({r["case_id"] for r in records}) != len(records):
        raise ValueError("Missing or duplicate test cases")
    return records


def source_manifest():
    files = set()
    for directory in ["apps/ios/ZeroRed", "apps/ios/UITests", "apps/ios/Tests",
                      "apps/ios/scripts", "apps/ios/Fixtures", "apps/ios/Configuration",
                      "apps/ios/ZeroRed.xcodeproj", "apps/web/dist", "apps/web/tests"]:
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and not any(p in {"__pycache__", "xcuserdata"} for p in path.parts):
                files.add(path)
    for name in ["apps/ios/Package.swift", "apps/web/package.json", "project.json",
                 "docs/ZERO_RED_TEST_CASES.md", "docs/ZERO_RED_TEST_EXECUTION.md"]:
        files.add(ROOT / name)
    git = shutil.which("git")
    git_info = {}
    if git:
        for name, args in [("head", ["rev-parse", "HEAD"]), ("working_tree", ["status", "--short"])]:
            result = command([git, "-c", "safe.directory=" + ROOT.as_posix(), *args])
            git_info[name] = result["output"].strip()
    return {"root": str(ROOT), "git": git_info,
            "files": [{"path": p.relative_to(ROOT).as_posix(), "size": p.stat().st_size,
                       "sha256": digest(p)} for p in sorted(files)]}


def create_fixtures(folder, large):
    folder.mkdir()
    text = "# 阅读测试：开始\n\n首段哨兵 ZR-BEGIN，中文 English 123 😀。\n\n"
    text += "\n\n".join(f"## 第 {i} 节\n\n测试正文 ZR-SECTION-{i:03d}，用于目录、查找、滚动与进度。" for i in range(1, 101))
    text += "\n\n末段哨兵 ZR-END。\n"
    (folder / "reading-zh.md").write_text(text, encoding="utf-8")
    (folder / "reading-utf16.txt").write_text(text, encoding="utf-16")
    (folder / "reading.html").write_text('<!doctype html><meta charset="utf-8"><h1>HTML导入</h1><p>ZR-HTML-BEGIN</p><p>ZR-HTML-END</p>', encoding="utf-8")
    (folder / "captions.srt").write_text("1\n00:00:00,000 --> 00:00:01,000\n第一秒 ZR-CAPTION-1\n\n2\n00:00:01,000 --> 00:00:02,500\nSecond cue ZR-CAPTION-2\n", encoding="utf-8")
    (folder / "captions.vtt").write_text("WEBVTT\n\n00:00.000 --> 00:01.000\n第一秒 ZR-CAPTION-1\n\n00:01.000 --> 00:02.500\nSecond cue ZR-CAPTION-2\n", encoding="utf-8")
    (folder / "empty.txt").write_bytes(b"")
    (folder / "broken.docx").write_bytes(b"not a ZIP/DOCX file")
    (folder / "unsupported.doc").write_bytes(b"unsupported legacy .doc test placeholder")
    (folder / "broken-backup.json").write_text('{"version": 1, "documents": [', encoding="utf-8")
    for name in ["reading.pdf", "reading.docx"]:
        shutil.copyfile(ROOT / "apps/web/tests/fixtures" / name, folder / name)
    if large:
        for delta in [-1, 0, 1]:
            # Deterministic bytes, actual bytes written; no sparse-file assumptions.
            path = folder / f"size-20MiB{delta:+d}.txt"
            remaining = 20 * 1024 * 1024 + delta
            with path.open("wb") as stream:
                while remaining:
                    size = min(remaining, 1024 * 1024)
                    stream.write(b"x" * size)
                    remaining -= size
    return [{"file": p.name, "bytes": p.stat().st_size, "sha256": digest(p)}
            for p in sorted(folder.iterdir())]


def fixture_checks():
    spec = importlib.util.spec_from_file_location("zero_red_qa_fixture", IOS / "scripts/fixture_server.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(module.Handler, directory=str(module.ROOT)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    checks = []
    # Local fixtures must never be sent through a machine-wide HTTP proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def fetch(path, status=200, contains=None, method="GET"):
        request = urllib.request.Request(origin + path, method=method)
        try:
            with opener.open(request, timeout=5) as response:
                actual, body = response.status, response.read()
        except urllib.error.HTTPError as response:
            actual, body = response.code, response.read()
        ok = actual == status and (contains is None or contains.encode() in body)
        checks.append({"path": path, "method": method, "status": "PASS" if ok else "FAIL",
                       "expected_http": status, "actual_http": actual})
        return body

    try:
        for path, sentinel in [("/", "Zero Red Test Page"), ("/interaction.html", "Show alert"),
                               ("/reader-complete.html", "Visible page conclusion"),
                               ("/reader-frame.html", "Embedded text sentinel"),
                               ("/video-controls.html", "Play in page"),
                               ("/video-frame.html", "iframe"),
                               ("/qa/session.html", "ZR-SESSION"),
                               ("/qa/form.html", "ZR-FORM"),
                               ("/qa/external.html", "zerored")]:
            fetch(path, contains=sentinel)
        data = fetch("/sample.mp4")
        checks.append({"path": "/sample.mp4 SHA-256", "status": "PASS" if hashlib.sha256(data).hexdigest() == digest(module.ROOT / "sample.mp4") else "FAIL"})
        fetch("/fake.mp4", contains="not a full video")
        fetch("/error.mp4", status=403)
        fetch("/test/offline-media/disable", method="POST")
        fetch("/offline-sample.mp4", status=503)
        fetch("/test/offline-media/enable", method="POST")
        fetch("/offline-sample.mp4")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-local", action="store_true")
    parser.add_argument("--large-fixtures", action="store_true")
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:6]
    output = IOS / "TestResults" / ("qa-prep-" + stamp)
    output.mkdir(parents=True)
    records = case_records()
    dump(output / "execution.json", {"run_id": stamp, "status_values": ["NOT_RUN", "PASS", "FAIL", "BLOCKED", "NA"], "records": records})
    dump(output / "source-manifest.json", source_manifest())
    dump(output / "fixture-manifest.json", create_fixtures(output / "fixtures", args.large_fixtures))
    ui_source = (IOS / "UITests/ZeroRedUITests.swift").read_text(encoding="utf-8")
    project = (IOS / "ZeroRed.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    try:
        checks = fixture_checks()
    except (OSError, urllib.error.URLError) as error:
        checks = [{"path": "loopback HTTP fixture self-check", "status": "BLOCKED", "reason": str(error)}]
    tools = {name: shutil.which(name) for name in ["python", "node", "npm", "swift", "bash", "xcodebuild", "xcrun", "ssh"]}
    report = {"created_at_utc": stamp, "platform": platform.platform(),
              "case_count": len(records), "case_status": "ALL_NOT_RUN",
              "ui_test_methods": re.findall(r"func (test\w+)\s*\(", ui_source),
              "deployment_targets": sorted(set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([^;]+)", project))),
              "tools": tools, "fixture_checks": checks,
              "native_execution": "NOT_RUN", "device_execution": "NOT_RUN",
              "local_commands": [], "blockers": []}
    if platform.system() != "Darwin" or not tools["xcodebuild"]:
        report["blockers"].append("Native build/UI execution requires a Mac with full Xcode; this host is not ready for native UI execution.")
    if not tools["swift"]:
        report["blockers"].append("Swift core tests: Swift executable not found on this host.")
    dependency = ROOT / "apps/web/node_modules/fake-indexeddb"
    if not dependency.is_dir():
        report["blockers"].append("Web storage test needs fake-indexeddb 6.0.0; install declared apps/web dependencies before full web suite.")
    report["blockers"].extend([
        "Mac source hash comparison and current simulator inventory have not been verified by this local script.",
        "Physical iPhone/signing, AirPlay, HLS, HTTPS security/permission hosts, POST counter and payment sandbox require separate readiness checks.",
        "Default-browser acceptance requires Apple authorization and matching entitlement/signature."])
    if args.run_local:
        commands = [("project", [sys.executable, "-X", "utf8", str(IOS / "scripts/verify_project.py")])]
        if tools["node"]:
            for name in ["core", "reading", "storage", "media", "download-flow"]:
                if name in {"storage", "download-flow"} and not dependency.is_dir():
                    report["local_commands"].append({"name": "web-" + name, "status": "BLOCKED", "reason": "fake-indexeddb missing"})
                    continue
                commands.append(("web-" + name, [tools["node"], str(ROOT / f"apps/web/tests/{name}.test.cjs")]))
        else:
            report["local_commands"].append({"name": "web-suite", "status": "BLOCKED", "reason": "node missing"})
        for name, argv in commands:
            result = command(argv)
            (output / ("run-local-" + name + ".log")).write_text(result.pop("output"), encoding="utf-8")
            report["local_commands"].append({"name": name, **result})
    report["preparation_status"] = "FAIL" if any(c["status"] == "FAIL" for c in checks + report["local_commands"]) else "PREPARED_WITH_BLOCKERS"
    dump(output / "readiness.json", report)
    print(json.dumps({"output": str(output), "cases": len(records), "ui_methods": len(report["ui_test_methods"]),
                      "fixture_checks": len(checks), "status": report["preparation_status"],
                      "local_commands": [{"name": c["name"], "status": c["status"]} for c in report["local_commands"]]}, ensure_ascii=False))
    return 1 if report["preparation_status"] == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
