# VPS migration: distro python + pip  ->  uv + locked Python 3.11

Migrates the `fall_detection_web` deployment from the old layout
(`python3 -m venv venv` + `pip install -r requirements.txt`, interpreter
supplied by the distro) to the current one (`uv sync --locked`, Python 3.11
supplied by uv, dependencies pinned by `uv.lock`).

**Strategy: side by side.** We clone into a *new* directory and build the new
venv there while the existing service keeps running untouched. The only moment
of downtime is the systemd unit swap in step 7. If anything fails before that,
nothing has changed. Rollback is one `systemctl` command.

Run every command as the same user that owns the current install.

---

## 0. Prerequisite, on your laptop — not the VPS

The VPS pulls the new layout from git, so it must be pushed first. These files
are what the migration depends on:

```
fall_detection_web/pyproject.toml    fall_detection_web/uv.lock
fall_detection_web/.python-version   fall_detection_web/requirements.txt
simple_ai_vision/pyproject.toml      simple_ai_vision/uv.lock
simple_ai_vision/.python-version     simple_ai_vision/requirements.txt
Makefile                             .gitignore
```

Confirm they are on the default branch of `github.com/SamCh1/AI_detect` before
continuing. Nothing below works until they are.

---

## 1. Discover the current state — change nothing

The old README was genericized (`git@github.com:MyRepo/my_hass_addon_public.git`),
so the real paths on this box have to be read, not assumed.

```bash
systemctl cat fall-detection.service
```

Read `WorkingDirectory` and `ExecStart` out of that output and set:

```bash
OLD_DIR=/opt/my_hass_addon_public          # <- replace with the real WorkingDirectory's parent
NEW_DIR=/opt/AI_detect
echo "OLD_DIR=$OLD_DIR  NEW_DIR=$NEW_DIR"
```

Record what is running now, so you can prove the migration changed the right things:

```bash
systemctl is-active fall-detection
"$OLD_DIR"/fall_detection_web/venv/bin/python -V     # the version actually in production
git -C "$OLD_DIR" remote -v
git -C "$OLD_DIR" rev-parse --short HEAD
df -h /opt | tail -1                                  # need ~3GB free: new venv + torch
```

Torch and its CUDA-free deps are roughly 1–2 GB. If `/opt` has less than ~3 GB
free, stop and clear space first — a half-installed venv is a bad place to be.

---

## 2. Back up the irreplaceable things

`.env` holds secrets and `data/` holds the SQLite database, `app.log` and any
stored evidence video. Neither is in git. Copy both off the box, not just to
another directory on it:

```bash
sudo tar czf ~/fall-detection-backup-$(date +%F).tar.gz \
  -C "$OLD_DIR/fall_detection_web" .env data
sudo cp /etc/systemd/system/fall-detection.service ~/fall-detection.service.bak
ls -lh ~/fall-detection-backup-*.tar.gz ~/fall-detection.service.bak
```

Then copy that tarball to your laptop with `scp`. A backup that only exists on
the machine you are changing is not a backup.

---

## 3. Install uv and make

uv is the only new prerequisite. It installs Python 3.11 itself — do not
`apt install python3.11`.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
sudo apt update && sudo apt install -y make git
uv --version
```

If the service runs as `root` (the README's unit does) make sure you install uv
as the user who will run `make setup`. systemd itself never needs uv: the unit
executes `.venv/bin/uvicorn` directly, by absolute path.

---

## 4. Clone the new layout alongside the old one

The existing install is not touched by anything in this step.

```bash
sudo git clone https://github.com/SamCh1/AI_detect.git "$NEW_DIR"
sudo chown -R "$USER:$USER" "$NEW_DIR"
git -C "$NEW_DIR" rev-parse --short HEAD
test -f "$NEW_DIR/fall_detection_web/uv.lock" \
  && echo "uv.lock present" \
  || echo "STOP: uv.lock missing -- step 0 was not completed"
```

Do not continue until that prints `uv.lock present`.

---

## 5. Carry over config and data

`.env` and `data/` are gitignored, so the fresh clone has neither. Copy, do not
move — the old install must stay bootable for rollback.

```bash
cp "$OLD_DIR/fall_detection_web/.env" "$NEW_DIR/fall_detection_web/.env"
cp -a "$OLD_DIR/fall_detection_web/data" "$NEW_DIR/fall_detection_web/data"
ls -la "$NEW_DIR/fall_detection_web/.env" && du -sh "$NEW_DIR/fall_detection_web/data"
```

`cp -a` preserves permissions and timestamps, which matters for the SQLite file.

> If the app is mid-write, the copied database can be a torn snapshot. For a
> clean cut, stop the service first (`sudo systemctl stop fall-detection`),
> re-run the two copies above, and accept downtime from here rather than at
> step 7.

---

## 6. Build the new environment

```bash
cd "$NEW_DIR"
make setup
```

`uv sync --locked` downloads CPython 3.11, creates
`fall_detection_web/.venv` and installs exactly what `uv.lock` pins — the
`+cpu` torch wheels from `download.pytorch.org` on x86_64, plain wheels on
aarch64. Then confirm:

```bash
make doctor
"$NEW_DIR"/fall_detection_web/.venv/bin/python -V          # expect Python 3.11.x
"$NEW_DIR"/fall_detection_web/.venv/bin/python -c "import torch, ultralytics, cv2; print(torch.__version__, ultralytics.__version__)"
```

`make doctor` must report both venvs `ready` and both lockfiles
`agrees with pyproject.toml`. If a lockfile says `STALE`, the push in step 0 was
incomplete — fix it there, not here.

Smoke-test on a spare port, so the live service is unaffected:

```bash
cd "$NEW_DIR/fall_detection_web"
"$NEW_DIR"/fall_detection_web/.venv/bin/uvicorn app:app --host 127.0.0.1 --port 8099 &
SMOKE_PID=$!
sleep 8
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:8099/
kill "$SMOKE_PID" 2>/dev/null; wait "$SMOKE_PID" 2>/dev/null
```

Read the result literally. Any **HTTP status at all** — `200`, `302` and `401`
are all normal here depending on whether auth is configured — means uvicorn
imported the app and is serving. `HTTP 000` means it never came up: read the
uvicorn output printed above it, usually an import or config error.

Port 8099 is deliberate; 8090 is still held by the live service. If the smoke
test fails, **stop here**. The old service is still serving and you have lost
nothing.

---

## 7. Swap the systemd unit — the only downtime

```bash
sudo systemctl stop fall-detection
sudo tee /etc/systemd/system/fall-detection.service >/dev/null <<EOF
[Unit]
Description=Fall Detection Web Service
After=network-online.target

[Service]
User=root
WorkingDirectory=$NEW_DIR/fall_detection_web
ExecStart=$NEW_DIR/fall_detection_web/.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8090 --no-access-log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl start fall-detection
```

Both paths change here: the directory, **and** `venv` -> `.venv`. Getting only
one of them right is the most likely way this fails.

Verify:

```bash
systemctl status fall-detection --no-pager
journalctl -u fall-detection -n 40 --no-pager
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/
```

---

## 8. Rollback, if step 7 goes wrong

The old install is untouched and still complete:

```bash
sudo cp ~/fall-detection.service.bak /etc/systemd/system/fall-detection.service
sudo systemctl daemon-reload && sudo systemctl restart fall-detection
systemctl status fall-detection --no-pager
```

You are back to the previous deployment. `$NEW_DIR` can stay for a second
attempt; it changes nothing on its own.

---

## 9. Cleanup — only after a day of healthy running

Do not rush this. The old directory is the rollback path.

```bash
du -sh "$OLD_DIR"
sudo rm -rf "$OLD_DIR"
```

Keep the step-2 tarball regardless.

---

## Afterwards

- Deploys are now `git -C /opt/AI_detect pull && make setup`. `--locked` means
  a dependency change that was not committed with its `uv.lock` fails loudly
  here instead of installing something no lockfile describes.
- Never `pip install` into `.venv` by hand. Change `pyproject.toml`, run
  `make lock` on your laptop, commit both, pull here.
- `requirements.txt` is a generated export, kept only so pip-based hosts keep
  working. It is not the source of truth.
