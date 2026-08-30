#!/bin/bash
#
# The two .strings files must carry the same keys.
#
# A key present in one and missing from the other fails silently at runtime:
# the lookup misses and the English text is shown verbatim, so the app simply
# stays in English in that one place and nothing warns anyone. That has shipped
# more than once, which is why it is a build gate rather than a habit.

set -euo pipefail

cd "$(dirname "$0")/.."

EN="Sources/Pulse/Resources/en.lproj/Localizable.strings"
ZH="Sources/Pulse/Resources/zh-Hans.lproj/Localizable.strings"

keys() { grep -o '^"[^"]*"' "$1" | sort; }

if diff <(keys "$EN") <(keys "$ZH") > /tmp/localization-diff.txt; then
    echo "Localization keys match ($(keys "$EN" | wc -l | tr -d ' ') keys)."
    exit 0
fi

echo "Localization keys differ between en and zh-Hans:"
echo "  < only in en    > only in zh-Hans"
cat /tmp/localization-diff.txt
exit 1
