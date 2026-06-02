#!/usr/bin/env bash
# Download the MediaMTX ingest server (Linux amd64) into ~/mediamtx and install
# the Python client dep. Re-run safely; it overwrites the binary in place.
set -euo pipefail

DEST="${MEDIAMTX_DIR:-$HOME/mediamtx}"
mkdir -p "$DEST"

echo "Fetching latest MediaMTX release..."
URL=$(curl -s https://api.github.com/repos/bluenviron/mediamtx/releases/latest \
  | grep -oP '"browser_download_url":\s*"\K[^"]*linux_amd64\.tar\.gz' | head -1)
[[ -n "$URL" ]] || { echo "Could not resolve release URL" >&2; exit 1; }

echo "Downloading: $URL"
curl -sL "$URL" -o /tmp/mediamtx.tar.gz
tar xzf /tmp/mediamtx.tar.gz -C "$DEST"
echo "MediaMTX installed at: $DEST/mediamtx ($("$DEST/mediamtx" --version 2>/dev/null))"

echo "Installing Python client dependency (openai)..."
pip install -q -r "$(dirname "$0")/requirements.txt"

echo "Done. Next: see README.md for the run order."
