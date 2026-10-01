#!/usr/bin/env python3
"""Checks that every text shown in the app is translated, with the same placeholders.

Usage: python3 tests/check_strings.py [--list]
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALL = re.compile(r'\bL\("((?:[^"\\]|\\.)*)"')
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')


def keys_in_sources():
    keys = {}
    for path in sorted((ROOT / "Sources").glob("*.swift")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for match in CALL.finditer(line):
                keys.setdefault(match.group(1), f"{path.name}:{number}")
    return keys


def entries(path):
    result = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("//") or line.startswith("/*"):
            continue
        match = ENTRY.match(line)
        if not match:
            sys.exit(f"{path.name}:{number}: cannot read this line: {line}")
        result[match.group(1)] = match.group(2)
    return result


def placeholders(text):
    return sorted(re.findall(r"%(?:\d\$)?[@dlsf]", text))


def main():
    keys = keys_in_sources()
    if "--list" in sys.argv:
        for key in sorted(keys):
            print(key)
        return
    problems = []
    languages = sorted(p.parent.stem for p in (ROOT / "Resources").glob("*.lproj/Localizable.strings") if p.parent.stem != "en")
    for lang in languages:
        texts = entries(ROOT / f"Resources/{lang}.lproj/Localizable.strings")
        for key, where in sorted(keys.items()):
            if key not in texts:
                problems.append(f"{lang}: missing translation for \"{key}\" ({where})")
            elif placeholders(key) != placeholders(texts[key]):
                problems.append(f"{lang}: placeholders differ for \"{key}\"")
        for key in sorted(set(texts) - set(keys)):
            problems.append(f"{lang}: text no longer used: \"{key}\"")
    for p in problems:
        print("FAIL " + p)
    print(f"{len(keys)} texts, languages checked: {', '.join(languages)}, {len(problems)} problems")
    sys.exit(1 if problems else 0)


main()
