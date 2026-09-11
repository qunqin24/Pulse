#!/usr/bin/env python3
"""Build the bilingual GitHub Release body for one version.

Chinese first, English second — same shape as upstream qunqin24/Pulse release
pages. Sparkle still reads the English CHANGELOG.md via changelog.py /
appcast.py; this script is only for the GitHub Release page.

Usage:
    Scripts/release-notes.py 1.1.0

Reads CHANGELOG.zh-CN.md and CHANGELOG.md. Exits 1 if the Chinese entry is
missing (English-only would ship a half-translated page). Previous version for
the "Already running …?" line and the Full Changelog compare link comes from
the next `##` heading in CHANGELOG.md (newest first).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG_EN = ROOT / "CHANGELOG.md"
CHANGELOG_ZH = ROOT / "CHANGELOG.zh-CN.md"


def github_repo() -> str:
    """owner/name. CI sets GITHUB_REPOSITORY; a local run reads origin."""
    env = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if env:
        return env
    result = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    url = result.stdout.strip()
    for prefix in ("git@github.com:", "https://github.com/", "ssh://git@github.com/"):
        if url.startswith(prefix):
            url = url[len(prefix) :]
            break
    if url.endswith(".git"):
        url = url[:-4]
    if not url:
        sys.exit("Could not tell which GitHub repository this is.")
    return url


def entry(path: Path, version: str) -> str | None:
    """Markdown under `## <version>`, up to the next version heading."""
    if not path.exists():
        return None
    text = path.read_text()
    pattern = rf"^## {re.escape(version)}\s*$(.*?)(?=^## |\Z)"
    match = re.search(pattern, text, re.M | re.S)
    if not match:
        return None
    body = match.group(1).strip()
    return body or None


def previous_version(version: str) -> str | None:
    """The version listed after `version` in CHANGELOG.md (newest first)."""
    if not CHANGELOG_EN.exists():
        return None
    versions = re.findall(r"^## (\d+\.\d+\.\d+(?:[-+][^\s]+)?)\s*$", CHANGELOG_EN.read_text(), re.M)
    try:
        i = versions.index(version)
    except ValueError:
        return None
    if i + 1 < len(versions):
        return versions[i + 1]
    return None


def install_zh(version: str) -> str:
    return "\n".join(
        [
            "## 安装",
            "",
            f"下载 **Pulse-{version}.dmg**，打开后拖入「应用程序」。未公证，首次启动会被阻止：先打开 Pulse 并关闭警告，再到 **系统设置 → 隐私与安全性 → 安全性 → 仍要打开**。只需操作一次。",
            "",
            "需要 macOS 14 或更高版本，支持 Apple 芯片和 Intel。",
        ]
    )


def install_en(version: str) -> str:
    return "\n".join(
        [
            "## Install",
            "",
            f"Download **Pulse-{version}.dmg** and drag Pulse into Applications. Not notarized, so macOS blocks the first launch: open Pulse, dismiss the warning, then go to **System Settings → Privacy & Security → Security → Open Anyway**. Once only.",
            "",
            "Requires macOS 14 or newer. Universal (Apple Silicon and Intel).",
        ]
    )


def build(version: str) -> str:
    zh = entry(CHANGELOG_ZH, version)
    if not zh:
        sys.exit(f"CHANGELOG.zh-CN.md has no entry for {version}")

    en = entry(CHANGELOG_EN, version)
    if not en:
        sys.exit(f"CHANGELOG.md has no entry for {version}")

    prev = previous_version(version)
    repo = github_repo()
    compare = (
        f"https://github.com/{repo}/compare/v{prev}...v{version}"
        if prev
        else f"https://github.com/{repo}/releases/tag/v{version}"
    )

    already_zh = (
        f"**已经在运行 {prev}？** 会自动提示更新，也可在 **设置 → 关于 → 检查更新** 手动检查。"
        if prev
        else "**首次安装？** 下载下方安装包即可。"
    )
    already_en = (
        f"**Already running {prev}?** Pulse will offer {version} on its own — or use **Settings → About → Check now**."
        if prev
        else "**First install?** Download the package below."
    )

    parts = [
        f"[中文](#cn-pulse-{version}) | [English](#en-pulse-{version})",
        "",
        f'<h2 id="cn-pulse-{version}">Pulse {version}</h2>',
        "",
        already_zh,
        "",
        "## 更新内容",
        "",
        zh,
        "",
        install_zh(version),
        "",
        f"**完整更新记录**：{compare}",
        "",
        "---",
        "",
        f'<h2 id="en-pulse-{version}">Pulse {version}</h2>',
        "",
        already_en,
        "",
        "## What's new",
        "",
        en,
        "",
        install_en(version),
        "",
        f"**Full Changelog**: {compare}",
        "",
    ]
    return "\n".join(parts)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    print(build(sys.argv[1]), end="")


if __name__ == "__main__":
    main()
