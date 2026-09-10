#!/bin/bash
# Set as an item's script. NAME is supplied by sketchybar.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
directory="$(dirname "$0")"
if ! label="$(/bin/bash "$directory/pulse-status.sh")"; then
    label="Pulse —"
fi
sketchybar --set "${NAME:-pulse}" label="$label"
