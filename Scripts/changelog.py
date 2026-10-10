#!/usr/bin/env python3
"""Reads one version's entry out of CHANGELOG.md.

Two things show a user what changed, and they must not drift apart: the GitHub
release page and Sparkle's update window. Both take their text from here.

Usage:
    Scripts/changelog.py 1.0.3                   # the entry, as markdown
    Scripts/changelog.py 1.0.3 --html            # the same, as the feed carries it
    Scripts/changelog.py 1.0.3 --release-notes   # the whole GitHub release page

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


def previous(version: str) -> str | None:
    """The version released before this one, for the upgrade line and the
    compare link. Read from the file's own order rather than computed, because
    the sequence is whatever was actually shipped."""
    if not CHANGELOG.exists():
        return None
    versions = re.findall(r"^## (\d+\.\d+\.\d+)\s*$", CHANGELOG.read_text(), re.M)
    if version not in versions:
        return None
    index = versions.index(version)
    return versions[index + 1] if index + 1 < len(versions) else None


# The furniture around each language's section of the release page. Only the
# two the changelog itself is written in — the interface ships six languages,
# but the entry is authored in these, and a page cannot carry a section nobody
# wrote.
#
# `id` is the anchor the language nav at the top links to. Kept stable across
# releases (`cn-pulse-1.2.1`, `en-pulse-1.2.1`) so a link into an old page
# still lands where it did.
LANGUAGES: list[dict[str, str]] = [
    {
        "name": "中文",
        "id": "cn",
        "upgrade": "**已经在运行 {previous}？** 会自动提示更新，也可在 **设置 → 关于 → 检查更新** 手动检查。",
        "install_heading": "安装",
        "install": (
            "下载 **Pulse-{version}.dmg**，打开后拖入「应用程序」。未公证，首次启动会被阻止："
            "先打开 Pulse 并关闭警告，再到 **系统设置 → 隐私与安全性 → 安全性 → 仍要打开**。"
            "只需操作一次。\n\n需要 macOS 14 或更高版本，支持 Apple 芯片和 Intel。"
        ),
        "changelog": "**完整更新记录**：{compare}",
    },
    {
        "name": "English",
        "id": "en",
        "upgrade": "**Already running {previous}?** Pulse will offer {version} on its own — or use **Settings → About → Check now**.",
        "install_heading": "Install",
        "install": (
            "Download **Pulse-{version}.dmg** and drag Pulse into Applications. Not notarized, "
            "so macOS blocks the first launch: open Pulse, dismiss the warning, then go to "
            "**System Settings → Privacy & Security → Security → Open Anyway**. Once only."
            "\n\nRequires macOS 14 or newer. Universal (Apple Silicon and Intel)."
        ),
        "changelog": "**Full Changelog**: {compare}",
    },
]

REPOSITORY = "https://github.com/qunqin24/Pulse"


def release_notes(version: str, markdown: str) -> str:
    """The GitHub release page: one section per language, with an anchor each.

    **The page is assembled here rather than in the workflow.** It used to be
    the entry, one hard-coded English install block, and GitHub's generated
    commit list stapled together — which is not what the pages before it looked
    like, so every release was reformatted by hand afterwards or left odd. The
    shape lives with the text it wraps.

    The commit list is left out on purpose: this repository takes direct
    commits, so it runs to dozens of lines of "Update README" under an entry
    that already says what changed.
    """
    sections = split_languages(markdown)
    if len(sections) < 2:
        # One language, or an entry that does not use the two-heading shape.
        # Wrap it in the English furniture rather than inventing a nav bar for
        # a page with nothing to navigate between.
        sections = [(LANGUAGES[-1], markdown)]

    before = previous(version)
    compare = (f"{REPOSITORY}/compare/v{before}...v{version}" if before
               else f"{REPOSITORY}/releases/tag/v{version}")

    parts: list[str] = []
    if len(sections) > 1:
        parts.append(" | ".join(
            f"[{language['name']}](#{language['id']}-pulse-{version})"
            for language, _ in sections))

    for index, (language, body) in enumerate(sections):
        if index:
            parts.append("---")
        parts.append(f"<h2 id=\"{language['id']}-pulse-{version}\">Pulse {version}</h2>")
        if before:
            parts.append(language["upgrade"].format(previous=before, version=version))
        parts.append(promote_headings(body))
        parts.append(f"## {language['install_heading']}")
        parts.append(language["install"].format(version=version))
        parts.append(language["changelog"].format(compare=compare))

    return "\n\n".join(part for part in parts if part)


def split_languages(markdown: str) -> list[tuple[dict[str, str], str]]:
    """The entry cut at its `**中文**` / `**English**` markers."""
    names = {language["name"]: language for language in LANGUAGES}
    sections: list[tuple[dict[str, str], list[str]]] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        marker = re.fullmatch(r"\*\*(.+?)\*\*", stripped)
        if marker and marker.group(1) in names:
            sections.append((names[marker.group(1)], []))
            continue
        if sections:
            sections[-1][1].append(line)
    return [(language, "\n".join(body).strip()) for language, body in sections]


def promote_headings(markdown: str) -> str:
    """`**新功能**` on a line of its own becomes `## 新功能`.

    Inside the update window those are bold paragraphs, which is all Sparkle's
    stylesheet can carry. A release page has real headings and a table of
    contents that reads them, so the same line is worth more as one.
    """
    return re.sub(r"^\*\*([^*]+)\*\*$", r"## \1", markdown, flags=re.M)


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
        # Links first, with the address parked behind a placeholder. All three
        # of these rewrite the whole line, so whichever runs second would
        # otherwise reach *inside* the href the first one produced: a URL
        # containing `**` came out as `<a href="…<strong>a</strong>b">`.
        # Malformed rather than unsafe — every quote is already an entity by
        # here — but wrong, and the label still wants its own formatting.
        addresses: list[str] = []

        def park(match: re.Match[str]) -> str:
            addresses.append(match.group(2))
            return f'<a href="\x00{len(addresses) - 1}\x00">{match.group(1)}</a>'

        escaped = re.sub(r"\[(.+?)\]\((https?://[^)\s]+)\)", park, escaped)
        escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
        escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
        escaped = re.sub(r"\x00(\d+)\x00", lambda m: addresses[int(m.group(1))], escaped)

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

    if "--release-notes" in sys.argv:
        print(release_notes(version, found))
    elif "--html" in sys.argv:
        print(as_html(found))
    else:
        print(found)


if __name__ == "__main__":
    main()
