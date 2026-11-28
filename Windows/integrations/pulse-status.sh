#!/bin/bash
# Cached usage for a shell prompt or tmux. Requires jq; never fetches a provider.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

format=plain
stdin=false
for argument in "$@"; do
    case "$argument" in
        --tmux) format=tmux ;;
        --stdin) stdin=true ;;
        *) printf 'Usage: pulse-status.sh [--tmux] [--stdin]\n' >&2; exit 2 ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    printf 'Pulse: install jq to use this integration.\n' >&2
    exit 1
fi
max_age="${PULSE_MAX_AGE:-1800}"
case "$max_age" in ''|*[!0-9]*) printf 'Pulse: PULSE_MAX_AGE must be seconds.\n' >&2; exit 2 ;; esac

read_report() {
    if "$stdin"; then
        # jq receives stdin directly; this path also makes fixture checks possible.
        jq -c .
        return
    fi
    local binary="${PULSE_BIN:-/Applications/Pulse.app/Contents/MacOS/Pulse}"
    if [ -z "${PULSE_BIN:-}" ] && [ ! -x "$binary" ]; then
        binary="$HOME/Applications/Pulse.app/Contents/MacOS/Pulse"
    fi
    if [ ! -x "$binary" ]; then
        printf 'Pulse: app not found. Set PULSE_BIN to its executable.\n' >&2
        return 1
    fi
    "$binary" --json
}

read_report | jq -er --arg account "${PULSE_ACCOUNT:-}" --arg format "$format" --argjson maxAge "$max_age" '
    def clean: gsub("[\u0000-\u001f\u007f]"; " ");
    if (.accounts | type) != "array" then error("Invalid Pulse report") else . end |
    [.accounts[] | select($account == "" or .id == $account) |
        . as $a | .headline as $h |
        ([.windows[]? | select(.id == $h.windowId)][0].estimated // false) as $estimated |
        ((.label // .name) | clean) + ": " +
        (if $h.usedPercent != null then
            (if $estimated then "≈" else "" end) + ($h.usedPercent | tostring) + "% used"
         elif .creditBalance != null then (.creditBalance | clean)
         else "—" end) +
        (if .observedAt == null or .ageSeconds == null then " (no reading)"
         elif .ageSeconds >= $maxAge then " (old)" else "" end)
    ] | if length == 0 then "Pulse —" else join(" · ") end |
    if $format == "tmux" then gsub("#"; "##") else . end
'
