# Local camera simulation on macOS

How to run `fall_detection_web` end to end on a MacBook with **no IP camera**,
using the built-in webcam as the video source via go2rtc.

Both apps in this repo are clients of an external go2rtc — neither one talks to
a camera directly, and `simple_ai_vision` has no RTSP code at all. So "set up a
camera" really means "stand up a go2rtc and give it something to serve." This
document gives it the MacBook camera.

Everything below was verified on macOS 26 (Darwin 25.6) / Apple Silicon with
go2rtc 1.9.14. If you are on Intel, substitute `go2rtc_mac_amd64.zip` in step 2.

Related: [`getting-started.md`](getting-started.md) covers `uv` and the venvs —
do that first. This document assumes `make setup` has already succeeded.

---

## 1. Install ffmpeg

go2rtc shells out to `ffmpeg` for any non-RTSP source, including the webcam, and
`fall_detection_web` uses it as its fallback clip recorder.

```bash
brew install ffmpeg
```

## 2. Install go2rtc

macOS ships as a **zip**, unlike the bare Linux binary the app READMEs reference.
Downloading the Linux URL on a Mac produces a file that will not execute.

```bash
mkdir -p ~/go2rtc && cd ~/go2rtc && curl -L -o go2rtc.zip https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_mac_arm64.zip && unzip -o go2rtc.zip && chmod +x go2rtc && xattr -dr com.apple.quarantine go2rtc && rm go2rtc.zip
```

`xattr -dr com.apple.quarantine` strips Gatekeeper. go2rtc is not notarized, so
macOS refuses to run it otherwise. This is the standard path for unsigned
open-source CLI tools, and it is scoped to the one file you just downloaded.

## 3. Find your camera's device index

```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A8 "video devices"
```

The built-in camera is normally `[0]`. **Re-run this whenever you connect or
disconnect a device** — plugging in an iPhone (Continuity Camera) inserts itself
into the list and shifts every index after it.

## 4. Write the config

```bash
cat > ~/go2rtc/go2rtc.yaml <<'YAML'
api:
  listen: "127.0.0.1:1984"
rtsp:
  listen: "127.0.0.1:8554"
webrtc:
  listen: "127.0.0.1:8555"
streams:
  bep: "ffmpeg:device?video=0&resolution=1280x720&framerate=30#video=h264"
YAML
```

Two things here are load-bearing.

**`framerate=30` is mandatory.** ffmpeg defaults to 29.97 fps for avfoundation,
which Apple cameras reject outright:

```
Selected framerate (29.970030) is not supported by the device.
Supported modes: 1280x720@[15.000000 30.000000]fps
Error opening input: Input/output error
```

go2rtc swallows this. The stream registers, `/api/frame.jpeg` returns **HTTP 200
with zero bytes**, and nothing in the go2rtc log says why. Omitting the framerate
is the single most likely reason a first setup appears to work but produces no
image.

**`127.0.0.1` on every listener is deliberate.** go2rtc's default is `:1984`,
meaning all interfaces, with **no authentication** — and its API exposes
`api/config` and `api/restart`, while its config format supports `exec:` sources
that run arbitrary commands. An unauthenticated go2rtc reachable from the local
network is a remote shell. Both apps run on the same machine, so binding to
localhost costs nothing.

## 5. Start go2rtc

Leave this running in its own terminal tab.

```bash
cd ~/go2rtc && ./go2rtc
```

## 6. Verify both stream paths

In a second tab. These are **separate code paths** in the app — snapshots go over
HTTP, YOLO capture goes over RTSP — so check both.

```bash
curl -s -w "HTTP %{http_code} bytes=%{size_download}\n" -o /tmp/snap.jpg "http://127.0.0.1:1984/api/frame.jpeg?src=bep" && open /tmp/snap.jpg
```

Expect a few hundred KB and a photo of yourself. `bytes=0` means the stream is
failing silently — see Troubleshooting.

```bash
ffprobe -v error -rtsp_transport tcp -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate -of default=nw=1 rtsp://127.0.0.1:8554/bep
```

Expect `codec_name=h264`, `1280x720`, `avg_frame_rate=30/1`.

## 7. Configure the AI provider

`fall_detection_web` requires an **OpenAI-compatible** vision endpoint. It POSTs
to `{ai_base_url}/chat/completions` with `Authorization: Bearer`, and sends the
image as a base64 data URL (`ai.py`).

Google's **native** Gemini API is not OpenAI-compatible — it uses
`/models/{model}:generateContent`, an `X-goog-api-key` header and a
`contents[].parts[]` body. Point the app at it and every call 404s. Google ships
a separate OpenAI-compatible gateway; use that:

```
https://generativelanguage.googleapis.com/v1beta/openai
```

Edit `fall_detection_web/.env` — every key ships commented out, so **remove the
leading `#`** or nothing applies:

```
AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai
AI_API_KEY=your-key-here
VISION_MODEL=gemini-3.5-flash-lite
VERIFY_INTERVAL=60
```

### Choosing a model: RPD is the constraint

On Gemini's free tier, **most Flash-class models are capped at 20 requests per
day**. At the default `VERIFY_INTERVAL=20`, that is about seven minutes of
monitoring. The two exceptions are worth 25x more:

| Model | RPM | RPD |
|---|---|---|
| `gemini-3.5-flash-lite` | 15 | **500** |
| `gemini-3.1-flash-lite` | 15 | **500** |
| `gemini-2.5-flash` and most Flash models | 5 | 20 |

Check your own numbers at <https://aistudio.google.com/rate-limit> — Google no
longer publishes a static table.

`fall_detection_web` retries with a second model on any primary failure,
including a 429, and the quotas are **per model** — so setting a fallback gives
you roughly 1,000 free calls a day. Set it at **Settings → Fallback Vision
Model** in the web UI, to `gemini-3.1-flash-lite`.

It must go in the UI, not `.env`: `fallback_vision_model` is absent from
`ENV_CONFIG_KEYS` in `config.py`, so the file cannot set it.

### Free tier trains on your images

Google's pricing page marks "content used to improve our products" as **Yes** for
the free tier and **No** for paid. This app sends a JPEG of whatever the camera
sees every time YOLO detects a person. On your own webcam for development that is
a fair trade. Pointing it at a room with other people in it is a decision to make
deliberately, not by default.

## 8. Run the app

```bash
cd /path/to/AI_detect && make dev-fall
```

`simple_ai_vision` is the Home Assistant add-on and is not part of this flow; use
`make dev` only if you want both.

First boot loads torch and YOLO — allow 10-20 seconds before :8090 answers.

Open <http://localhost:8090>, log in with `admin` / `admin`, then:

**Settings**
- go2rtc URL: `http://127.0.0.1:1984`
- Fallback Vision Model: `gemini-3.1-flash-lite`
- Leave AI Base URL, API Key and Vision Model **alone** — `.env` owns them, and
  `config.py`'s `write_config` silently skips saving any key that env supplies.

**Cameras → Add Camera**
- Name / go2rtc source: `bep`
- RTSP fallback: `rtsp://127.0.0.1:8554/bep`
- Live Mode: `Automatic: go2rtc iframe`
- Live URL: leave empty

Press **Start**, then walk in front of the camera. Follow the pipeline with:

```bash
cd /path/to/AI_detect && make logs
```

A healthy cycle logs `[AI] verifying scene image=...` followed by
`[AI] latency=1.2s result=SAFE description='...'`.

To exercise the `EMERGENCY` path you have to satisfy the prompt in `config.py`,
which looks for a person fallen or lying on the ground. A laptop camera is
face-level and narrow, so this means lying on the floor in front of it. An iPhone
as Continuity Camera (`video=1`, after re-checking the index) propped across the
room gives a far better angle for this.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `frame.jpeg` returns HTTP 200, `bytes=0` | Missing `framerate=30`; ffmpeg's 29.97 default is rejected | Step 4 |
| ffmpeg opens the camera and hangs forever, no frames | macOS camera permission not granted | System Settings → Privacy & Security → Camera → enable Terminal, then **fully quit** Terminal (⌘Q) and restart |
| Camera green light stays on with nothing running | Orphaned ffmpeg holding the device | `pkill -9 -f avfoundation` |
| `[AI] HTTP Error 400` naming the model | Wrong model ID, or native Gemini URL instead of the `/openai` gateway | Step 7 |
| AI settings changed in the UI do not stick | `.env` supplies that key; `write_config` skips it | Edit `.env`, restart |
| `read tcp ...: i/o timeout` against an external RTSP source | TCP connected, the server never answered — the source is not actually serving | Not a go2rtc problem. Probe it directly: `printf 'OPTIONS rtsp://HOST:PORT/PATH RTSP/1.0\r\nCSeq: 1\r\n\r\n' \| nc -w 6 HOST PORT` |
| Phone RTSP app: port accepts, zero bytes back | iOS/Android suspended the app; the kernel still completes the handshake | Keep the app in the foreground, disable auto-lock |

### Teardown

```bash
pkill -f go2rtc
```

The config and binary stay in `~/go2rtc`; nothing is installed system-wide and
nothing in this repository is modified by any of the above.
