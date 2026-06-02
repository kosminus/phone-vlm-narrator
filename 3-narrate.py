#!/usr/bin/env python3
"""Step 3: watch the clips folder and narrate the live feed with a vision-LLM.

Design choices that matter for a real-time feed:
  * Always jump to the NEWEST finished clip and drop any backlog. If inference
    is slower than the stream, we skip stale clips instead of falling behind.
  * Carry a short rolling TEXT summary of recent narration into each prompt for
    continuity -- never re-send old frames (that re-pays the whole vision cost).
  * Stream the model's output token-by-token so narration appears live.

Config via environment variables (sensible defaults shown):
  CLIPS_DIR   directory the segmenter writes to       (./clips)
  VLLM_URL    OpenAI-compatible base URL              (http://localhost:8000/v1)
  MODEL       served model name                       (qwen3.6-27b)
  HISTORY     how many recent lines to feed back      (4)
  PROMPT      narration instruction (advanced)
"""
import glob
import os
import time
from collections import deque

import openai

HERE = os.path.dirname(os.path.abspath(__file__))
CLIPS = os.environ.get("CLIPS_DIR", os.path.join(HERE, "clips"))
BASE_URL = os.environ.get("VLLM_URL", "http://localhost:8000/v1")
MODEL = os.environ.get("MODEL", "qwen3.6-27b")
HISTORY = int(os.environ.get("HISTORY", "4"))
INSTRUCTION = os.environ.get(
    "PROMPT",
    "This is the next few seconds of a live camera feed. In one or two "
    "sentences, narrate what is happening now. Do not repeat earlier narration.",
)

client = openai.OpenAI(base_url=BASE_URL, api_key="x")
recent: deque[str] = deque(maxlen=HISTORY)
seen: set[str] = set()


def newest_finished_clip():
    """Newest clip ffmpeg has finished writing.

    The last file is still being written, so the one before it is the newest
    safe-to-read clip.
    """
    clips = sorted(glob.glob(os.path.join(CLIPS, "clip_*.mp4")))
    if len(clips) < 2:
        return None
    return clips[-2]


def narrate(path: str):
    context = ""
    if recent:
        context = "Recent narration (for continuity):\n" + "\n".join(recent) + "\n\n"
    stream = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": [
            {"type": "text", "text": context + INSTRUCTION},
            {"type": "video_url", "video_url": {"url": f"file://{path}"}},
        ]}],
        stream=True,
        max_tokens=120,
    )
    print(f"\n[{time.strftime('%H:%M:%S')}] {os.path.basename(path)} -> ", end="", flush=True)
    out = []
    for chunk in stream:
        d = chunk.choices[0].delta.content
        if d:
            out.append(d)
            print(d, end="", flush=True)
    recent.append("".join(out).strip())


def main():
    print("Narrator running. Watching", CLIPS, "->", f"{MODEL} @ {BASE_URL}")
    while True:
        clip = newest_finished_clip()
        if clip and clip not in seen:
            # mark everything up to this clip as seen -> drop the backlog
            for f in sorted(glob.glob(os.path.join(CLIPS, "clip_*.mp4"))):
                seen.add(f)
                if f == clip:
                    break
            try:
                narrate(clip)
            except Exception as e:  # keep the loop alive on transient errors
                print(f"\n  (skip {os.path.basename(clip)}: {e})", flush=True)
        time.sleep(0.5)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nbye")
