# AGENTS.md — Fall Detection Web

Per-app rules for `fall_detection_web/`. Repo-wide rules (RTK, code intelligence, the
two-app split, UTF-8 policy) live in [`../CLAUDE.md`](../CLAUDE.md) — read that first.

## What this is

A standalone multi-camera monitoring and fall-detection web app. Not an HA add-on —
it runs under systemd on a VPS, on port 8090.

```
RTSP / go2rtc streams
  → threaded YOLOv8 person detection (CPU)
  → AI Vision scene validation (OpenAI-compatible)
  → verdict: SAFE | EMERGENCY
  → Telegram photo alert
  → incident video recording → Teldrive upload
  → timeline, recordings hub, dashboard
```

~4,000 lines of Python across 8 modules, 35 routes.

**This app has the opposite posture to `simple_ai_vision`.** Torch, YOLO, threading
and Redis are all approved here. Do not carry this stack into the add-on, and do not
carry the add-on's minimalism into here.

## Files

| File | Lines | What it holds |
|---|---|---|
| `monitor.py` | 1,344 | **The core.** Capture threads, YOLO inference, verdict pipeline, recording |
| `app.py` | 785 | FastAPI routes, page rendering, auth wiring |
| `db.py` | 621 | SQLite (WAL), events, recordings, settings table |
| `config.py` | 423 | Config resolution + `DEFAULT_CONFIG` + the default prompts |
| `ai.py` | 268 | AI Vision calls, verdict parsing |
| `teldrive.py` | 268 | Cloud upload — a local module over `requests`, **not a pip package** |
| `redis_cache.py` | 171 | Optional cache layer (see below) |
| `auth.py` | 94 | bcrypt hashing + JWT HTTP-only cookie sessions, 8-hour expiry |
| `templates/` | 4 files | `index.html`, `cameras.html`, `camera_detail.html`, `login.html` |

## Run it

`make dev-fall` from the repo root, on :8090. `make logs` follows `data/app.log`.
Setup, venvs and `.env` handling are in [`../AGENTS.md`](../AGENTS.md).

This app carries `from __future__ import annotations` in every module, so its PEP 604
unions stay strings. Keep that import when you add a module — it is why this app is not
pinned to 3.10+ the way the add-on is, even though both currently run 3.11.

`requirements.txt` is a **generated** export of `uv.lock` used by the VPS systemd venv.
Change `pyproject.toml` and run `make lock`; never hand-edit the export.

`data/`, `.env` and `*.pt` model weights are gitignored.

## Config precedence

Documented at the top of `config.py` and easy to get wrong:

```
1. environment / .env       ← secrets, container overrides
2. SQLite settings table    ← what the UI writes
3. DEFAULT_CONFIG           ← built-in defaults
```

`config.json` is **no longer written**. If one exists at startup it is migrated into
the DB and renamed `config.json.migrated`. Do not reintroduce it as a config source.

## Approved stack

- **Core:** FastAPI, Uvicorn, Jinja2, python-multipart
- **CV/AI:** PyTorch (CPU wheels), torchvision, **`opencv-python-headless`**,
  ultralytics (YOLOv8)
- **Data/auth:** SQLite in WAL mode, bcrypt, python-jose
- **Optional:** Redis, psutil
- **Cloud:** Teldrive via the local `teldrive.py`

Use `opencv-python-headless`, never plain `opencv-python` — this runs on a headless
VPS and the GUI build pulls in libraries that aren't there.

## Redis is optional — code for its absence

`redis_cache.py` guards the import, gates everything behind a `redis_enabled` config
flag, and downgrades a failed connection to a warning. **Never write a path that
assumes Redis is reachable.** Every cache read must work when it returns nothing.

Three cache tiers, in order of preference:

- **Browser HTTP cache** — `Cache-Control: private, max-age=86400, immutable`, ETags,
  `Last-Modified` on static assets and local images.
- **Local disk cache** — downloaded media (Teldrive thumbnails) under
  `data/teldrive_cache/`, so external APIs aren't re-hit.
- **Redis** — session metadata, stream status, camera availability, high-frequency
  dashboard analytics. Optional by construction.

## Routes — the ordering gotcha

`app.py` registers a catch-all page route:

```python
@app.get("/{page_name}")   # app.py:161
```

It renders `index.html` for an allowlist — `dashboard`, `prompts`, `live`,
`settings`, `tools`, `logs` — and 404s everything else.

**Two consequences.** Adding a page means adding its name to that allowlist, or it
404s. And any new *single-segment* GET route registered after line 161 is shadowed by
the catch-all — register it above, or give it a prefixed path. Multi-segment paths
(`/api/…`) are unaffected.

Nearly every route takes `Depends(auth.require_auth)`. **This app has real auth**,
unlike the add-on. New routes need that dependency unless they are deliberately
public — `/login`, `/auth/login`, `/favicon.ico`.

## Threading

Frame capture, YOLO inference, AI validation and Teldrive uploads run on isolated
threads so none can block another. Guard shared state with `threading.Lock`. Log
explicitly on API timeouts, DB transactions and stream reconnections — a silent
reconnect loop is very hard to diagnose from the outside.

## UI

Templates use raw vanilla CSS matching the existing dark (OLED) theme. No CSS
framework, no build step.

**There is no design-system document in this repo.** Earlier revisions of this file
cited `design-system/MASTER.md`; that file has never existed. Until one is written,
follow the patterns already in `templates/` rather than inventing rules — and do not
cite that path as though it resolves.

Concrete rules that hold today: no layout shift on hover (reserve the space), keep
transitions short, and match the spacing and color values already in the templates.

## Vietnamese strings are data — do not translate

`DEFAULT_VERIFY_PROMPT` in `config.py` is Vietnamese on purpose: it instructs the
model and constrains it to reply `SAFE` or `EMERGENCY`. Camera and go2rtc stream
names (`bep`, `h9ccam2_sub`) are identifiers. Translating either changes behaviour.
See rule 5 in [`../AGENTS.md`](../AGENTS.md).

## Releasing a change

This is a standalone app. A change here must **not** bump the add-on version in
`simple_ai_vision/config.yaml` — that field belongs to the add-on alone.

## Verifying your work

There is no test suite — see rule 4 in [`../AGENTS.md`](../AGENTS.md). `make check`
byte-compiles and proves syntax, nothing more.
