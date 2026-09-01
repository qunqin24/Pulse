#!/usr/bin/env python3
"""Adds a build to appcast.xml, the feed Sparkle reads.

Sparkle will not install an archive that isn't signed by the EdDSA key whose
public half is in the app's Info.plist, so the signature written here is what
makes updating safe without an Apple Developer ID. The private half never
touches the repository: it lives in the SPARKLE_PRIVATE_KEY secret and reaches
`sign_update` through the environment.

Usage:
    Scripts/appcast.py <version> <path-to-zip> <download-url>

The feed is committed rather than generated from scratch each time. Re-signing
older releases would mean downloading every archive ever published just to say
the same thing about them again, and an entry that has been served once should
not change afterwards.
"""

from __future__ import annotations

import email.utils
import html
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import changelog  # noqa: E402  — a sibling script, not a package

ROOT = Path(__file__).resolve().parent.parent
FEED = ROOT / "appcast.xml"

SKELETON = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Pulse</title>
        <link>https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml</link>
        <description>Updates for Pulse.</description>
        <language>en</language>
    </channel>
</rss>
"""


def sign(archive: Path) -> tuple[str, str]:
    """The archive's EdDSA signature and length, from Sparkle's own tool."""
    tools = list((ROOT / ".build" / "artifacts").rglob("sign_update"))
    if not tools:
        sys.exit("sign_update not found — run `swift build` first so Sparkle's tools are fetched.")

    command = [str(tools[0])]

    # In CI the key comes from the secret and is piped in; on a developer's Mac
    # `generate_keys` has already put it in the login keychain and the tool
    # finds it there on its own.
    #
    # Through stdin, not `-s`: that flag is deprecated and explicitly refuses
    # newly generated keys, which is every key anyone would make today. It
    # fails with a message you only see if stderr is not swallowed, which is
    # the other half of why this cost a release run.
    key = os.environ.get("SPARKLE_PRIVATE_KEY", "").strip()
    if key:
        command += ["--ed-key-file", "-"]
    command.append(str(archive))

    result = subprocess.run(
        command,
        input=key + "\n" if key else None,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"sign_update failed ({result.returncode}):\n{result.stderr.strip()}")

    output = result.stdout

    # It prints the two attributes ready to paste: sparkle:edSignature="…" length="…"
    parts = dict(
        piece.split("=", 1) for piece in output.strip().replace('" ', '"\n').split("\n")
    )
    signature = parts["sparkle:edSignature"].strip('"')
    length = parts["length"].strip('"')
    return signature, length


REPO = "https://github.com/qunqin24/Pulse"

# Bookkeeping, not news: the version bump itself and the commit this script's
# own output produces.
BORING = re.compile(r"^(Pulse \d|Offer \d[\d.]* to Sparkle$)")

# Spacing only — **no colours and no fonts.** Sparkle injects a stylesheet of
# its own (`ReleaseNotesColorStyle.css`) that turns the text white under
# `prefers-color-scheme: dark` and leaves the background transparent so the
# update window shows through, and it sets the font to match the dialog. A feed
# that brings its own palette is fighting that, and loses in whichever
# appearance it guessed wrong about.
STYLE = """<style>
  h2 { font-size: 1.05em; margin: 0 0 .5em; }
  ul { margin: 0; padding-left: 1.2em; }
  li { margin: .3em 0; }
  p { margin: .8em 0 0; }
</style>"""


def previous_version(feed: str) -> str | None:
    """The newest version already in the feed, which is the one being replaced."""
    match = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", feed)
    return match.group(1) if match else None


def changes(version: str, previous: str | None) -> list[str]:
    """The commit subjects, as a **fallback** when the changelog has no entry.

    Not the first choice, and it was: this repository takes direct commits, so
    the range runs to forty subjects a release and half of them say things like
    "Update README" — true, and meaningless to somebody deciding whether to
    install an update. A forgotten changelog entry should still ship something
    rather than an empty dialog, which is all this is for.
    """
    if not previous:
        return []

    result = subprocess.run(
        ["git", "log", f"v{previous}..v{version}", "--format=%s", "--reverse"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    if result.returncode != 0:
        return []

    return [line for line in result.stdout.splitlines() if line and not BORING.match(line)]


def description(version: str, previous: str | None) -> str:
    """The release notes Sparkle shows, carried **in the feed**.

    Not a `sparkle:releaseNotesLink`, which is what this used to be: that is
    not a link the user clicks, it is a page Sparkle loads into the update
    window — so the whole GitHub release page, navigation bars and all, was
    rendered inside a small panel, and showed nothing at all without a network.
    """
    written = changelog.entry(version)
    if written:
        listing = changelog.as_html(written)
    else:
        items = changes(version, previous)
        body = "".join(f"<li>{html.escape(line)}</li>" for line in items)
        listing = f"<ul>{body}</ul>" if body else ""

    link = f'<p><a href="{REPO}/releases/tag/v{version}">Release notes on GitHub</a></p>'
    inner = f"{STYLE}<h2>Pulse {html.escape(version)}</h2>{listing}{link}"

    # A CDATA section cannot contain its own terminator; nothing here should
    # produce one, but a commit subject is user-written text.
    return inner.replace("]]>", "]]&gt;")


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    version, archive, url = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    signature, length = sign(archive)

    feed = FEED.read_text() if FEED.exists() else SKELETON
    notes = description(version, previous_version(feed))

    item = f"""        <item>
            <title>{version}</title>
            <pubDate>{email.utils.formatdate(localtime=False, usegmt=False)}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <link>{REPO}/releases/tag/v{version}</link>
            <description><![CDATA[{notes}]]></description>
            <enclosure url="{url}"
                       length="{length}"
                       type="application/octet-stream"
                       sparkle:edSignature="{signature}" />
        </item>
"""

    if f"<sparkle:version>{version}</sparkle:version>" in feed:
        print(f"appcast.xml already carries {version} — leaving it alone.")
        return

    # Newest first, which is the order Sparkle and every feed reader expect.
    anchor = "        <language>en</language>\n"
    if anchor not in feed:
        sys.exit("appcast.xml is not in the shape this expects — check it by hand.")

    FEED.write_text(feed.replace(anchor, anchor + item, 1))
    print(f"appcast.xml now offers {version} ({length} bytes)")


if __name__ == "__main__":
    main()
