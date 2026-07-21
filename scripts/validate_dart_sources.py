#!/usr/bin/env python3
"""Lightweight offline integrity checks for Dart sources when the SDK is unavailable.

This does not replace `flutter analyze`; CI still runs the real analyzer. It catches
missing package imports, duplicate class declarations, unterminated comments/strings,
and unbalanced delimiters before packaging the repository.
"""
from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "apps" / "mobile_flutter" / "lib"
PACKAGE_PREFIX = "package:ahla_shabab_management_os/"


def structural_scan(path: Path, source: str) -> list[str]:
    errors: list[str] = []
    stack: list[tuple[str, int]] = []
    pairs = {')': '(', ']': '[', '}': '{'}
    opens = set(pairs.values())
    i = 0
    state = "normal"
    quote = ""
    block_depth = 0

    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        tri = source[i : i + 3]

        if state == "line_comment":
            if ch == "\n":
                state = "normal"
            i += 1
            continue

        if state == "block_comment":
            if ch == "/" and nxt == "*":
                block_depth += 1
                i += 2
                continue
            if ch == "*" and nxt == "/":
                block_depth -= 1
                i += 2
                if block_depth == 0:
                    state = "normal"
                continue
            i += 1
            continue

        if state in {"single", "double"}:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                state = "normal"
            i += 1
            continue

        if state in {"triple_single", "triple_double"}:
            token = "'''" if state == "triple_single" else '\"\"\"'
            if tri == token:
                state = "normal"
                i += 3
                continue
            i += 1
            continue

        if ch == "/" and nxt == "/":
            state = "line_comment"
            i += 2
            continue
        if ch == "/" and nxt == "*":
            state = "block_comment"
            block_depth = 1
            i += 2
            continue
        if tri == "'''":
            state = "triple_single"
            i += 3
            continue
        if tri == '\"\"\"':
            state = "triple_double"
            i += 3
            continue
        if ch == "'":
            state = "single"
            quote = ch
            i += 1
            continue
        if ch == '"':
            state = "double"
            quote = ch
            i += 1
            continue

        if ch in opens:
            stack.append((ch, i))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                errors.append(f"{path}: unexpected {ch!r} at byte {i}")
            else:
                stack.pop()
        i += 1

    if state not in {"normal", "line_comment"}:
        errors.append(f"{path}: unterminated lexical state {state}")
    for delimiter, offset in stack:
        errors.append(f"{path}: unclosed {delimiter!r} from byte {offset}")
    return errors


def main() -> int:
    errors: list[str] = []
    classes: defaultdict[str, list[Path]] = defaultdict(list)
    files = sorted(LIB.rglob("*.dart"))

    for path in files:
        source = path.read_text(encoding="utf-8")
        errors.extend(structural_scan(path.relative_to(ROOT), source))

        for match in re.finditer(r"^\s*(?:abstract\s+|base\s+|final\s+|sealed\s+)?class\s+([A-Za-z_]\w*)", source, re.MULTILINE):
            classes[match.group(1)].append(path.relative_to(ROOT))

        for uri in re.findall(r"(?:import|export|part)\s+'([^']+)'", source):
            if not uri.startswith(PACKAGE_PREFIX):
                continue
            target = LIB / uri.removeprefix(PACKAGE_PREFIX)
            if not target.is_file():
                errors.append(f"{path.relative_to(ROOT)}: missing import target {uri}")

    for class_name, paths in sorted(classes.items()):
        if class_name.startswith("_"):
            continue
        if len(paths) > 1:
            joined = ", ".join(map(str, paths))
            errors.append(f"duplicate Dart class {class_name}: {joined}")

    if errors:
        print("Dart source integrity check failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"Dart source integrity valid: {len(files)} files, {len(classes)} classes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
