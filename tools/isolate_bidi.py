#!/usr/bin/env python3
"""Wraps Latin words and %@ placeholders inside Arabic strings in Unicode isolates.

Without isolates, a run like "Cinema 2026" inside an Arabic sentence is laid out
left to right as one block, so the words come out in the wrong order. FSI (U+2068)
… PDI (U+2069) make each run behave like a single neutral word.

Run from the repository root after adding Arabic strings:
    python3 tools/isolate_bidi.py
It is safe to run again: already isolated runs are left alone.
"""
import json
import re
import sys

FSI, PDI = "⁨", "⁩"
PATH = "Cinema/Resources/Localizable.xcstrings"

ARABIC = re.compile(r"[؀-ۿ]")
# A Latin run: starts with a letter or digit, may hold spaces and URL/brand punctuation,
# ends with a letter, digit, '+' or '/'. Must contain at least one Latin letter.
LATIN_RUN = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9 .'’&:/_\-]*[A-Za-z0-9+/])?\+?")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?@")
# Any printf-style specifier (%lld, %1$@, %.1f, %%): kept whole so it is never split.
SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA%]")


def isolate(value: str) -> str:
    if not ARABIC.search(value):
        return value
    out, i = [], 0
    pattern = re.compile(f"{SPECIFIER.pattern}|{LATIN_RUN.pattern}")
    for match in pattern.finditer(value):
        text = match.group(0)
        start, end = match.span()
        if text.startswith("%"):
            if not PLACEHOLDER.fullmatch(text):
                continue  # numbers (%lld) sit fine inside Arabic
        elif not re.search(r"[A-Za-z]", text):
            continue  # so do plain numbers
        if value[start - 1:start] == FSI and value[end:end + 1] == PDI:
            continue  # already isolated
        out.append(value[i:start])
        out.append(FSI + text + PDI)
        i = end
    out.append(value[i:])
    return "".join(out)


def main() -> int:
    with open(PATH, encoding="utf-8") as file:
        catalog = json.load(file)
    changed = 0
    for entry in catalog["strings"].values():
        unit = entry.get("localizations", {}).get("ar", {}).get("stringUnit")
        if not unit:
            continue
        new = isolate(unit["value"])
        if new != unit["value"]:
            unit["value"] = new
            changed += 1
    with open(PATH, "w", encoding="utf-8") as file:
        file.write(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", ": ")))
    print(f"Isolated {changed} Arabic strings.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
