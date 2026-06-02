# phone-vlm-narrator

Turn your phone into a live "eyes" feed for a **local vision-LLM**. Point your
phone camera at something, and a self-hosted model (e.g. Qwen3-VL on vLLM)
narrates what it sees in near real time — all on your own hardware, no cloud.

```
📱 phone camera
   │  RTMP push over your LAN (Larix Broadcaster, etc.)
   ▼
🖥️ MediaMTX            ← 1-ingest.sh   (accepts the stream, republishes as RTSP)
   │  rtsp://127.0.0.1:8554/live/phone
   ▼
🎞️ ffmpeg              ← 2-segment.sh  (chops feed into short, downscaled clips)
   │  clips/clip_00000.mp4, clip_00001.mp4, …
   ▼
🤖 vLLM (vision-LLM)   ← 3-narrate.py  (sends newest clip, streams a narration line)
```

> **Why clips, not a stream?** Inference servers like vLLM don't accept an open,
> growing video — every request is a *finite* set of frames. So we slice the live
> feed into short clips and feed them one at a time. It's **near-real-time**
> (a few seconds of lag, dominated by the vision encode), not instant.

## Prerequisites

- A running **OpenAI-compatible vLLM server** serving a video-capable VLM
  (developed against **Qwen3-VL / Qwen3.5-VL**). See [vLLM serving](#vllm-serving).
- **ffmpeg** on the server (`ffmpeg -version`).
- **Python 3.9+** with the `openai` package (installed by `setup.sh`).
- A phone app that pushes **RTMP**, e.g. **Larix Broadcaster** (iOS/Android, free).
- Phone and server on the **same LAN**.

## Setup

```bash
git clone https://github.com/kosminus/phone-vlm-narrator.git
cd phone-vlm-narrator
./setup.sh          # downloads MediaMTX into ~/mediamtx, installs openai
```

### vLLM serving

Serve a video-capable model with multimodal + local-file access enabled. Example
for Qwen3.5/3.6-VL FP8:

```bash
vllm serve /path/to/Qwen3.6-27B-FP8 \
  --served-model-name qwen3.6-27b \
  --limit-mm-per-prompt '{"video": 1}' \
  --allowed-local-media-path /absolute/path/to/phone-vlm-narrator/clips \
  --mm-processor-kwargs '{"fps": 2, "max_pixels": 501760}' \
  --max-num-batched-tokens 16384 \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.90
```

Key flags (easy to miss):
- `--limit-mm-per-prompt '{"video": 1}'` — the default video cap is **0**, so
  video is rejected unless you set this.
- `--allowed-local-media-path <clips dir>` — required for the `file://` paths the
  narrator sends. Must be the **absolute** path to this repo's `clips/`.
- **`--max-num-batched-tokens` *is* the encoder cache size.** A single video clip
  must fit entirely within it. If you see *"exceeds the pre-allocated encoder
  cache size"*, raise this value (the error's hint about `--limit-mm-per-prompt`
  is misleading).

## Run order (strict)

Each stage connects to the previous one, so start them in order:

| # | Terminal | Command |
|---|----------|---------|
| 1 | vLLM | (your `vllm serve …` above) |
| 2 | ingest | `./1-ingest.sh` |
| 3 | **phone** | start broadcasting (see below), wait for the "is publishing" log |
| 4 | segmenter | `./2-segment.sh` |
| 5 | narrator | `python3 3-narrate.py` |

The RTSP path doesn't exist until the phone is publishing — so start the
segmenter **after** the phone is live, or it'll fail to connect.

### Phone setup (Larix Broadcaster)

1. New connection → **Publish**, URL: `rtmp://<SERVER_LAN_IP>:1935/live/phone`
   (find the server IP with `ip -4 addr`).
2. Optional: drop capture resolution to 720p / a few Mbps (we downscale anyway).
3. Tap broadcast. MediaMTX should log `... is publishing to path 'live/phone'`.

You'll then see narration appear live:

```
[18:42:07] clip_00004.mp4 -> A person walks across a kitchen and opens the fridge.
[18:42:11] clip_00005.mp4 -> They take out a bottle and pour a drink at the counter.
```

## Configuration

All knobs are environment variables with sane defaults:

| Variable | Default | Used by | Meaning |
|----------|---------|---------|---------|
| `MEDIAMTX` | `~/mediamtx/mediamtx` | 1-ingest | MediaMTX binary path |
| `RTSP_URL` | `rtsp://127.0.0.1:8554/live/phone` | 2-segment | feed to read |
| `SEGMENT_SECONDS` | `4` | 2-segment | clip length |
| `SCALE_WIDTH` | `854` | 2-segment | downscale width (≈480p) |
| `CLIPS_DIR` | `./clips` | 2-segment, 3-narrate | clip folder |
| `VLLM_URL` | `http://localhost:8000/v1` | 3-narrate | model endpoint |
| `MODEL` | `qwen3.6-27b` | 3-narrate | served model name |
| `HISTORY` | `4` | 3-narrate | recent lines fed back for continuity |
| `PROMPT` | (narration instruction) | 3-narrate | what to ask per clip |

## Tuning & notes

- **Lagging behind?** The narrator auto-drops backlog (always grabs the newest
  finished clip). To ease load: raise `SEGMENT_SECONDS`, lower `SCALE_WIDTH`, or
  lower vLLM's `fps`.
- **More detail per clip?** Raise vLLM's `fps` / `max_pixels` — but watch the
  encoder budget; bump `--max-num-batched-tokens` if you hit the cache error.
- **Continuity** is carried as a short *text* summary of recent narration, never
  by re-sending old frames (that would re-pay the full vision encode).
- **One stream ≈ one busy GPU.** Real-time per-clip analysis keeps the model
  saturated; don't expect many concurrent streams from one instance.

## License

MIT — see [LICENSE](LICENSE).
