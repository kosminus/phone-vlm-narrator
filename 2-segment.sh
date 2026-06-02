#!/usr/bin/env bash
# Step 2: pull the live RTSP feed from MediaMTX and chop it into short,
# downscaled clips small enough to fit under vLLM's encoder budget.
#
#   SCALE_WIDTH      downscale width (480p-ish keeps the token count sane;
#                    raw 4K phone video would blow the encoder budget)
#   SEGMENT_SECONDS  length of each clip
#   audio is dropped (-an) -- the vision model ignores it
#
# Override any of these via environment variables.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RTSP_URL="${RTSP_URL:-rtsp://127.0.0.1:8554/live/phone}"
OUT="${CLIPS_DIR:-$HERE/clips}"
SEGMENT_SECONDS="${SEGMENT_SECONDS:-4}"
SCALE_WIDTH="${SCALE_WIDTH:-854}"

mkdir -p "$OUT"
rm -f "$OUT"/clip_*.mp4

echo "Reading $RTSP_URL -> $OUT/clip_*.mp4 (${SEGMENT_SECONDS}s, width ${SCALE_WIDTH})"
exec ffmpeg -hide_banner -loglevel warning \
  -rtsp_transport tcp -fflags nobuffer -i "$RTSP_URL" \
  -an -vf "scale=${SCALE_WIDTH}:-2" \
  -f segment -segment_time "$SEGMENT_SECONDS" -reset_timestamps 1 -g 60 \
  "$OUT/clip_%05d.mp4"
