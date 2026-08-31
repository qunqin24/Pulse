#!/usr/bin/env python3
"""Every localization key the Swift source asks for, and whether it exists.

A key is an English sentence written out twice — once in Swift, once in each
.strings file — so any edit to one that misses the other silently reverts that
string to English, with nothing to warn anyone. Comparing the two .strings
files to each other cannot see it; they still agree.

Reading the literals needs a small scanner rather than a regular expression.
Swift interpolations nest, and they can contain string literals of their own
(`\\("\\(count)")`, `\\(names.joined(separator: ", "))`), so a pattern that
stops at the next quote reads half a key and reports it missing. Comments have
to be skipped too, or the examples in a doc comment are reported as keys.
"""

# The annotations below are written in the modern spelling; this keeps them
# from being evaluated on a Python that predates it.
from __future__ import annotations

import pathlib
import re
import sys

CALL = re.compile(r'(?:String\.localized|\.localized|\bText)\(\s*(?:localized:\s*)?(?=")')


def commentless(source: str) -> list[bool]:
    """A mask of positions that are inside a comment, so calls there are ignored."""
    inside = [False] * len(source)
    i, depth, in_line, in_string = 0, 0, False, False

    while i < len(source):
        two = source[i:i + 2]
        if in_line:
            inside[i] = True
            if source[i] == "\n":
                in_line = False
            i += 1
        elif depth:
            inside[i] = True
            if two == "*/":
                inside[i + 1] = True
                depth -= 1
                i += 2
            elif two == "/*":
                depth += 1
                i += 2
            else:
                i += 1
        elif in_string:
            if source[i] == "\\":
                i += 2
            else:
                if source[i] == '"':
                    in_string = False
                i += 1
        elif two == "//":
            in_line = True
        elif two == "/*":
            depth = 1
            i += 2
        else:
            if source[i] == '"':
                in_string = True
            i += 1

    return inside


def literal(source: str, start: int) -> tuple[str, int] | None:
    """The string literal opening at `start`, with interpolations reduced to %@.

    That is what `String.LocalizationValue` produces, and therefore what the
    key in the .strings file has to read as.
    """
    if source[start] != '"':
        return None

    out, i = [], start + 1
    while i < len(source):
        char = source[i]
        if char == "\\":
            if source[i + 1] == "(":
                # Skip the interpolation whole, brackets and nested strings and
                # all, and leave the placeholder in its place.
                out.append("%@")
                depth, i = 0, i + 1
                while i < len(source):
                    if source[i] == '"':
                        inner = literal(source, i)
                        if inner is None:
                            return None
                        i = inner[1]
                        continue
                    if source[i] == "(":
                        depth += 1
                    elif source[i] == ")":
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    i += 1
                continue
            out.append(source[i:i + 2])
            i += 2
            continue
        if char == '"':
            return "".join(out), i + 1
        out.append(char)
        i += 1

    return None


def available(path: pathlib.Path) -> set[str]:
    keys = set()
    for line in path.read_text().splitlines():
        match = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=', line)
        if match:
            keys.add(match.group(1))
    return keys


def main() -> int:
    have = available(pathlib.Path(sys.argv[1]))
    missing: list[tuple[str, int, str]] = []

    for file in sorted(pathlib.Path("Sources/Pulse").rglob("*.swift")):
        source = file.read_text()
        inside = commentless(source)

        for match in CALL.finditer(source):
            if inside[match.start()]:
                continue
            parsed = literal(source, match.end())
            if parsed is None:
                continue
            key = parsed[0]
            # Text("…") is only a lookup when it is written as Text(localized:).
            # A bare Text with a literal is not localized at all, which is its
            # own mistake but not this check's.
            if match.group(0).lstrip().startswith("Text") and "localized" not in match.group(0):
                continue
            if key not in have:
                missing.append((str(file), source[:match.start()].count("\n") + 1, key))

    if missing:
        print("Keys the source asks for that the .strings files do not have:")
        for file, line, key in missing:
            print(f"  {file}:{line}")
            print(f"    {key}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
