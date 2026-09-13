# AI_detect

Two independent AI camera applications that share a git remote and nothing else — no
shared code, no shared dependencies, no shared runtime.

| | [Simple AI Vision](./simple_ai_vision) | [Fall Detection Web](./fall_detection_web) |
|---|---|---|
| **What** | Home Assistant add-on | Standalone web app |
| **Does** | Snapshot → AI Vision → keyword match → Telegram | RTSP → YOLOv8 → AI verify → Telegram + recorded video |
| **Stack** | FastAPI + requests + uvicorn | FastAPI, torch/ultralytics (CPU), SQLite, Redis, Teldrive |
| **Runs on** | Alpine container via HA Supervisor, port 8000 | venv + systemd on a VPS, port 8090 |
| **Triggered by** | a Home Assistant automation calling `/analyze` | its own capture threads, continuously |
| **Docs** | [`simple_ai_vision/README.md`](./simple_ai_vision/README.md) | [`fall_detection_web/README.md`](./fall_detection_web/README.md) |

Pick the one you need — each README is self-contained. This file covers only what
applies to the repository as a whole.

## Simple AI Vision

A lightweight add-on that answers one question about one JPEG: *does this snapshot
match something I care about?*

```text
HA automation trigger (typically a Frigate person event on MQTT)
  → POST /analyze  {"camera": "bep"}
  → snapshot from go2rtc, falling back to Frigate's latest frame
  → OpenAI-compatible Vision API
  → keyword matching
  → Telegram sendPhoto + event log
```

It does not poll cameras. A Home Assistant automation decides when `/analyze` runs, so
the add-on stays idle — and under 150 MB of RAM — until something asks it a question.
The trigger is usually a Frigate person event on MQTT, handled entirely by the HA
automation; the add-on itself speaks only HTTP and takes a single `camera` name.

Cameras, prompt profiles, keywords and credentials are managed from the built-in web
UI. Full settings reference, API, and automation examples:
[`simple_ai_vision/README.md`](./simple_ai_vision/README.md).

### Install it in Home Assistant

1. **Settings → Add-ons → Add-on Store**.
2. Open the **⋮** menu (top right) → **Repositories**.
3. Add: `https://github.com/SamCh1/AI_detect`
4. **Add**, then find **Simple AI Vision** in the store.
5. **Install**, **Start**, then **Open Web UI** to configure it.

You will need Home Assistant OS or Supervised (the Add-on Store must be available), an
API key from an OpenAI-compatible vision provider, and a Telegram bot token and chat
ID. Snapshots come from go2rtc or Frigate — one of the two must be reachable.

## Fall Detection Web

A multi-camera monitoring app that watches continuously rather than waiting to be
asked.

```text
RTSP / go2rtc streams
  → threaded YOLOv8 person detection (CPU)
  → AI Vision scene validation
  → verdict: SAFE | EMERGENCY
  → Telegram photo alert
  → incident video → Teldrive upload
  → timeline, recordings hub, dashboard
```

It is **not** a Home Assistant add-on and is not installed through the Add-on Store.
It runs as a normal Python service — typically under systemd on a VPS, behind a login.
Setup, go2rtc, Teldrive and Redis instructions:
[`fall_detection_web/README.md`](./fall_detection_web/README.md).

## Local development

New here? [`docs/getting-started.md`](docs/getting-started.md) is the walkthrough —
installing `uv`, what a healthy first run prints, and the fixes for the handful of
things that go wrong. The summary below is the reference version.

```bash
make setup    # both venvs + .env, then a readiness report — start here
make doctor   # what is installed, what is missing, what to run next
make preflight # ready for make dev? pass/fail, exits non-zero when not
make dev      # run both apps together, labelled streams
make logs     # follow app.log and any running container
make help     # every target
```

`make dev-vision` (:8000) and `make dev-fall` (:8090) run one app alone.

Two things the Makefile exists to enforce:

- **`uv` is the only prerequisite.** It installs Python 3.11 itself — do not install
  Python by hand. Both apps pin 3.11 via `.python-version`, matching the add-on's
  `python:3.11-alpine` image, so a local venv and the shipped container run the same
  interpreter.
- **One virtualenv per app, inside the app.** `simple_ai_vision/.venv` holds exactly
  three packages; `fall_detection_web/.venv` holds torch and YOLO. Sharing one env
  would silently let the add-on import dependencies it must never ship with, and
  `uv.lock` now makes an accidental one impossible to install rather than merely
  discouraged.
- **`requirements.txt` is generated, never hand-edited.** Both apps resolve through
  `pyproject.toml` + `uv.lock`; `make lock` re-resolves and re-exports. The exports
  exist because both deploy paths still install with pip — the add-on's Dockerfile and
  the VPS systemd venv.

There is no test suite, linter or CI. `make check` byte-compiles both apps, which
proves they parse and nothing more.

## Repository layout

```text
simple_ai_vision/      the Home Assistant add-on
fall_detection_web/    the standalone web app
Makefile               every command; `make help` lists them
CLAUDE.md              instructions for Claude Code
AGENTS.md              instructions for other coding agents
docs/                  code-intelligence setup notes
.codesight/            committed inventory of routes, libraries and env vars
repository.yaml        Home Assistant add-on repository manifest
```

Changing the add-on requires bumping its version in `simple_ai_vision/config.yaml`
(`make bump`) — the HA Add-on Store keys its update offer off that field, so an
unbumped change never reaches anyone. Changes to `fall_detection_web` must leave it
alone.

## Upstream

This repository is a fork. `repository.yaml` names
[`minhhungtsbd/my_hass_addon_public`](https://github.com/minhhungtsbd/my_hass_addon_public)
as the upstream project; this fork lives at
[`SamCh1/AI_detect`](https://github.com/SamCh1/AI_detect). `fall_detection_web` was
added here and is not part of upstream.
