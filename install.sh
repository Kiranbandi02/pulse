#!/bin/bash
# Installs (or updates) Pulse into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/Kiranbandi02/pulse/main/install.sh | bash
#   ... | bash -s -- --uninstall
set -euo pipefail

REPO="${PULSE_REPO:-Kiranbandi02/pulse}"
URL="${PULSE_ZIP_URL:-https://github.com/$REPO/releases/latest/download/Pulse.zip}"
DEST=/Applications/Pulse.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ "$(uname -s)" = "Darwin" ] || { echo "Pulse is for macOS only."; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  pkill -x Pulse 2>/dev/null || true
  rm -rf "$DEST"
  defaults delete com.kiranbandi.pulse 2>/dev/null || true
  echo "✓ Pulse removed."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "▸ Downloading Pulse…"
curl -fsSL "$URL" -o "$tmp/Pulse.zip" || { echo "Download failed: $URL"; exit 1; }
ditto -x -k "$tmp/Pulse.zip" "$tmp"
[ -d "$tmp/Pulse.app" ] || { echo "Unexpected archive contents."; exit 1; }

pkill -x Pulse 2>/dev/null || true
rm -rf "$DEST"
ditto "$tmp/Pulse.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
"$LSREGISTER" -f "$DEST"
open "$DEST"
echo "✓ Pulse installed in /Applications. Add the widget via right-click on desktop → Edit Widgets → System Pulse."
