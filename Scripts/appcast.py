#!/usr/bin/env python3
"""Adds a build to appcast.xml, the feed Sparkle reads.

Sparkle will not install an archive that isn't signed by the EdDSA key whose
public half is in the app's Info.plist, so the signature written here is what
makes updating safe without an Apple Developer ID. The private half never
touches the repository: it lives in the SPARKLE_PRIVATE_KEY secret and reaches
`sign_update` through the environment.

Usage:
    Scripts/appcast.py <version> <path-to-zip> <download-url>
    Scripts/appcast.py --notes <version>     # rewrite one item's notes only

**One language in the update window.** The changelog entry is written in
Chinese and English; each item carries one `<description xml:lang="…">` per
language and Sparkle shows the one the system's preferred languages pick
(`NSBundle preferredLocalizationsFromArray:`). Chinese goes out as both
`zh-Hans` and `zh-Hant` — no Traditional section is written, and macOS would
otherwise give a Traditional reader the English. Japanese, Korean and Russian readers
get English. Pulse can also be set to a language other than the system's, which
Sparkle cannot see, so the script writes one feed per language as well
(`appcast-zh.xml`, `appcast-en.xml`: the same items with only that language's
notes), and the app reads the one for the language it is set to
(`UpdaterRelay.feedURLString`).

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

# The changelog's languages, each with the `xml:lang` values it is offered
# under, the per-language feed it is written to, and the line under the notes.
NOTE_LANGUAGES: dict[str, dict[str, object]] = {
    "中文": {"langs": ["zh-Hans", "zh-Hant"], "feed": "appcast-zh.xml", "link": "在 GitHub 上查看更新说明"},
    "English": {"langs": ["en"], "feed": "appcast-en.xml", "link": "Release notes on GitHub"},
}

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


def notes_html(version: str, listing: str, link_text: str) -> str:
    """One language's notes as the update window shows them."""
    link = f'<p><a href="{REPO}/releases/tag/v{version}">{html.escape(link_text)}</a></p>'
    inner = f"{STYLE}<h2>Pulse {html.escape(version)}</h2>{listing}{link}"
    # A CDATA section cannot contain its own terminator; nothing here should
    # produce one, but a commit subject is user-written text.
    return inner.replace("]]>", "]]&gt;")


def descriptions(version: str, previous: str | None) -> str:
    """The release notes Sparkle shows, carried **in the feed**: the
    `<description>` elements of one item, one per language when the entry is
    written in both.

    Not a `sparkle:releaseNotesLink`, which is what this used to be: that is
    not a link the user clicks, it is a page Sparkle loads into the update
    window — so the whole GitHub release page, navigation bars and all, was
    rendered inside a small panel, and showed nothing at all without a network.
    """
    written = changelog.entry(version)
    if written:
        sections = changelog.split_languages(written)
        if len(sections) >= 2 and all(language["name"] in NOTE_LANGUAGES for language, _ in sections):
            elements = []
            for language, body in sections:
                spec = NOTE_LANGUAGES[language["name"]]
                notes = notes_html(version, changelog.as_html(body), str(spec["link"]))
                for lang in spec["langs"]:
                    elements.append(f'<description xml:lang="{lang}"><![CDATA[{notes}]]></description>')
            return "\n            ".join(elements)
        listing = changelog.as_html(written)
    else:
        items = changes(version, previous)
        body = "".join(f"<li>{html.escape(line)}</li>" for line in items)
        listing = f"<ul>{body}</ul>" if body else ""

    # One language, or the fallback: a single description with no `xml:lang`.
    return f"<description><![CDATA[{notes_html(version, listing, 'Release notes on GitHub')}]]></description>"


ITEM = re.compile(r"        <item>\n.*?        </item>\n", re.S)
DESCRIPTION = re.compile(r'[ \t]*<description(?: xml:lang="([^"]+)")?><!\[CDATA\[.*?\]\]></description>\n', re.S)


def single_language(feed: str, langs: list[str]) -> str:
    """The feed with each item's notes cut to one language.

    An item with notes in several languages keeps only the first of `langs`
    it has, under no `xml:lang` (one node needs none); an older item with one
    bilingual description is left as it is.
    """
    def cut(match: re.Match[str]) -> str:
        item = match.group(0)
        found = DESCRIPTION.findall(item)
        if len([lang for lang in found if lang]) < 2:
            return item
        keep = next((lang for lang in langs if lang in found), None)
        if keep is None:
            return item

        def one(description: re.Match[str]) -> str:
            if description.group(1) != keep:
                return ""
            return description.group(0).replace(f' xml:lang="{keep}"', "", 1)

        return DESCRIPTION.sub(one, item)

    return ITEM.sub(cut, feed)


def write_feeds(feed: str) -> None:
    """appcast.xml and its one-language copies."""
    FEED.write_text(feed)
    for spec in NOTE_LANGUAGES.values():
        langs = [str(lang) for lang in spec["langs"]]  # type: ignore[union-attr]
        copy = single_language(feed, langs).replace(
            "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml",
            f"https://raw.githubusercontent.com/qunqin24/Pulse/main/{spec['feed']}",
            1,
        )
        (ROOT / str(spec["feed"])).write_text(copy)


def rewrite_notes(version: str) -> None:
    """Replaces the notes of an item already in the feed, nothing else: the
    enclosure, its signature and the dates stay as they were served."""
    feed = FEED.read_text()
    for match in ITEM.finditer(feed):
        item = match.group(0)
        if f"<sparkle:version>{version}</sparkle:version>" not in item:
            continue
        previous = None
        older = feed[match.end():]
        found = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", older)
        if found:
            previous = found.group(1)
        stripped = DESCRIPTION.sub("", item)
        anchor = "            <enclosure "
        if anchor not in stripped:
            sys.exit(f"The {version} item is not in the shape this expects — check it by hand.")
        rewritten = stripped.replace(anchor, f"            {descriptions(version, previous)}\n{anchor}", 1)
        write_feeds(feed[:match.start()] + rewritten + feed[match.end():])
        print(f"Rewrote the notes for {version}.")
        return
    sys.exit(f"appcast.xml has no item for {version}.")


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--notes":
        rewrite_notes(sys.argv[2])
        return
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    version, archive, url = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    signature, length = sign(archive)

    feed = FEED.read_text() if FEED.exists() else SKELETON
    notes = descriptions(version, previous_version(feed))

    item = f"""        <item>
            <title>{version}</title>
            <pubDate>{email.utils.formatdate(localtime=False, usegmt=False)}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <link>{REPO}/releases/tag/v{version}</link>
            {notes}
            <enclosure url="{url}"
                       length="{length}"
                       type="application/octet-stream"
                       sparkle:edSignature="{signature}" />
        </item>
"""

    if f"<sparkle:version>{version}</sparkle:version>" in feed:
        print(f"appcast.xml already carries {version} — leaving it alone.")
        write_feeds(feed)
        return

    # Newest first, which is the order Sparkle and every feed reader expect.
    anchor = "        <language>en</language>\n"
    if anchor not in feed:
        sys.exit("appcast.xml is not in the shape this expects — check it by hand.")

    write_feeds(feed.replace(anchor, anchor + item, 1))
    print(f"appcast.xml now offers {version} ({length} bytes)")


if __name__ == "__main__":
    main()
