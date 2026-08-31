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

set -euo pipefail

cd "$(dirname "$0")/.."

EN="Sources/Pulse/Resources/en.lproj/Localizable.strings"
ZH="Sources/Pulse/Resources/zh-Hans.lproj/Localizable.strings"

keys() { grep -o '^"[^"]*"' "$1" | sed 's/^"//; s/"$//' | sort; }

status=0

if ! diff <(keys "$EN") <(keys "$ZH") > /tmp/localization-diff.txt; then
    echo "Localization keys differ between en and zh-Hans:"
    echo "  < only in en    > only in zh-Hans"
    cat /tmp/localization-diff.txt
    status=1
fi

# What the source asks for, read with a scanner rather than a pattern — Swift
# interpolations nest and can hold string literals of their own.
python3 Scripts/localization-keys.py "$EN" || status=1

if [ "$status" -eq 0 ]; then
    echo "Localization keys match ($(keys "$EN" | wc -l | tr -d ' ') keys), and every key the source asks for exists."
fi

exit "$status"
