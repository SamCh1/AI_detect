# AGENTS.md — Simple AI Vision

Per-app rules for `simple_ai_vision/`. Repo-wide rules (RTK, code intelligence, the
two-app split, UTF-8 policy) live in [`../CLAUDE.md`](../CLAUDE.md) — read that first.

## What this is

A Home Assistant add-on that analyses camera snapshots. One trigger path:

```
HA motion trigger → go2rtc snapshot → AI Vision API → keyword match → Telegram alert
```

~2,650 lines of Python in two files, 10 routes, three pip dependencies. The
minimalism is the product, not a stage it is growing out of.

## Files

| File | Lines | What it holds |
|---|---|---|
| `app.py` | 1,181 | Everything: routes, go2rtc fetch, AI call, keyword match, Telegram |
| `ui.py` | 1,470 | A single `INDEX_HTML = r"""…"""` raw string — the entire web UI |
| `config.yaml` | — | Add-on manifest. **The `version:` field gates every update.** |
| `Dockerfile` | — | `python:3.11-alpine`, installs requirements, runs `run.sh` |
| `run.sh` | — | `exec uvicorn app:app --host 0.0.0.0 --port 8000` |

There is no `templates/`, no `static/`, no framework. The UI is served by returning
`INDEX_HTML` from `GET /`. That is why the DO-NOT-ADD list below is enforceable:
adding a frontend build step would require inventing a whole layer that isn't here.

## Run it

`make dev-vision` from the repo root, on :8000. Setup (`uv`, the pinned 3.11, the
per-app `.venv`) is in [`../AGENTS.md`](../AGENTS.md).

## The dependency ceiling

`pyproject.toml` declares exactly three dependencies — `fastapi`, `uvicorn`,
`requests` — plus stdlib, pinned by `uv.lock`. `requirements.txt` beside it is a
**generated** export consumed by the Dockerfile; never hand-edit it, change
`pyproject.toml` and run `make lock`. **Adding a dependency here is a design change, not an implementation detail** —
raise it rather than doing it.

Never introduce: React · Vue · any frontend SPA or build step · websockets ·
database · ORM · Redis · Celery · background worker queues · Frigate integration ·
object detection models · TensorFlow · PyTorch · OpenCV · RTSP decoding ·
ffmpeg · authentication systems · user management · plugin systems.

This add-on analyses JPEG snapshots. That is the whole scope.

**Targets:** under 150 MB RAM idle, minimal CPU, no persistent background loops. The
add-on stays idle until triggered.

## State lives in `/data`

There is no database, but there *is* persistence — two files on the add-on's `/data`
volume:

- `/data/simple_ai_vision_config.json` — UI-edited options
- `/data/simple_ai_vision_events.jsonl` — append-only event log

Use these. Do not reach for SQLite because "it needs to persist something."

## Routes

`POST /analyze` is the workhorse — the trigger endpoint HA calls. The rest exist to
serve and configure the UI:

| Method | Path | |
|---|---|---|
| GET | `/health` | liveness |
| GET | `/` | returns `INDEX_HTML` |
| GET · POST | `/api/config` | read / write `/data/…config.json` |
| GET | `/api/go2rtc/streams` | stream discovery |
| GET | `/api/events` | reads the `.jsonl` log |
| GET | `/api/camera/frame` | snapshot proxy |
| POST | `/api/test-ai` · `/api/test-telegram` | UI connection tests |
| POST | `/analyze` | **the trigger path** |

Keep it flat. No routers, no versioning, no REST resource modelling.

## External contracts

- **Snapshots come from go2rtc** (`/api/frame.jpeg?src={camera}`) or an HA camera
  entity. Never hand-roll RTSP decoding here.
- **AI providers must be OpenAI-compatible** — OpenAI, OpenRouter, 9Router, Gemini
  OpenAI-compatible gateways. Image input is a **base64 data URL**.
- **Telegram via Bot API**, `sendPhoto` preferred.
- **HA Supervisor** via `SUPERVISOR_TOKEN` from the environment. There is no inbound
  auth layer and none is wanted — the add-on runs behind HA ingress
  (`ingress: true`, `homeassistant_api: true` in `config.yaml`).

## Releasing a change

**Every change to this directory must bump `config.yaml`'s `version`.** The HA Add-on
Store keys its update offer off that field, so an unbumped change never reaches a
user — it fails silently, which is the worst failure mode in this repo.

```bash
make bump            # patch bump
make bump V=1.5.0    # explicit version
```

The inverse also holds: a change to `fall_detection_web/` must **not** touch this
version.

Add-ons must stay clean on **amd64 and aarch64** — no distro-specific assumptions, no
x86-only wheels.

## Style

Short functions, explicit logic, functional over class-based, minimal abstraction. No
enterprise architecture.

Always handle: snapshot timeout · AI API timeout · Telegram failure · invalid camera
name · invalid JSON · network errors. Return clean JSON.

Log stage transitions only — snapshot fetched, AI requested, keyword matched, Telegram
sent, errors. No debug spam.

## Not implemented, on purpose

| Not here | Why | If you add it |
|---|---|---|
| MQTT | no code path, not in `requirements.txt` | optional publish-only integration, never a required runtime dependency for snapshot analysis, and no persistent subscriber loop |

## Verifying your work

There is no test suite — see rule 4 in [`../AGENTS.md`](../AGENTS.md). `make check`
byte-compiles and proves syntax, nothing more.
