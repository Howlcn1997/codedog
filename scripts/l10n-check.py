#!/usr/bin/env python3
"""检查 String Catalog 是否覆盖了代码里的全部文案。

先 `make build`（会产出编译器提取的 .stringsdata），再运行本脚本：
列出代码里有、但 App/Resources/Localizable.xcstrings 里缺少英文或繁体翻译的 key。
CodedogCore 里的 String(localized:) 不在 App 目标的提取结果中，脚本会单独编译一遍来提取。
"""
import glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "App/Resources/Localizable.xcstrings")
LANGS = ["en", "zh-Hant"]


def extracted_keys():
    keys = set()
    files = glob.glob(os.path.join(ROOT, "build/DerivedData/**/codedog.build/**/*.stringsdata"), recursive=True)
    with tempfile.TemporaryDirectory() as tmp:
        sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
        sources = glob.glob(os.path.join(ROOT, "Packages/CodedogCore/Sources/**/*.swift"), recursive=True)
        subprocess.run(["xcrun", "swiftc", "-c", "-wmo", "-parse-as-library", "-module-name", "CodedogCore",
                        "-sdk", sdk, "-target", "arm64-apple-macos26", "-swift-version", "6",
                        "-emit-localized-strings", "-emit-localized-strings-path", tmp, *sources,
                        "-o", os.path.join(tmp, "core.o")], check=True, capture_output=True)
        files += glob.glob(os.path.join(tmp, "*.stringsdata"))
        for f in files:
            if "DebugSnapshot" in f or "CodedogCLI" in f:
                continue
            for e in json.load(open(f))["tables"].get("Localizable", []):
                keys.add(e["key"])
    return keys


def main():
    strings = json.load(open(CATALOG))["strings"]
    missing = []
    for key in sorted(extracted_keys()):
        entry = strings.get(key)
        if not re.search(r"[一-鿿]", key):
            continue
        langs = (entry or {}).get("localizations", {})
        lacks = [l for l in LANGS if l not in langs]
        if lacks:
            missing.append(f"{key!r}  缺少: {', '.join(lacks)}")
    print("\n".join(missing) if missing else "全部文案都有翻译。")
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
