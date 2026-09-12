# AI_detect -- two independent FastAPI apps that share nothing but a git remote.
# See CLAUDE.md for the conventions this file exists to enforce mechanically.
#
# New here?  install uv, then `make setup`  (one command, does everything)
# Broken?    make doctor                     (one command, tells you what)
#
# uv is the ONLY prerequisite. It installs python 3.11 itself, so do not install
# python by hand and do not rely on whatever python3 your OS happens to ship --
# on a stock mac that is 3.9, which cannot run either app any more.
#
# No make on your machine (Windows)? `uv sync` inside each app directory is
# precisely what `make setup` runs, and produces the identical environment.
#
# There is no lint or test target, and that is deliberate: CLAUDE.md's
# "Deliberately absent" table rejects ruff/lefthook until a test suite exists.
# Every target below wraps something that already works today.

.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules
SHELL := /bin/bash

# ---- knobs ------------------------------------------------------------------
# Trailing comments are NOT safe on these: make keeps the whitespace before the
# `#`, so `VENV ?= .venv   # note` yields ".venv   " and every path built from it
# breaks. Keep the comment on its own line.

# Both apps run 3.11 and uv owns the interpreter, so the only prerequisite for a
# new contributor is uv itself -- `uv sync` downloads CPython 3.11 when the
# machine does not have it. No system python, no pyenv, no version drift.
#
# 3.11 is not arbitrary. It is the HIGHEST version the pinned torch allows
# (torchvision 0.20.1 ships cp39-cp312 wheels, no cp313 -- 3.13 is unresolvable
# until torch is bumped) and the version simple_ai_vision already runs in
# production via its python:3.11-alpine Dockerfile. Both apps used to differ
# here: fall on 3.9, vision needing 3.10+. They no longer do.
#
# Each app repeats the pin in its own .python-version, so a bare `uv sync` run
# inside an app directory agrees with everything below.
PY_VERSION ?= 3.11

HOST        ?= 0.0.0.0
VISION_PORT ?= 8000
FALL_PORT   ?= 8090

VISION_DIR := simple_ai_vision
FALL_DIR   := fall_detection_web

# One venv per app, living INSIDE the app directory -- which is where `uv sync`
# puts it by default. That is the point: `cd fall_detection_web && uv sync`
# and `make setup` now build the identical environment, so the Makefile is a
# convenience wrapper rather than a second, divergent way to set up the repo.
# (Both are already excluded from git and from the code indexes via `*/.venv/`.)
#
# Still two venvs, never one. simple_ai_vision has a hard 3-dependency ceiling
# and a ~25-entry DO-NOT-ADD list (CLAUDE.md #3). Run it in an env holding torch
# and an accidental `import torch` just works; run it in its own env and it
# fails on the spot. uv.lock now enforces that instead of merely documenting it.
VENV        ?= $(FALL_DIR)/.venv
VISION_VENV ?= $(VISION_DIR)/.venv

IMAGE     ?= simple-ai-vision:local
CODESIGHT ?= codesight@1.19.0

# PLATFORM: e.g. linux/amd64 -- see `docker-vision`. Empty = host arch.
PLATFORM ?=

# Colima sizing. The only container workload in this repo is the simple_ai_vision
# add-on image: alpine + three pip packages. It does not need a big VM.
# --disk is a sparse CEILING, not an upfront allocation -- the qcow grows to what
# you actually use, so a roomy number costs nothing while a stingy one is painful
# to raise later (it needs a delete + recreate).
# Measured on this repo: a native arm64 build takes ~27s, produces a 185 MB image
# and installs every dep from a musl wheel -- nothing compiles from source. The
# container idles at ~39 MB. 2 GiB would do; 4 is headroom for linux/amd64 under
# QEMU, which is the same build with an emulator in the way.
#
# Sizing is applied by `colima start`, but ONLY cpu and memory can change on an
# existing VM. A smaller --disk is recorded in colima's config and reported by
# `colima list` while the underlying data disk keeps its original size -- the
# number moves and the bytes do not. Shrinking for real needs colima-reset.
COLIMA_PROFILE ?= default
COLIMA_CPU     ?= 2
COLIMA_MEMORY  ?= 4
COLIMA_DISK    ?= 40

# colima names its docker context `colima` for the default profile and
# `colima-<profile>` for any other. Getting this wrong is how you end up with the
# dangling-context failure that looks like a dead daemon but is not one.
COLIMA_CTX := $(if $(filter default,$(COLIMA_PROFILE)),colima,colima-$(COLIMA_PROFILE))

# colima is ONE way to get a docker daemon, not a requirement of this repo.
# Docker Desktop, OrbStack, Rancher Desktop and a remote DOCKER_HOST all work --
# every docker target here only needs `docker info` to succeed. So the advice we
# print when the daemon is down has to depend on what the user actually has.
HAS_COLIMA  := $(shell command -v colima 2>/dev/null)
DOCKER_HINT := $(if $(HAS_COLIMA),make colima-up,start your docker engine (Docker Desktop, OrbStack, Rancher Desktop, ...))

.PHONY: help setup reset doctor dev dev-vision dev-fall logs version bump \
        colima-up colima-down colima-reset docker-vision require-docker \
        graph inventory check clean lock require-uv \
        _venv-fall _venv-vision _env _export

##@ Setup

setup: ## Onboard this repo: both venvs, .env, then a readiness report
	@echo "==> [1/3] fall_detection_web venv ($(VENV))"
	@$(MAKE) --no-print-directory _venv-fall || echo "    FAILED -- see above; make doctor will show what is missing"
	@echo ""
	@echo "==> [2/3] simple_ai_vision venv ($(VISION_VENV))"
	@$(MAKE) --no-print-directory _venv-vision || echo "    skipped -- see above; the add-on still builds via make docker-vision"
	@echo ""
	@echo "==> [3/3] $(FALL_DIR)/.env"
	@$(MAKE) --no-print-directory _env
	@echo ""
	@$(MAKE) --no-print-directory doctor

reset: ## Delete both venvs and all bytecode, then re-run setup
	rm -rf $(VENV) $(VISION_VENV)
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory setup

lock: require-uv ## Re-resolve both uv.lock files, then regenerate requirements.txt
	uv lock --directory $(FALL_DIR)
	uv lock --directory $(VISION_DIR)
	@$(MAKE) --no-print-directory _export
	@echo "review the uv.lock and requirements.txt diffs before committing"

# requirements.txt is a GENERATED artifact in both apps -- never hand-edit it.
# It exists because both deploy paths still install with pip: the add-on's
# Dockerfile (`pip install -r requirements.txt`) and fall_detection_web's VPS
# venv under systemd. Exporting it from uv.lock keeps ONE source of truth
# instead of two lists that drift apart.
#
# --emit-index-url is load-bearing, not decoration. Without it the export names
# torch==2.5.1+cpu but omits download.pytorch.org, so pip goes looking for that
# version on PyPI where it does not exist. uv itself never needs the line (it
# reads the index from pyproject.toml), which means the failure would show up
# only on the deploy hosts -- the worst place to find it.
_export:
	@for d in $(FALL_DIR) $(VISION_DIR); do \
	  uv export --quiet --directory $$d --no-hashes --no-emit-project \
	    --emit-index-url --format requirements.txt -o requirements.txt \
	  && echo "    exported $$d/requirements.txt"; \
	done

doctor: ## Health check: uv, venvs, lockfiles, .env, docker/colima, code indexes
	@echo "-- toolchain"
	@printf "  %-26s %s\n" "uv" "$$(uv --version 2>&1 || echo 'MISSING -- see make setup')"
	@printf "  %-26s %s\n" "pinned python" "$(PY_VERSION), both apps (.python-version)"
	@echo "-- venvs"
	@for v in $(VENV) $(VISION_VENV); do \
	  if [ -x "$$v/bin/uvicorn" ]; then \
	    printf "  %-26s ready   %s\n" "$$v" "$$($$v/bin/python -V 2>&1)"; \
	  else \
	    printf "  %-26s missing -> make setup\n" "$$v"; \
	  fi; \
	done
	@echo "-- lockfiles"
	@for d in $(FALL_DIR) $(VISION_DIR); do \
	  if uv lock --directory $$d --check >/dev/null 2>&1; then \
	    printf "  %-26s agrees with pyproject.toml\n" "$$d/uv.lock"; \
	  else \
	    printf "  %-26s STALE -> make lock\n" "$$d/uv.lock"; \
	  fi; \
	done
	@[ -f "$(FALL_DIR)/.env" ]           && echo "  $(FALL_DIR)/.env  present" || echo "  $(FALL_DIR)/.env  absent (optional -- config falls back to SQLite)"
	@echo "-- docker"
	@echo "  (only needed for docker-vision -- setup, dev and logs never touch it)"
ifdef HAS_COLIMA
	@colima list 2>/dev/null | sed 's/^/  /'
	@echo "  Makefile wants $(COLIMA_CPU) cpu / $(COLIMA_MEMORY) GiB / $(COLIMA_DISK) GiB"
	@echo "    cpu + memory apply on the next colima-up. DISK DOES NOT SHRINK: colima will"
	@echo "    record the smaller number and report it here while the data disk stays its"
	@echo "    original size -- only make colima-reset YES=1 actually reclaims it."
else
	@echo "  colima not installed -- the COLIMA_* knobs and colima-* targets do not apply here"
endif
	@docker info >/dev/null 2>&1 \
	  && echo "  daemon reachable: $$(docker info --format '{{.ServerVersion}} on {{.Architecture}}') via context '$$(docker context show 2>/dev/null)'" \
	  || { echo "  daemon NOT reachable -> $(DOCKER_HINT)"; docker context ls 2>&1 | sed 's/^/    /'; }
	@echo "-- code intelligence"
	@command -v codegraph >/dev/null 2>&1 && echo "  codegraph $$(codegraph --version 2>&1)" || echo "  codegraph not installed (optional)"
	@git check-ignore -q .codegraph && echo "  .codegraph ignored" || echo "  WARN: .codegraph is NOT gitignored -- never commit the graph"
	@[ -f .codesight/routes.md ] && echo "  .codesight inventory present" || echo "  .codesight missing -> make inventory"

# Internal. Folded into `setup` on purpose -- there is no reason for a new
# contributor to have to know these exist, or the order they run in.
#
# `uv sync` IS the whole installation step. It reads the app's .python-version,
# downloads CPython $(PY_VERSION) if this machine does not have it, creates the
# venv and installs exactly what uv.lock pins -- identical on macOS, Linux and
# Windows, with no system python involved at any point.
#
# --locked means "the lockfile must already agree with pyproject.toml". Editing
# a dependency without running `make lock` therefore fails here, loudly, instead
# of silently producing an environment that no lockfile describes. That drift is
# the exact failure this layout exists to prevent, so setup refuses to paper
# over it.
#
# The old `sed -e 's/+cpu//'` macOS rewrite is gone. torch's platform split now
# lives in fall_detection_web/pyproject.toml as marker-gated index sources,
# which additionally covers linux-aarch64 -- a case the sed hack got wrong, as
# no +cpu wheels are published for ARM Linux either.
_venv-fall: require-uv
	uv sync --directory $(FALL_DIR) --locked

_venv-vision: require-uv
	uv sync --directory $(VISION_DIR) --locked

_env:
	@if [ -f $(FALL_DIR)/.env ]; then \
	  echo "    exists -- not overwriting"; \
	else \
	  cp $(FALL_DIR)/.env.example $(FALL_DIR)/.env; \
	  echo "    created -- every key is commented out; uncomment what you need"; \
	fi

##@ Run

# Both apps are started as `uvicorn app:app` -- a bare module reference resolved
# against $PWD. Run it from the repo root and you get an ImportError or, worse,
# the *other* app. Every recipe below cds first, which makes that unreachable.

dev: ## Run both apps together (vision :8000, fall :8090), streams labelled
	@if [ -t 1 ]; then \
	  F='\033[36m[fall]  \033[0m%s\n'; V='\033[35m[vision]\033[0m%s\n'; \
	else \
	  F='[fall]   %s\n'; V='[vision] %s\n'; \
	fi; \
	trap 'trap - INT TERM; kill 0 2>/dev/null; exit 0' INT TERM; \
	$(MAKE) --no-print-directory dev-fall   2>&1 | awk -v f="$$F" '{ printf f, $$0; fflush() }' & \
	$(MAKE) --no-print-directory dev-vision 2>&1 | awk -v f="$$V" '{ printf f, $$0; fflush() }' & \
	wait

# uvicorn writes its banner to stderr, hence 2>&1 on each side. awk rather than
# `sed -u`: unbuffered sed is a GNU flag that BSD sed on macOS does not have,
# while awk's fflush() is portable. Colour is dropped when stdout is not a tty,
# so `make dev > run.log` stays free of escape codes.

dev-vision: ## Run simple_ai_vision alone on :8000
	@[ -x "$(VISION_VENV)/bin/uvicorn" ] \
	  || { echo "no venv at $(VISION_VENV) -- run: make setup" >&2; exit 1; }
	cd $(VISION_DIR) && $(CURDIR)/$(VISION_VENV)/bin/uvicorn app:app --host $(HOST) --port $(VISION_PORT)

dev-fall: ## Run fall_detection_web alone on :8090
	@[ -x "$(VENV)/bin/uvicorn" ] \
	  || { echo "no venv at $(VENV) -- run: make setup" >&2; exit 1; }
	cd $(FALL_DIR) && $(CURDIR)/$(VENV)/bin/uvicorn app:app --host $(HOST) --port $(FALL_PORT)

logs: ## Follow every log this repo produces: app.log + running containers
	@n=0; \
	trap 'trap - INT TERM; kill 0 2>/dev/null; exit 0' INT TERM; \
	if [ -f $(FALL_DIR)/data/app.log ]; then \
	  n=$$((n+1)); \
	  tail -n 50 -F $(FALL_DIR)/data/app.log 2>/dev/null \
	    | awk '{ printf "[fall.log] %s\n", $$0; fflush() }' & \
	fi; \
	for c in $$(docker ps --format '{{.Names}}' 2>/dev/null); do \
	  n=$$((n+1)); \
	  docker logs -f --tail 50 "$$c" 2>&1 \
	    | awk -v name="$$c" '{ printf "[%s] %s\n", name, $$0; fflush() }' & \
	done; \
	if [ "$$n" = "0" ]; then \
	  echo "nothing to follow: no $(FALL_DIR)/data/app.log, no running containers"; \
	  echo "  start something first -- make dev, or make docker-vision && docker run ..."; \
	  exit 0; \
	fi; \
	echo "following $$n stream(s) -- ctrl-c to stop"; \
	wait

# `make dev` shows the two apps live in one terminal; `make logs` is the other
# half -- it follows what is ALREADY running, including things this Makefile did
# not start (a container, or the app under systemd on the VPS). fall_detection_web
# writes data/app.log via a FileHandler; simple_ai_vision is stdout-only, so it
# appears here only when it is running as a container.
#
# Deliberately not a web UI. Dozzle and friends read the docker socket, so they
# would show the add-on container and nothing at all for fall_detection_web,
# which runs as a bare uvicorn process. A real dashboard needs both apps
# containerised first, and CLAUDE.md pins fall_detection_web to venv + systemd.

##@ Add-on release

version: ## Print the current simple_ai_vision add-on version
	@sed -n 's/^version:[[:space:]]*"\([^"]*\)".*/simple_ai_vision \1/p' $(VISION_DIR)/config.yaml

bump: ## Bump the add-on patch version (or: make bump V=1.5.0)
	@f=$(VISION_DIR)/config.yaml; \
	cur=$$(sed -n 's/^version:[[:space:]]*"\([^"]*\)".*/\1/p' $$f); \
	if [ -z "$$cur" ]; then echo "could not read version from $$f" >&2; exit 1; fi; \
	if [ -n "$(V)" ]; then new="$(V)"; \
	else new=$$(echo "$$cur" | awk -F. -v OFS=. '{ $$NF = $$NF + 1; print }'); fi; \
	sed 's/^version:.*/version: "'"$$new"'"/' $$f > $$f.tmp && mv -f $$f.tmp $$f; \
	echo "simple_ai_vision  $$cur -> $$new"

# An unbumped add-on change is the silent failure in this repo: the HA Add-on
# Store keys the update off this version, so the change simply never ships.
# A change to fall_detection_web must NOT touch it (CLAUDE.md #1).

##@ Docker

colima-up: ## Start the docker VM (creates it at 2cpu/4G/20G on first run)
	@if colima status -p $(COLIMA_PROFILE) >/dev/null 2>&1; then \
	  echo "colima '$(COLIMA_PROFILE)' already running"; \
	else \
	  colima start -p $(COLIMA_PROFILE) \
	    --cpu $(COLIMA_CPU) --memory $(COLIMA_MEMORY) --disk $(COLIMA_DISK); \
	fi
	@docker context use $(COLIMA_CTX) >/dev/null 2>&1 \
	  || echo "warn: could not select docker context '$(COLIMA_CTX)'"
	@docker info --format 'ready: docker {{.ServerVersion}} on {{.Architecture}}' 2>/dev/null \
	  || echo "warn: daemon still unreachable -- see make doctor"

colima-down: ## Stop the docker VM (keeps the disk image)
	colima stop -p $(COLIMA_PROFILE)

colima-reset: ## DESTROY the VM and recreate it at the sizes above (needs YES=1)
	@[ "$(YES)" = "1" ] || { \
	  echo "refusing: this deletes the colima VM '$(COLIMA_PROFILE)' and everything in it"; \
	  echo "  (images, build cache, volumes -- nothing in this repo lives there)"; \
	  echo "  re-run: make colima-reset YES=1"; \
	  exit 1; }
	colima delete -p $(COLIMA_PROFILE) -f
	@$(MAKE) --no-print-directory colima-up

require-uv:
	@command -v uv >/dev/null 2>&1 || { \
	  echo "uv is not installed -- and it is the ONLY prerequisite for this repo."; \
	  echo "  macOS/Linux:  curl -LsSf https://astral.sh/uv/install.sh | sh"; \
	  echo "  or:           brew install uv"; \
	  echo "  Windows:      powershell -c \"irm https://astral.sh/uv/install.ps1 | iex\""; \
	  echo "  uv then installs python $(PY_VERSION) itself -- do not install python by hand."; \
	  exit 1; }

require-docker:
	@docker info >/dev/null 2>&1 || { \
	  echo "docker daemon unreachable -- $(DOCKER_HINT)"; \
	  echo "  (a dangling docker context fails like a dead daemon but is not one;"; \
	  echo "   make doctor tells the two apart)"; \
	  exit 1; }

docker-vision: require-docker ## Build the add-on image locally
	docker build $(if $(PLATFORM),--platform $(PLATFORM),) -t $(IMAGE) $(VISION_DIR)

# The add-on must stay amd64 + aarch64 clean (CLAUDE.md #6), and a bare build
# only proves your host's arch. For the other half:
#   make docker-vision PLATFORM=linux/amd64
# On an arm64 host that needs binfmt/QEMU emulation -- slow, but it is the
# difference between "builds here" and "builds for users". Note the Dockerfile's
# BUILD_FROM defaults to python:3.11-alpine while the HA supervisor substitutes
# its own per-arch base, so a green local build proves your layers, not HA's.

##@ Code intelligence

graph: ## Build the CodeGraph index, or rebuild it if one exists
	@if [ -d .codegraph ]; then codegraph index .; else codegraph init .; fi

inventory: ## Regenerate .codesight/ (committed) -- version pinned on purpose
	npx --yes $(CODESIGHT) .
	@echo "now review and commit the .codesight/ diff"

##@ Housekeeping

check: require-uv ## Byte-compile both apps -- a syntax gate, not a linter
	@uv run --no-project --python $(PY_VERSION) -- python -m compileall -q $(VISION_DIR) $(FALL_DIR) \
	  && echo "both apps parse on $(PY_VERSION)"
	@$(MAKE) --no-print-directory clean >/dev/null

clean: ## Remove __pycache__ and *.pyc from both apps
	@find $(VISION_DIR) $(FALL_DIR) -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find $(VISION_DIR) $(FALL_DIR) -name '*.pyc' -delete 2>/dev/null || true
	@echo "cleaned"

help: ## Show this help
	@awk 'BEGIN { FS = ":.*##" } \
	     /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
	     /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' \
	     $(MAKEFILE_LIST)
	@echo ""
