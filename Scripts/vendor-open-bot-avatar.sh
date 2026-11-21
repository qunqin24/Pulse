#!/bin/bash
# Rebuilds Sources/Pulse/Resources/open-bot-avatar.js and open-bot-avatars.json
# from Open Bot Avatar (https://github.com/DominikScholz/open-bot-avatar, MIT).
#
#   ./Scripts/vendor-open-bot-avatar.sh 0.3.0 5e64c08
#
# The first argument is the npm version of the engine, the second the commit of
# the repository whose gallery/ is taken. Needs npm, npx and gh. Read the diff
# before committing it: Docs/ui/rings-and-surface.md#robot says what Pulse
# relies on.
set -euo pipefail
version="${1:?engine version, e.g. 0.3.0}"
commit="${2:?gallery commit, e.g. 5e64c08}"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cd "$work"
npm pack "open-bot-avatar@$version" --silent >/dev/null
mkdir pkg && tar -xzf "open-bot-avatar-$version.tgz" -C pkg
cat > entry.js <<'JS'
export { liveFrame } from './pkg/package/dist/render.js';
export { validateAvatar } from './pkg/package/dist/validate.js';
export { createAnimator } from './pkg/package/dist/animator.js';
export { examples } from './pkg/package/dist/examples.js';
JS
npx --yes esbuild@0.24.0 entry.js --bundle --format=iife --global-name=OpenBotAvatar \
    --target=safari16 --minify --legal-comments=none --outfile=bundle.js --log-level=warning
{
    echo "// open-bot-avatar $version (https://github.com/DominikScholz/open-bot-avatar)"
    echo "// Copyright (c) 2026 Dominik Scholz. MIT License; see THIRD_PARTY_NOTICES.md."
    echo "// Bundled for JavaScriptCore by Scripts/vendor-open-bot-avatar.sh. Do not edit."
    cat bundle.js
} > "$root/Sources/Pulse/Resources/open-bot-avatar.js"

mkdir gallery
for name in $(gh api "repos/DominikScholz/open-bot-avatar/contents/gallery?ref=$commit" \
        --jq '.[] | select(.name | endswith(".json")) | select(.name != "colors.json") | .name'); do
    gh api "repos/DominikScholz/open-bot-avatar/contents/gallery/$name?ref=$commit" --jq .content \
        | base64 -d > "gallery/$name"
done
python3 - "$root/Sources/Pulse/Resources/open-bot-avatars.json" gallery <<'PY'
import glob, json, sys
out, folder = sys.argv[1], sys.argv[2]
avatars = [json.load(open(f)) for f in sorted(glob.glob(folder + "/*.json"))]
with open(out, "w") as f:
    json.dump(avatars, f, separators=(",", ":"))
    f.write("\n")
PY
echo "open-bot-avatar $version and the gallery at $commit are in Sources/Pulse/Resources."
