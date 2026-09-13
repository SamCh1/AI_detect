# AGENTS.md

Entry point for coding agents. If you are Claude Code, read
[`CLAUDE.md`](CLAUDE.md) instead — it is the fuller hub and supersedes this file.

## What this repo is

A Home Assistant add-on repository holding **two independent applications** that
share nothing but a git remote. No shared code, no shared dependencies, no shared
runtime.

| App | What it is | Stack | Runs on |
|---|---|---|---|
| [`simple_ai_vision/`](simple_ai_vision/AGENTS.md) | HA add-on. Snapshot → AI Vision → keyword match → Telegram | FastAPI + requests + uvicorn, nothing else | Alpine container, port 8000 |
| [`fall_detection_web/`](fall_detection_web/AGENTS.md) | Standalone web app. RTSP → YOLOv8 → AI verify → Telegram + video | FastAPI, torch/ultralytics (CPU), SQLite, Redis, Teldrive | venv + systemd on a VPS, port 8090 |

**Read the per-app `AGENTS.md` for whichever app you are touching.** Each carries its
own stack rules, file map and constraints, and they differ sharply.

**Upstream:** this is a fork. `repository.yaml` names
`minhhungtsbd/my_hass_addon_public` as upstream; `origin` is `SamCh1/AI_detect`.
Attribute upstream design decisions to upstream.

## The five rules that bite

1. **Bump the add-on version for add-on changes.** Any change to `simple_ai_vision/`
   must bump `version:` in `simple_ai_vision/config.yaml` (`make bump`) — the HA
   Add-on Store keys its update offer off that field, so an unbumped change never
   reaches a user and fails *silently*. A change to `fall_detection_web/` must **not**
   touch it.

2. **`cd` into the app directory before running it.** Both apps define `app.py` and
   both start as `uvicorn app:app` — a bare module reference resolved against the
   working directory. From the repo root you get an import error, or worse, the
   *other* app. Every `make dev*` recipe does the `cd` for you.

3. **One venv per app, inside the app** — `simple_ai_vision/.venv` and
   `fall_detection_web/.venv`, both created by `uv sync --locked`. The add-on has a
   hard three-dependency ceiling and an explicit DO-NOT-ADD list; the separation plus
   `uv.lock` is what enforces it. In a shared env an accidental `import torch` would
   just work.

4. **There is no test suite, no linter and no CI.** Nothing here mechanically checks a
   change. `make check` byte-compiles both apps and proves syntax, nothing more. Say
   what you actually ran and actually observed — never call a change "verified" or
   "passing". If you could not run the app, say that.

5. **UTF-8 everywhere, and prose docs are English** — but a few strings are
   Vietnamese *because they are data, not prose*: the `cháy` keyword in the add-on's
   keyword list, the default AI prompts in `fall_detection_web/config.py`, and camera
   / go2rtc stream names like `bep` and `h9ccam2_sub`. Translating an identifier
   changes behaviour. Do not "fix" them.

## Run it

Every target runs from the repo root. Both apps are driven from one Makefile.

```bash
make setup    # both venvs + .env, then a readiness report — start here
make doctor   # health check: pythons, venvs, .env, docker, code indexes
make preflight # can this machine run make dev right now? verdict + exit code
make dev      # run both apps together (vision :8000, fall :8090)
make logs     # follow every log this repo produces (app.log + containers)
make check    # byte-compile both apps
make bump     # bump the add-on version
make help     # every target, with descriptions
```

`make dev-vision` (:8000) and `make dev-fall` (:8090) run one app alone. `make reset`
deletes both venvs and re-runs setup.

Three things `make setup` handles that bite if you do it by hand:

- **`uv` is the only prerequisite** — it installs Python 3.11 itself. Do not install
  Python by hand; both apps pin 3.11 via `.python-version`.
- **One venv per app, inside the app** — `simple_ai_vision/.venv` and
  `fall_detection_web/.venv`. See rule 3; this is what enforces the add-on's ceiling.
- **`requirements.txt` is a generated export of `uv.lock`** in both apps. Never
  hand-edit it — change `pyproject.toml` and run `make lock`.
- **`fall_detection_web` gets a `.env`** copied from `.env.example` if absent, never
  overwriting an existing one. It is optional — config falls back to SQLite.

`fall_detection_web`'s `data/`, `.env` and `*.pt` model weights are gitignored.

## Committing

Commit when you are asked to, not automatically after each edit. Do not push to the
remote unless the request was explicit.

## Where to read next

| File | Read it when |
|---|---|
| [`simple_ai_vision/AGENTS.md`](simple_ai_vision/AGENTS.md) | touching the add-on — dependency ceiling, DO-NOT-ADD list, release rule |
| [`fall_detection_web/AGENTS.md`](fall_detection_web/AGENTS.md) | touching the web app — stack, threading, caching, route ordering |
| [`CLAUDE.md`](CLAUDE.md) | Claude Code specifics — RTK, code intelligence, agent tooling |
| `*/CLAUDE.md` | nothing new — a symlink to that directory's `AGENTS.md`, so Claude Code picks it up too |
| `.codesight/` | committed inventory of routes, libraries and env vars |
| `simple_ai_vision/README.md` | add-on install, HA automation wiring |
| `fall_detection_web/README.md` | VPS setup, go2rtc, systemd, `.env` keys |
