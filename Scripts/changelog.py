#!/usr/bin/env python3
"""Reads one version's entry out of CHANGELOG.md.

Two things show a user what changed, and they must not drift apart: the GitHub
release page and Sparkle's update window. Both take their text from here.

Usage:
    Scripts/changelog.py 1.0.3            # the entry, as markdown
    Scripts/changelog.py 1.0.3 --html     # the same, as the feed carries it

**The entry is deliberately hand-written.** Generating it from commit subjects
was tried and is wrong: this repository takes direct commits, so the list runs
to forty lines an release and half of them say things like "Update README" —
true, and meaningless to somebody deciding whether to install an update.

Exits 1 when there is no entry, so a caller can fall back rather than ship an
empty dialog.
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"


def entry(version: str) -> str | None:
    """The markdown under `## <version>`, up to the next version heading."""
    if not CHANGELOG.exists():
        return None

    text = CHANGELOG.read_text()
    pattern = rf"^## {re.escape(version)}\s*$(.*?)(?=^## |\Z)"
    match = re.search(pattern, text, re.M | re.S)
    if not match:
        return None

    body = match.group(1).strip()
    return body or None


def as_html(markdown: str) -> str:
    """The small subset the changelog is written in, turned into HTML.

    Bullets, bold, inline code and links — no more than that. A general
    markdown parser would be a dependency and a surface area for a release
    script to fail on; the file is ours, so its grammar can be small enough to
    convert in twenty lines and be sure of.

    Everything is escaped **first**, so a stray `<` in a line is text rather
    than markup, and only the marks below are turned back into tags.
    """
    lines: list[str] = []
    for raw in markdown.splitlines():
        line = raw.strip()
        if not line:
            continue

        # Only the bullet marker, never `lstrip("-* ")` — that also eats the
        # leading asterisks of a line that begins **bold**.
        escaped = html.escape(re.sub(r"^[-*]\s+", "", line))
        escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
        escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
        escaped = re.sub(r"\[(.+?)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', escaped)

        lines.append(f"<li>{escaped}</li>" if line.startswith(("- ", "* ")) else f"<p>{escaped}</p>")

    # Runs of list items become one list, so bullets are not each their own.
    out: list[str] = []
    inside = False
    for line in lines:
        if line.startswith("<li>") and not inside:
            out.append("<ul>")
            inside = True
        elif not line.startswith("<li>") and inside:
            out.append("</ul>")
            inside = False
        out.append(line)
    if inside:
        out.append("</ul>")

    return "".join(out)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    version = sys.argv[1]
    found = entry(version)
    if not found:
        sys.exit(f"CHANGELOG.md has no entry for {version}")

    print(as_html(found) if "--html" in sys.argv else found)


if __name__ == "__main__":
    main()
