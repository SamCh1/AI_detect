# Conventions that bite

The rules that fail a build, break a deploy, or produce a silently wrong result.
[`CLAUDE.md`](../../CLAUDE.md) carries these as one-line reminders; this file holds the
reasoning. The full per-app constraint lists live in each app's `AGENTS.md`.

When something surprises you, add a numbered entry here and a one-liner to the list in
`CLAUDE.md`.

---

## 1. The two apps are independent

A change to `fall_detection_web` must **not** bump the version in
`simple_ai_vision/config.yaml`. A change to `simple_ai_vision` **must** bump it
(`make bump`) — the HA Add-on Store keys its update offer off that field, so an
unbumped add-on change never reaches a user. It fails silently, which makes it the
worst failure mode in this repo.

## 2. Both apps define `app.py`, and both start as `uvicorn app:app`

That is a bare module reference resolved against the current working directory. Run it
from the repo root and you get an import error, or worse, the *other* app. Always `cd`
into the app directory first — every `make dev*` recipe does this for you, which is
most of why they exist.

## 3. `simple_ai_vision` has a hard dependency ceiling

`pyproject.toml` declares exactly three dependencies — `fastapi`, `uvicorn`,
`requests` — plus stdlib, and `uv.lock` pins them. Its `AGENTS.md` carries an explicit ~25-entry DO-NOT-ADD list: no database, no
ORM, no Redis, no OpenCV, no ffmpeg, no auth, no frontend build step. Target is under
150 MB RAM idle with no background loops.

Adding a dependency here is a design change, not an implementation detail.

One venv per app, inside the app, is what enforces this. In a shared env an accidental
`import torch` would just work, and the breakage would only surface when the add-on
image was built — `uv.lock` now makes the accident uninstallable rather than merely
discouraged.

`requirements.txt` is a **generated** export of `uv.lock` consumed by the Dockerfile's
`pip install`. Never hand-edit it; change `pyproject.toml` and run `make lock`. The
export carries `--emit-index-url`, which is load-bearing: without it the file names
`torch==2.5.1+cpu` but omits `download.pytorch.org`, and pip fails on the deploy host
only.

## 4. `fall_detection_web` has the opposite posture

Torch, YOLO, Redis and threading are all approved there. Do not carry
`simple_ai_vision`'s minimalism into it, or its stack into `simple_ai_vision`.

Both apps now pin Python 3.11 (`.python-version`, `requires-python`), matching the
add-on's `python:3.11-alpine` base, and `uv` installs that interpreter itself. The
underlying code difference still exists and still matters if you ever unpin:
`fall_detection_web` carries `from __future__ import annotations` in every module, so
its PEP 604 unions stay strings and it would run on 3.9; `simple_ai_vision/app.py` does
not, and evaluates `str | None` at import time, so it needs 3.10+.

## 5. Snapshots come from go2rtc, with Frigate as the fallback

`fetch_snapshot_with_fallback()` tries go2rtc (`/api/frame.jpeg?src={camera}`) and, on
failure, Frigate's `latest.jpg`. That is the whole chain.

**There is no Home Assistant camera-entity path.** `/analyze` accepts one key,
`{"camera": "<name>"}`. Nothing in `app.py` calls the HA Core API, and `ui.py` has no
entity field. Documentation that promises an `entity_id` payload is describing
something this fork does not implement — the READMEs were corrected on 2026-09-12.

Never implement RTSP decoding by hand in `simple_ai_vision`.

## 6. The add-on's Supervisor access is narrow and specific

`supervisor_frigate_hosts()` calls `http://supervisor/addons` to auto-discover a
Frigate add-on. That is the **Supervisor** API and needs `hassio_api: true` in
`config.yaml` — not `homeassistant_api`, which grants the HA *Core* API that this
add-on never calls.

The failure is swallowed (`logger.warning`, return `[]`), so a missing grant looks
exactly like "no Frigate installed". If Frigate discovery mysteriously finds nothing,
check the manifest before the network.

## 7. Add-ons must stay `amd64` + `aarch64` clean

No distro-specific assumptions, no x86-only wheels. The image is built from
`python:3.11-alpine` on the user's own hardware.

## 8. AI providers must be OpenAI-compatible

Image input as a base64 data URL. Applies to both apps.

## 9. UTF-8 everywhere, and all prose docs are English

A handful of strings stay Vietnamese on purpose because they are **data, not prose** —
do not "fix" them:

- the `cháy` entry in the Simple AI Vision keyword list (it matches Vietnamese AI
  output, and English `fire` is already a separate entry)
- camera and go2rtc stream names such as `bep` and `h9ccam2_sub`
- prompt-profile titles, and `DEFAULT_VERIFY_PROMPT` in `fall_detection_web/config.py`,
  which constrains the model to reply `SAFE` or `EMERGENCY`
- the automation aliases in the README examples

Translating an identifier changes behaviour; translating a caption does not.

## 10. Write shell commands as single-line `&&` chains, not multi-line blocks

The global `rtk` auto-rewrite hook adds the `rtk` prefix for you, but it matches on the
command's leading token — so a newline-separated block starting with `cd …` matches
nothing, and the hook returns **silently**: no rewrite, no warning.

Measured 2026-09-12: 48 of 51 commands in one session ran unprefixed despite the rule.
`cd x && git status && grep foo` has every command rewritten; `cd x` ⏎ `git status` has
none. The one unavoidable exception is a heredoc (`git commit -F - <<'EOF'`), which
saves nothing anyway.

Do not "fix" this by editing the RTK section of `CLAUDE.md`. Upstream, that block is a
*generated* region fenced by `<!-- rtk-instructions vN -->` markers, and an edit inside
it is reverted by the next rtk update. Our copy was written by hand and carries no
markers — so if rtk's updater ever manages that file it will not recognise the section
and may append a second one. Keep caveats here, where nothing regenerates over them.
