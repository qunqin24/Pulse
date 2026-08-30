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

import email.utils
import os
import subprocess
import sys
from pathlib import Path

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
    # In CI the key comes from the secret; on a developer's Mac `generate_keys`
    # has already put it in the login keychain and the tool finds it there.
    key = os.environ.get("SPARKLE_PRIVATE_KEY", "").strip()
    if key:
        command += ["-s", key]
    command.append(str(archive))

    output = subprocess.run(command, capture_output=True, text=True, check=True).stdout

    # It prints the two attributes ready to paste: sparkle:edSignature="…" length="…"
    parts = dict(
        piece.split("=", 1) for piece in output.strip().replace('" ', '"\n').split("\n")
    )
    signature = parts["sparkle:edSignature"].strip('"')
    length = parts["length"].strip('"')
    return signature, length


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    version, archive, url = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    signature, length = sign(archive)

    item = f"""        <item>
            <title>{version}</title>
            <pubDate>{email.utils.formatdate(localtime=False, usegmt=False)}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <link>https://github.com/qunqin24/Pulse/releases/tag/v{version}</link>
            <sparkle:releaseNotesLink>https://github.com/qunqin24/Pulse/releases/tag/v{version}</sparkle:releaseNotesLink>
            <enclosure url="{url}"
                       length="{length}"
                       type="application/octet-stream"
                       sparkle:edSignature="{signature}" />
        </item>
"""

    feed = FEED.read_text() if FEED.exists() else SKELETON

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
