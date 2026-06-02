#!/usr/bin/env bash
# Step 1: ingest server. Listens for the phone's RTMP push and republishes it
# as a local RTSP feed that the segmenter (step 2) reads.
#
#   phone (Larix) --RTMP--> MediaMTX --RTSP--> ffmpeg
#
# MediaMTX binary location can be overridden with $MEDIAMTX. See setup.sh.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIAMTX="${MEDIAMTX:-$HOME/mediamtx/mediamtx}"

if [[ ! -x "$MEDIAMTX" ]]; then
  echo "MediaMTX not found at: $MEDIAMTX" >&2
  echo "Run ./setup.sh first (or set \$MEDIAMTX to the binary path)." >&2
  exit 1
fi

exec "$MEDIAMTX" "$HERE/mediamtx.yml"
