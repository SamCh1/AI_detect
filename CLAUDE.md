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
decisions to upstream — do not describe them as this fork's choices. Keeping
`repository.yaml` on upstream's name, url and maintainer is a **deliberate attribution
choice, reaffirmed 2026-09-12** — do not "fix" it to the fork. `simple_ai_vision/config.yaml`'s
`url` does point at this fork, because the add-on's own docs have diverged from
upstream's and users need the version matching what they installed.

## RTK (Token-Optimized Commands)

Globally installed. Prefix **every** command with `rtk` — including in `&&` chains.
Examples: `rtk git diff`, `rtk cargo test`, `rtk grep pattern`, `rtk gh pr view 42`.
Saves 60–90% tokens. Full reference: `~/.claude/CLAUDE.md`.

## Code intelligence — the routing rule

> **Code symbol, caller, or blast radius → CodeGraph.
> What routes / env vars / libraries exist → `.codesight/`.
> grep and read last.**

CodeGraph answers "where is this symbol, what calls it, what breaks" from
`.codegraph/` (1.6 MB SQLite, **gitignored**, built with `rtk codegraph init .`).
`.codesight/` is the route/library/env-var inventory (32 KB markdown,
**committed**, no local setup). **Commit the inventory, never the graph.**

Setup, exclusions, the subagent trap, the validation ladder and how to regenerate
the inventory: **[docs/claude/code-intelligence.md](docs/claude/code-intelligence.md)**.

## Conventions that bite

One line each; the reasoning, and what breaks when you get it wrong, is in
**[docs/claude/gotchas.md](docs/claude/gotchas.md)**. Read it before changing anything
structural. Add new entries there, and a one-liner here.

1. **The two apps are independent.** Add-on changes MUST bump
   `simple_ai_vision/config.yaml` (`make bump`); `fall_detection_web` changes must NOT.
2. **`cd` into the app dir before `uvicorn app:app`** — both apps define `app.py`.
3. **`simple_ai_vision` has a hard 3-dependency ceiling** and a ~25-entry DO-NOT-ADD
   list. Adding one is a design change. The two venvs are what enforce it.
4. **`fall_detection_web` has the opposite posture** — torch, YOLO, Redis, threading.
   Both pin Python 3.11; `uv` installs it. One `.venv` per app, inside the app.
5. **Snapshots are go2rtc → Frigate fallback.** There is no HA camera-entity path;
   `/analyze` takes `{"camera": "..."}` only. Never hand-roll RTSP.
6. **The add-on needs `hassio_api` for Frigate discovery**, not `homeassistant_api`.
   The failure is silent.
7. **Add-ons stay `amd64` + `aarch64` clean.** No x86-only wheels.
8. **AI providers must be OpenAI-compatible**, image input as a base64 data URL.
9. **UTF-8, prose in English** — but a few Vietnamese strings are *data*. Do not
   translate identifiers, keywords, stream names, or model prompts.
10. **Shell commands as single-line `&&` chains.** The `rtk` hook matches the leading
    token and skips multi-line blocks silently.

## Running and verifying

The `Makefile` wraps all of it, and every recipe `cd`s into the app first, which
makes the `uvicorn app:app` trap in rule 2 unreachable. `make help` lists everything.

```bash
rtk make setup    # both venvs + .env, then a readiness report
rtk make doctor   # what is installed, what is missing, what to run next
rtk make dev      # both apps, labelled streams (vision :8000, fall :8090)
rtk make logs     # follow app.log and any running container
rtk make check    # byte-compile both apps
```

`uv` is the only prerequisite and installs Python 3.11 itself — do not install Python
by hand. Both apps pin 3.11 via `.python-version`, so a local venv and the add-on's
`python:3.11-alpine` container run the same interpreter. Each app owns its `.venv`.
`requirements.txt` is a generated export of `uv.lock` in both apps: change
`pyproject.toml`, then `rtk make lock`, never hand-edit the export.

`fall_detection_web` expects a venv and an optional `.env` — see
`fall_detection_web/.env.example` and its README. Its `data/`, `.env` and `*.pt` model
weights are gitignored.

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

`.claude/settings.json` is the committed team layer — anything a reviewer relies on
belongs there. It currently holds the `codegraph prompt-hook` and the
`mcp__codegraph__*` permission grant. `.claude/settings.local.json` is personal and
gitignored, and GSD's 18 hooks live there. Never move a hook the other way: a hook
that runs only on one machine is indistinguishable from a hook that does not exist.

The same split governs MCP: `.mcp.json` is committed, but which servers a given
developer enables is personal. Committed config, personal activation.

## Known drift

- `fall_detection_web/.env.example` carries Vietnamese comments, which is prose, not
  data — it sits outside the exception list in rule 8 above. Harmless at runtime; fix
  it the next time that file is touched for another reason.

## Deliberately absent

Each of these was considered and rejected for this repo's size, not overlooked.
An unexplained absence gets "helpfully" added back; a recorded one does not.

| Not here | Why | Add it when |
|---|---|---|
| a docs knowledge graph | the whole docs corpus is 6 files | docs pass ~30 markdown files |
| automated PR review | 4 commits, no PR traffic yet | the first real PR arrives |
| `lefthook` / `ruff` pre-commit | there are no tests to back a gate | a test suite exists |
| a pinned env (devbox/nix) | one contributor, two `pip install` lines | a second contributor needs reproducibility |
| CI regeneration of `.codesight/` | needs a GitHub App token in a branch ruleset | the repo gains branch protection |
| a `SessionStart` banner hook | it would cost its own output every session forever, and this file already carries the routing rule | never, probably |

## Pointers

Each app directory's `CLAUDE.md` is a **symlink to its `AGENTS.md`** — one file, two
names, because Claude Code reads only the former and other agents only the latter. It
is what makes per-app rules load automatically in that directory. Edit the `AGENTS.md`;
never delete the link as a duplicate.


| File | Read it when |
|---|---|
| `AGENTS.md` (root) | you are not Claude Code — thin cross-tool entry point, points back here |
| `simple_ai_vision/AGENTS.md` | touching the add-on — carries the full DO-NOT-ADD list |
| `fall_detection_web/AGENTS.md` | touching the web app — stack, caching strategy, threading rules |
| `simple_ai_vision/README.md` | add-on install, HA automation wiring, `rest_command` examples |
| `fall_detection_web/README.md` | VPS setup, go2rtc, systemd service, `.env` keys |
| `README.md` (root) | repository-level overview and HA install — English |
| `Makefile` | the commands; `make help` lists them, `make doctor` checks the env |

When something surprises you, add a numbered entry to **Conventions that bite** above.
If that section outgrows this file, split it into `docs/claude/gotchas.md` and link it
from here — do not let this hub grow past ~200 lines.
