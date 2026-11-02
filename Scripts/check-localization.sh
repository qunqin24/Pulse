#!/bin/bash
#
# Two things have to hold, and both of them fail silently at runtime.
#
# 1. The two .strings files must carry the same keys. A key present in one and
#    missing from the other means the lookup misses and the English is shown
#    verbatim, so the app simply stays in English in that one place.
#
# 2. Every key the source asks for must exist. This is the same failure wearing
#    a different hat, and it is easier to cause: a key is an English sentence
#    written out twice, once in Swift and once in the .strings files, so any
#    edit to one that misses the other silently reverts that string to English.
#    It happened by find-and-replace — a rename swept through a *string
#    literal*, leaving the caption asking for a key nobody had written — and
#    the check as it stood could not see it, because both .strings files still
#    agreed with each other perfectly.
#
# 0. Before either: every table must parse. One malformed line — an unescaped
#    quote — makes macOS drop the **whole** file, so the app falls back to
#    English everywhere while the keys above still match. 1.12.5 shipped that
#    way: a script appended a dictionary instead of a translation, quote and
#    all, to all six tables.

set -euo pipefail

cd "$(dirname "$0")/.."

RESOURCES="Sources/Pulse/Resources"
EN="$RESOURCES/en.lproj/Localizable.strings"

keys() { grep -o '^"[^"]*"' "$1" | sed 's/^"//; s/"$//' | sort; }

status=0
languages=0

for table in "$RESOURCES"/*.lproj/Localizable.strings; do
    if ! problem=$(plutil -lint "$table" 2>&1); then
        echo "Not a valid strings file, so macOS would ignore all of it: $problem"
        status=1
    fi
done

# Every shipped language against English, rather than one named pair: a
# language added to the app but not to this loop is a language nobody is
# checking, which is the failure this script exists to prevent.
for table in "$RESOURCES"/*.lproj/Localizable.strings; do
    [ "$table" = "$EN" ] && continue
    language=$(basename "$(dirname "$table")" .lproj)
    languages=$((languages + 1))

    if ! difference=$(diff <(keys "$EN") <(keys "$table")); then
        echo "Localization keys differ between en and $language:"
        echo "  < only in en    > only in $language"
        echo "$difference"
        status=1
    fi
done

# What the source asks for, read with a scanner rather than a pattern — Swift
# interpolations nest and can hold string literals of their own.
python3 Scripts/localization-keys.py "$EN" || status=1

if [ "$status" -eq 0 ]; then
    echo "Localization keys match ($(keys "$EN" | wc -l | tr -d ' ') keys across $languages translations), and every key the source asks for exists."
fi

exit "$status"
