# CLAUDE.md

Agent hub for this repo. Read this first, then the per-app `AGENTS.md` for whichever
app you are touching.

## What this repo is

A Home Assistant add-on repository containing **two independent applications** that
share nothing but a git remote. There is no shared code, no shared dependency set,
and no shared runtime.

| App | What it is | Stack | Runs on |
|---|---|---|---|
| `simple_ai_vision/` | HA add-on. Snapshot → AI Vision → keyword match → Telegram | FastAPI + requests + uvicorn, nothing else | Alpine container, port 8000 |
| `fall_detection_web/` | Standalone web app. RTSP → YOLOv8 → AI verify → Telegram + video | FastAPI, torch/ultralytics (CPU), SQLite, Redis, Teldrive | venv + systemd on a VPS, port 8090 |

Roughly 6,600 lines of Python across 10 files. `simple_ai_vision` is ~2,600 LOC /
10 routes; `fall_detection_web` is ~4,000 LOC / 35 routes.

**Upstream:** this is a fork. `repository.yaml` names `minhhungtsbd/my_hass_addon_public`
as the upstream project; `origin` is `SamCh1/AI_detect`. Attribute upstream design
decisions to upstream — do not describe them as this fork's choices.

## RTK (Token-Optimized Commands)

Globally installed. Prefix **every** command with `rtk` — including in `&&` chains.
Examples: `rtk git diff`, `rtk cargo test`, `rtk grep pattern`, `rtk gh pr view 42`.
Saves 60–90% tokens. Full reference: `~/.claude/CLAUDE.md`.

## Conventions that bite

These are the ones that fail a build, break a deploy, or produce a silently wrong
result. The full constraint lists live in each app's `AGENTS.md`.

1. **The two apps are independent.** A change to `fall_detection_web` must NOT bump
   the version in `simple_ai_vision/config.yaml`. A change to `simple_ai_vision`
   MUST bump it — the HA Add-on Store uses that version to offer the update, so an
   unbumped add-on change never reaches a user.

2. **Both apps define `app.py`, and both are started as `uvicorn app:app`.** That is
   a bare module reference resolved against the current working directory. Run it
   from the repo root and you either get an import error or the *other* app. Always
   `cd` into the app directory first.

3. **`simple_ai_vision` has a hard dependency ceiling.** FastAPI, requests, uvicorn,
   paho-mqtt, stdlib. Its `AGENTS.md` carries an explicit ~25-entry "DO NOT ADD"
   list — no database, no ORM, no Redis, no OpenCV, no ffmpeg, no auth. Target is
   under 150 MB RAM idle with no background loops. Adding a dependency here is a
   design change, not an implementation detail.

4. **`fall_detection_web` has the opposite posture** — torch, YOLO, Redis and
   threading are all approved there. Do not carry `simple_ai_vision`'s minimalism
   into it, or its stack into `simple_ai_vision`.

5. **Snapshots come from go2rtc** (`/api/frame.jpeg?src={camera}`) or an HA camera
   entity. Never implement RTSP decoding by hand in `simple_ai_vision`.

6. **Add-ons must stay `amd64` + `aarch64` clean.** No distro-specific assumptions,
   no x86-only wheels.

7. **AI providers must be OpenAI-compatible**, image input as a base64 data URL.

8. **UTF-8 everywhere, and all prose docs are English.** A handful of strings stay
   Vietnamese on purpose because they are *data, not prose* — do not "fix" them:
   the `cháy` entry in the Simple AI Vision keyword list (it matches Vietnamese AI
   output, and English `fire` is already a separate entry), camera and go2rtc
   stream names such as `bep` and `h9ccam2_sub`, prompt-profile titles, and the
   automation aliases in the README examples. Translating an identifier changes
   behaviour; translating a caption does not.

## Running and verifying

```bash
cd simple_ai_vision    && rtk uvicorn app:app --host 0.0.0.0 --port 8000
cd fall_detection_web  && rtk uvicorn app:app --host 0.0.0.0 --port 8090
```

`fall_detection_web` expects a venv and a `.env` — see `fall_detection_web/.env.example`
and its README. Its `data/`, `.env` and `*.pt` model weights are gitignored.

**There is no test suite, no linter config, and no CI in this repo.** Nothing here
mechanically checks a change. Do not claim a change is "verified" or "passing" — say
what you actually ran and what you actually observed. If you could not run the app,
say that instead.

## Agent tooling installed here

**GSD Core v1.13.0**, `core` profile, installed **locally** to `.claude/` and
deliberately excluded from git (see `.git/info/exclude`). Eight commands, zero
agents, ~700 cold-start tokens.

- `/gsd-phase` · `/gsd-plan-phase` · `/gsd-discuss-phase` · `/gsd-execute-phase`
- `/gsd-new-project` · `/gsd-surface` · `/gsd-update` · `/gsd-help`

Two things to know before acting on its output:

- **`/gsd-onboard` is not installed.** It belongs to the `core_loop` *cluster*, which
  is not the same list as the `core` *profile*. Add it with
  `/gsd-surface enable core_loop` — never by re-running the installer bare, which
  would silently upgrade this repo to the full ~12k-token profile.
- **Health check `W010` ("No GSD agents found") is expected**, and its suggested fix
  is wrong for this repo. The `core` profile excludes all agents on purpose. Ignore
  it. `E002`/`E003`/`E004` for `PROJECT.md`/`ROADMAP.md`/`STATE.md` are likewise
  expected until the repo is onboarded.

`.planning/` is local-only: `planning.commit_docs=false` and
`planning.search_gitignored=true` are set in `.planning/config.json`. The second one
is load-bearing — without it, ignoring `.planning/` would make GSD's own searches
skip its own planning docs.

⚠️ **`git clean -fdx` destroys the entire local agent layer** (GSD, and any index
built later). Ordinary git operations are safe; that one is not.

## The two-tier config split

`.claude/settings.json` is the **designated** committed team layer — anything a
reviewer relies on belongs there. It does not exist yet; nothing team-wide has
needed it. `.claude/settings.local.json` is personal and gitignored, and GSD's 18
hooks live there. Never move a hook the other way: a hook that runs only on one
machine is indistinguishable from a hook that does not exist.

## Known drift

- `fall_detection_web/AGENTS.md:55` cites `design-system/MASTER.md`. **That file does
  not exist anywhere in this repo.** Until it is written, treat the design system as
  undocumented and follow the existing templates in `fall_detection_web/templates/`
  rather than inventing rules. Do not cite that path as though it resolves.

## Pointers

| File | Read it when |
|---|---|
| `simple_ai_vision/AGENTS.md` | touching the add-on — carries the full DO-NOT-ADD list |
| `fall_detection_web/AGENTS.md` | touching the web app — stack, caching strategy, threading rules |
| `simple_ai_vision/README.md` | add-on install, HA automation wiring, `rest_command` examples |
| `fall_detection_web/README.md` | VPS setup, go2rtc, systemd service, `.env` keys |
| `README.md` (root) | repository-level overview, in Vietnamese |

When something surprises you, add a numbered entry to **Conventions that bite** above.
If that section outgrows this file, split it into `docs/claude/gotchas.md` and link it
from here — do not let this hub grow past ~200 lines.
