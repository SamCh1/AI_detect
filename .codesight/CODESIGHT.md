# AI_detect — AI Context Map

> **Stack:** fastapi | none | unknown | mixed
> **Monorepo:** fall_detection_web, simple_ai_vision

> 39 routes | 0 models | 0 components | 9 lib files | 1 env vars | 1 middleware
> **Token savings:** this file is ~2,200 tokens. Without it, AI exploration would cost ~26,400 tokens. **Saves ~24,300 tokens per conversation.**
> **Last scanned:** 2026-09-12 07:18 — re-run after significant changes

---

# Routes

- `GET` `/favicon.ico` params()
- `GET` `/login` params()
- `POST` `/auth/login` params() [auth]
- `POST` `/auth/logout` params() [auth]
- `GET` `/` params() [auth]
- `GET` `/cameras` params() [auth]
- `GET` `/camera/{camera_name:path}` params(path) [auth]
- `GET` `/{page_name}` params(page_name) [auth]
- `GET` `/api/logs` params() [auth]
- `POST` `/api/logs/clear` params() [auth]
- `GET` `/api/event-image/{filename}` params(filename) [auth, cache]
- `GET` `/api/teldrive/file/{file_id}/{file_name:path}` params(path, file_id) [auth, cache]
- `POST` `/api/user/update` params() [auth]
- `GET` `/api/config` params() [auth]
- `POST` `/api/config` params() [auth]
- `GET` `/api/cameras` params() [auth]
- `GET` `/api/camera/detail/{camera_name:path}` params(path) [auth]
- `POST` `/api/cameras` params() [auth]
- `POST` `/api/teldrive/check` params() [auth]
- `GET` `/api/status` params() [auth, cache]
- `POST` `/api/start` params() [auth]
- `POST` `/api/stop` params() [auth]
- `GET` `/api/events` params() [auth, cache]
- `GET` `/api/events/trends` params() [auth, cache]
- `GET` `/api/recordings` params() [auth, cache]
- `DELETE` `/api/events` params() [auth, db]
- `DELETE` `/api/recordings` params() [auth, db]
- `POST` `/api/capture` params() [auth]
- `GET` `/api/camera/snapshot` params() [auth]
- `GET` `/api/cameras/snapshot` params() [auth]
- `GET` `/api/camera/video` params() [auth, upload]
- `POST` `/api/test-ai` params() [auth]
- `POST` `/api/test-ai-camera` params() [auth]
- `POST` `/api/test-telegram` params() [auth]
- `POST` `/api/test-ai-upload` params() [auth, upload]
- `GET` `/health` params()
- `GET` `/api/go2rtc/streams` params()
- `GET` `/api/camera/frame` params() [cache]
- `POST` `/analyze` params()

---

# Libraries

- `fall_detection_web/ai.py`
  - function image_to_data_url: (path) -> str
  - function chat_url: (config, Any]) -> str
  - function parse_ai_content: (data, Any]) -> str
  - function parse_ai_sse: (text) -> str
  - function parse_concatenated_json: (text) -> str
  - function response_ai_content: (response) -> str
  - _...6 more_
- `fall_detection_web/app.py`
  - function login_page: (request)
  - function logout: ()
  - function find_camera_by_name: (c, Any], camera_name) -> tuple[int, dict[str, Any]]
  - function camera_snapshot_response: (index, refresh) -> Response
  - function lifespan: (app)
  - function favicon: ()
- `fall_detection_web/auth.py`
  - function configure_secret: (secret) -> None
  - function hash_password: (plain) -> str
  - function verify_password: (plain, hashed) -> bool
  - function create_token: (username, expire_hours) -> str
  - function decode_token: (token) -> str | None
- `fall_detection_web/config.py`
  - function normalize_go2rtc_source: (value) -> str
  - function is_url: (value) -> bool
  - function positive_int: (value, name) -> int
  - function clamp_float: (value, min_val, max_val, name) -> float
  - function migrate_config_json: () -> None
  - function normalize_cameras: (config, Any]) -> list[dict[str, Any]]
  - _...6 more_
- `fall_detection_web/db.py`
  - function ensure_data_dir: () -> None
  - function get_conn: () -> Generator[sqlite3.Connection, None, None]
  - function init_db: () -> None
  - function now_iso: () -> str
  - function local_iso: () -> str
  - function cleanup_event_images: () -> None
  - _...24 more_
- `fall_detection_web/monitor.py`
  - function get_backoff_seconds: (failures) -> int
  - function set_state: (**updates) -> None
  - function read_state: () -> dict[str, Any]
  - function camera_snapshot_path: (index) -> Path
  - function capture_rtsp_snapshot: (rtsp_url, output_path) -> Path
  - function log_event: (config, Any], status_name, image_path, camera_config, Any] | None, **fields) -> None
  - _...44 more_
- `fall_detection_web/redis_cache.py`
  - function get_client: (config, Any]) -> redis.Redis | None
  - function get_cache: (key, config, Any]) -> str | None
  - function set_cache: (key, value, expire_seconds, config, Any]) -> bool
  - function delete_cache: (key, config, Any]) -> bool
  - function clear_cache_pattern: (pattern, config, Any]) -> int
- `fall_detection_web/teldrive.py`
  - function enabled: (config, Any]) -> bool
  - function check_token: (config, Any], token, base_url) -> dict[str, Any]
  - function remote_folder: (config, Any], camera_name, kind) -> str
  - function ensure_folder: (config, Any], folder) -> None
  - function upload_file: (config, Any], local_path, folder, file_name) -> dict[str, Any]
  - function upload_event_image: (config, Any], local_path, camera_name, file_name) -> dict[str, Any]
  - _...4 more_
- `simple_ai_vision/app.py`
  - function error_response: (message, status_code, **extra) -> JSONResponse
  - function provider_error_response: (exc) -> JSONResponse
  - function upstream_error_response: (exc) -> JSONResponse
  - function default_options: () -> dict[str, Any]
  - function read_options: () -> dict[str, Any]
  - function load_options: () -> dict[str, Any]
  - _...54 more_

---

# Config

## Environment Variables

- `SUPERVISOR_TOKEN` (has default) — simple_ai_vision/app.py

## Config Files

- `fall_detection_web/.env.example`

---

# Middleware

## auth
- auth — `fall_detection_web/auth.py`

---

# Dependency Graph

## Most Imported Files (change these carefully)

- `fall_detection_web/config.py` — imported by **4** files
- `fall_detection_web/db.py` — imported by **3** files
- `fall_detection_web/ai.py` — imported by **2** files
- `fall_detection_web/teldrive.py` — imported by **2** files
- `fall_detection_web/redis_cache.py` — imported by **2** files
- `fall_detection_web/auth.py` — imported by **1** files
- `fall_detection_web/monitor.py` — imported by **1** files
- `simple_ai_vision/ui.py` — imported by **1** files

## Import Map (who imports what)

- `fall_detection_web/config.py` ← `fall_detection_web/ai.py`, `fall_detection_web/app.py`, `fall_detection_web/db.py`, `fall_detection_web/monitor.py`
- `fall_detection_web/db.py` ← `fall_detection_web/app.py`, `fall_detection_web/config.py`, `fall_detection_web/monitor.py`
- `fall_detection_web/ai.py` ← `fall_detection_web/app.py`, `fall_detection_web/monitor.py`
- `fall_detection_web/teldrive.py` ← `fall_detection_web/app.py`, `fall_detection_web/monitor.py`
- `fall_detection_web/redis_cache.py` ← `fall_detection_web/app.py`, `fall_detection_web/db.py`
- `fall_detection_web/auth.py` ← `fall_detection_web/app.py`
- `fall_detection_web/monitor.py` ← `fall_detection_web/app.py`
- `simple_ai_vision/ui.py` ← `simple_ai_vision/app.py`

---

# Claude Skills

Project-local slash commands available to Claude Code agents:

- `/gsd-discuss-phase` — Gather phase context through adaptive questioning before planning.
- `/gsd-execute-phase` — SDD phase execution — execute all plans in a phase with dependency-aware wave parallelization
- `/gsd-help` — Show available GSD commands and usage guide
- `/gsd-new-project` — Initialize a new project with deep context gathering and PROJECT.md
- `/gsd-phase` — Multi-phase management — add, insert, remove, or edit phases in ROADMAP.md (roadmap phase CRUD)
- `/gsd-plan-phase` — Create detailed phase plan (PLAN.md) with verification loop
- `/gsd-surface` — Toggle which skills are surfaced — apply a profile, list, or disable a cluster without reinstall
- `/gsd-update` — Update GSD to latest version with changelog display

_Source: .claude/commands_

---

_Generated by [codesight](https://github.com/Houseofmvps/codesight) — see your codebase clearly_