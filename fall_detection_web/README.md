# AI Camera Monitoring & Fall Detection System (Fall Detection Web)

An intelligent camera monitoring system that detects people locally with YOLO, verifies their behaviour (falls, sudden incidents) through AI Vision, and then sends an instant alert with photographic evidence over Telegram.

The project is built as a standalone, self-hosted web application, suitable for deployment on a VPS, an internal LAN server, a mini PC, or a dedicated monitoring machine.

```text
Camera / RTSP / go2rtc 
  -> Local person detection (YOLO)
  -> Image verification via AI Vision (OpenAI API/Gemini/OpenRouter)
  -> Incident timeline
  -> Instant Telegram alert (sendPhoto)
  -> Video recording & evidence storage (Teldrive / VPS)
```

---

## Core Features

- **SOC Dashboard**: Track system status, visualise CPU/RAM/disk load, review a 7-day incident trend chart, and see the most recent incidents.
- **Multi-camera management**: Add, edit, delete, enable/disable, take snapshots, and test the AI directly.
- **Live View**: Low-latency live streaming through go2rtc (automatic WebRTC/MSE negotiation), a custom live URL, or an MJPEG proxy fallback.
- **AI Vision verification**: Send snapshots to OpenAI-compatible APIs (OpenAI, Gemini, OpenRouter, 9Router, and others) to classify incidents precisely as `SAFE` or `EMERGENCY`.
- **Telegram alerts**: Send the incident snapshot along with a detailed description as soon as the AI confirms an emergency (`EMERGENCY`).
- **Incident timeline (Events)**: Store incident history with thumbnails, timestamps (Vietnam time, UTC+7), status, and the AI's description.
- **Recording playback (Recordings)**: Review incident clips recorded locally in the interface or stored on Teldrive (with a popup web player and a quick copy-download-link action).
- **Prompt manager**: Define separate AI prompt templates and assign them per camera area — for example, an indoor camera needs a different prompt from one covering the yard.
- **Security**: Safe login using bcrypt password hashing and a JWT cookie session.

---

## Quick Installation Guide

### 1. On Linux / Ubuntu VPS

Open a terminal and run the following commands to create the directory, fetch the source, and install Python and the required libraries:

```bash
# 1. Create the project directory under /opt
sudo mkdir -p /opt
cd /opt

# 2. Clone the source from GitHub using an SSH key
sudo git clone git@github.com:MyRepo/my_hass_addon_public.git
cd my_hass_addon_public/fall_detection_web

# Give the current user (for example root or ubuntu) ownership of the directory so it can run without sudo
sudo chown -R $USER:$USER /opt/my_hass_addon_public

# 3. Install Python 3, pip and venv (if not already present)
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

# 4. Create and activate a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# 5. Install the dependencies
pip install --upgrade pip
pip install -r requirements.txt

# 6. Run the web application as a test
uvicorn app:app --host 0.0.0.0 --port 8090
```

### 2. On Windows (PowerShell)

Open PowerShell in the project directory and run:

```powershell
# 1. Create a Python virtual environment
python -m venv venv

# 2. Activate the virtual environment
.\venv\Scripts\Activate.ps1

# 3. Install the dependencies
pip install -r requirements.txt

# 4. Run the web application
uvicorn app:app --host 0.0.0.0 --port 8090
```

Once it is running, open the interface in a browser:
* Address: `http://<IP-SERVER>:8090` or `http://localhost:8090`
* Default username: **`admin`**
* Default password: **`admin`**
* *Note: you should change the account password under Settings immediately after your first successful login.*

---

## System Configuration Guide (Settings)

After logging in, open the **Settings** menu (or the gear icon) in the left-hand navigation bar to configure the system:

### 1. AI Vision configuration (AI Provider)
* **AI Base URL**: The provider's API address (for example `https://api.openai.com/v1`, OpenRouter's endpoint `https://openrouter.ai/api/v1`, or a Gemini OpenAI gateway).
* **AI API Key**: The secret API key for your AI account.
* **Vision Model**: The name of a model that can interpret images (for example `gpt-4o` or `google/gemini-2.5-flash`).

### 2. Telegram alert configuration
* **Telegram Bot Token**: The token for the Telegram bot you created via `@BotFather`.
* **Telegram Chat ID**: The ID of the recipient, or of the Telegram group/channel that receives the alerts.

### 3. go2rtc configuration (stream and snapshot management)
* **go2rtc URL**: The go2rtc API link (for example `http://127.0.0.1:1984`, or your public URL such as `https://go2rtc.example.me`).

### 4. History storage configuration (Teldrive — optional)
If you want to store incident video and images on Telegram with unlimited capacity through the Teldrive virtual file system:
* **Teldrive Enabled**: Tick to enable.
* **Teldrive Base URL**: The path to your Teldrive server (for example `https://teldrive.yourdomain.com`).
* **Teldrive Token**: Enter your **JWT/Bearer token** or your **permanent static API key**. Permanent static API keys are fully supported by the customised Teldrive build at [minhhungtsbd/teldrive](https://github.com/minhhungtsbd/teldrive), which keeps the connection stable without worrying about session expiry.
* **Teldrive Root Path**: The root directory used for storage (for example `/Fall Detection`).

### 5. Redis cache configuration (optional — for all-round optimisation and smooth loading)
To get sub-millisecond page loads and reduce query load on the SQLite database, you can enable the Redis cache:
* **Redis Enabled**: Tick to enable the cache (only turn this on once a Redis server is installed).
* **Redis Host**: The Redis connection address (default: `127.0.0.1`).
* **Redis Port**: The Redis port (default: `6379`).
* **Redis DB**: The Redis database index to use (default: `0`).
* **Redis Password**: The Redis authentication password, if any.

---

## go2rtc Installation & Configuration Guide

For the web application to fetch camera snapshots and stream live video smoothly, you need to install the **go2rtc** service.

### 1. Quick go2rtc installation on Linux (VPS)

You can run go2rtc either directly from the binary or via Docker:

#### Option 1: Run the binary directly (recommended, as it is the lightest)
```bash
# Download the latest release from GitHub (pick the build matching your CPU, amd64 or arm64)
wget https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64 -O go2rtc
chmod +x go2rtc

# Start go2rtc once to generate a sample configuration file
./go2rtc
```

To run go2rtc in the background as a system service on a VPS, create a systemd service file:
```bash
sudo nano /etc/systemd/system/go2rtc.service
```
Paste the following service configuration (adjust the `/opt/go2rtc` directory to match wherever your binary lives):
```ini
[Unit]
Description=go2rtc service
After=network.target

[Service]
ExecStart=/opt/go2rtc/go2rtc
Restart=always
RestartSec=5
WorkingDirectory=/opt/go2rtc

[Install]
WantedBy=multi-user.target
```
Then enable it to start with the system:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now go2rtc
```

---

### 2. Configuring the go2rtc connection in the web app

Once go2rtc is running, update the **go2rtc URL** setting in the web application's **Settings** menu according to your network layout:

#### Case A: Using a local IP (go2rtc and the web app are on the same VPS/server)
* Use go2rtc's default port, `1984`.
* Enter this in the web app's Settings:
  ```text
  http://127.0.0.1:1984
  ```

#### Case B: Using a LAN IP or a public IP (go2rtc runs on a different machine or network)
* For a connection over the local LAN:
  ```text
  http://192.168.1.100:1984
  ```
* For a connection over the internet using your VPS/server's public IP (remember to open port `1984` on the VPS firewall and on your home router):
  ```text
  http://<YOUR-VPS-PUBLIC-IP>:1984
  ```

#### Case C: Using a public domain via Cloudflare Tunnel (recommended for free HTTPS and strong security)
If you expose go2rtc to the internet safely through a Cloudflare Tunnel (for example `go2rtc.yourdomain.com`):
* Create a Cloudflare Tunnel pointing the domain `go2rtc.yourdomain.com` at local port `1984` on the machine running go2rtc.
* Enter the HTTPS URL in the web app's Settings:
  ```text
  https://go2rtc.yourdomain.com
  ```
* **A note on WebRTC behind a Cloudflare Tunnel:**
  * Cloudflare Tunnel carries HTTP and WebSockets perfectly, so snapshot capture (`frame.jpeg`) and MSE/HLS live streaming work reliably straight away.
  * However, the WebRTC protocol (which gives the lowest-latency video and the best HEVC support) requires UDP port `8555`, and the standard Cloudflare proxy blocks that port.
  * **Workaround:** if the WebRTC live stream goes black because Cloudflare is blocking the port, the go2rtc player in the web UI detects this automatically and falls back to **MSE/HLS** without interrupting you. To have WebRTC work over the internet as well, you can open port `8555` (TCP/UDP) directly on the public IP of the machine running go2rtc.

---

## Camera Setup Guide (Cameras)

Go to **Cameras** > **Add Camera**, or edit an existing camera with the **Edit** button on the camera detail page. Fill in the fields as described below to get the best results:

| Configuration field | How to set it, and sensible values |
| :--- | :--- |
| **Camera name / go2rtc source** | Enter exactly the stream name declared in your `go2rtc.yaml` configuration (for example `h9ccam2_sub`). No spaces or special characters. |
| **Prompt** | Select the AI prompt template that suits this camera (created beforehand in the Prompts tab). |
| **go2rtc frame URL or source** | Enter the short stream name (for example `h9ccam2_sub`) if you have already set a shared go2rtc URL in Settings. The system automatically expands it into the still-image path `https://<go2rtc-url>/api/frame.jpeg?src=h9ccam2_sub`. |
| **go2rtc live URL** | Best left empty. The system automatically builds a live stream link of the form `https://<go2rtc-url>/stream.html?src=h9ccam2_sub`. That player runs **WebRTC** by default (smooth H.265/HEVC support, no stutter) and falls back to MSE/HLS when needed. |
| **Camera RTSP URL (fallback)** | **⚠️ IMPORTANT:** this must be the **RTSP URL taken directly from the camera's IP address** (for example `rtsp://admin:PASS@192.168.2.152:554/Streaming/Channels/201`) — **do not** enter go2rtc's RTSP link. This is the fallback path the system uses to connect straight to the camera for a snapshot when go2rtc fails. |
| **Live Mode** | Choose **Automatic: go2rtc iframe** for the smoothest result. If your HEVC/H.265 camera still shows a black screen in older browsers, switch to **Snapshot refresh**. |
| **Storage & recording** | Tick **Save images/video on the VPS** or **Record and upload video** (via Teldrive) as needed. |
| **Recording duration** | How long to record when an incident is detected (**10 to 30 seconds** is usually sensible). |
| **Cooldown before the next recording** | A cooldown in seconds that prevents repeated recordings of the same incident (**300 seconds — 5 minutes** is a good default). |

---

## Detailed Usage Guide

1. **Start monitoring**: On the Dashboard or a camera detail page, click **Start** in the top right to begin the YOLO person-detection monitoring loop.
2. **Watch the status**: The dashboard shows charts and system resources in real time.
3. **Person detection & verification**:
   * When YOLO detects a person in frame, it triggers a snapshot capture from go2rtc.
   * The snapshot is sent to AI Vision for behavioural analysis.
   * If the AI confirms an `EMERGENCY` (a fall, an unconscious person, an unexpected intrusion, and so on):
     * An alert image and a description of the event are sent to your Telegram immediately.
     * A short video recording is triggered automatically (if that option is enabled).
     * The event is pushed into the **Events** timeline on the web UI.
   * If the AI reports `SAFE` (someone simply walking past, cleaning, and so on), the event is recorded in the events list as safe and no Telegram alert is sent, which avoids spam.
4. **Review the evidence**:
   * **Events**: Open the **Events** tab to see the incident timeline, filter by camera or by AI status, and click a thumbnail to view the full-size original image.
   * **Recordings**: Open the **Recordings** tab to review incident video. You can switch between grid and list layouts, change the column count (2 or 3), toggle thumbnails, and toggle **Play Cover** mode (which plays video in a smooth popup or embeds it directly in the page). You can also copy a video link quickly with the **Copy Link** button to download it.

---

## Running in the Background (Systemd Service on Linux)

To have the application start with the VPS and keep running in the background, configure a systemd service:

1. Create the service file:
   ```bash
   sudo nano /etc/systemd/system/fall-detection.service
   ```
2. Paste the following configuration into the file:
   ```ini
   [Unit]
   Description=Fall Detection Web Service
   After=network-online.target

   [Service]
   User=root
   WorkingDirectory=/opt/my_hass_addon_public/fall_detection_web
   ExecStart=/opt/my_hass_addon_public/fall_detection_web/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8090 --no-access-log
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
3. Save the file (`Ctrl+O`, `Enter`, `Ctrl+X`), then run the following to enable the service:
   ```bash
   # Reload the service configuration
   sudo systemctl daemon-reload

   # Enable start-on-boot and start the service immediately
   sudo systemctl enable --now fall-detection

   # Check that the service is running
   sudo systemctl status fall-detection

   # Follow the logs in real time
   journalctl -u fall-detection -f
   ```

---

## Teldrive Installation & Configuration Guide (Incident Video & Image Storage)

To store evidence clips and incident images on Telegram with unlimited capacity, install the customised **Teldrive** build that supports a **permanent static API key**, from the repository [minhhungtsbd/teldrive](https://github.com/minhhungtsbd/teldrive).

### 1. Installing and building Teldrive on a VPS

#### Option 1: Build with Docker (recommended — clean and fast)
If Docker is already installed on the VPS, you can build a standalone executable without installing Go on the host:
```bash
# 1. Move into a working directory and clone the source
cd ~/
git clone https://github.com/minhhungtsbd/teldrive.git teldrive-src
cd teldrive-src

# 2. Run a container to generate the UI, generate the API and build the server
docker run --rm -v "$PWD":/app -w /app golang:alpine sh -c "
  apk add --no-cache git curl bash unzip &&
  go install github.com/go-task/task/v3/cmd/task@latest &&
  /go/bin/task gen &&
  /go/bin/task ui &&
  CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o bin/teldrive
"
```
When it finishes, the compiled executable is at `~/teldrive-src/bin/teldrive`.

#### Option 2: Build directly with Go (requires Go >= 1.22 on the system)
```bash
cd ~/teldrive-src
# Generate the auto-generated sources
go generate ./...
# Build the server
go build -o bin/teldrive main.go
```

---

### 2. Setting up the database and configuring Teldrive

1. **Prepare a PostgreSQL database**: Teldrive needs PostgreSQL to store the virtual directory structure. Run the following SQL to initialise it:
   ```sql
   CREATE DATABASE teldrive_db;
   CREATE USER teldrive_user WITH PASSWORD 'YourPassword';
   GRANT ALL PRIVILEGES ON DATABASE teldrive_db TO teldrive_user;
   ```

2. **Configure `config.toml`**:
   Create the `/etc/teldrive` directory and the configuration file:
   ```bash
   sudo mkdir -p /etc/teldrive
   sudo nano /etc/teldrive/config.toml
   ```
   Paste the sample configuration below (take care to fill in the correct Postgres connection details and to **set the permanent static API key**):
   ```toml
   [server]
   port = 8080
   graceful-shutdown = '10s'

   [db]
   # Enter your PostgreSQL database connection string
   data-source = 'postgres://teldrive_user:YourPassword@127.0.0.1:5432/teldrive_db?sslmode=disable'

   [jwt]
   secret = 'enter-your-own-random-jwt-secret-string'
   session-time = '30d'
   allowed-users = ["your_telegram_username"] # Whitelist of Telegram usernames allowed to sign in
   
   # Permanent static API key configuration
   api-key = 'fall_detection_web_secure_api_key_2026' # Enter your own secret key here
   api-key-user = 0 # Telegram ID owning the session (leave 0 to let the system pick up the first session automatically)

   [tg]
   app-id = 2496 # Telegram App ID from my.telegram.org
   app-hash = '8da85b0d5bfe62527e5b244c209159c3' # Telegram App Hash
   auto-channel-create = true
   channel-limit = 500000

   [tg.session]
   type = 'postgres'
   key = 'session'
   ```

3. **Run the Teldrive service in the background with systemd**:
   Create the service file:
   ```bash
   sudo nano /etc/systemd/system/teldrive.service
   ```
   Paste the following configuration:
   ```ini
   [Unit]
   Description=Teldrive Telegram VFS Service
   After=network.target

   [Service]
   ExecStart=/usr/bin/teldrive run --config /etc/teldrive/config.toml
   Restart=always
   RestartSec=5
   WorkingDirectory=/etc/teldrive

   [Install]
   WantedBy=multi-user.target
   ```
   Then move the executable into place and enable the service:
   ```bash
   sudo cp ~/teldrive-src/bin/teldrive /usr/bin/teldrive
   sudo chmod +x /usr/bin/teldrive
   sudo systemctl daemon-reload
   sudo systemctl enable --now teldrive
   sudo systemctl status teldrive
   ```

---

### 3. Using the static API key to upload video and images

In this customised distribution you can authenticate with the permanent static API key in three flexible ways:
1. **Authorization header:** send `Authorization: Bearer <static-api-key>` (this is what Fall Detection Web uses automatically when you fill in the **Teldrive token** field).
2. **X-API-Key header:** send `X-API-Key: <static-api-key>`.
3. **URL parameter:** append `?token=<static-api-key>` to the URL.

#### 🔗 Embedding images and video directly in a page (bypass)
When you need to embed incident snapshots or stream incident video from Teldrive on another web page, just append the `?token=` parameter to the file path:
```html
<!-- Embed an incident thumbnail -->
<img src="http://<VPS-IP>:8080/api/files/<FILE_ID>/thumb.jpg?token=fall_detection_web_secure_api_key_2026" />

<!-- Play an incident video -->
<video controls>
  <source src="http://<VPS-IP>:8080/api/files/<FILE_ID>/clip.mp4?token=fall_detection_web_secure_api_key_2026" type="video/mp4">
</video>
```

#### 🔑 Signing in quickly to the Teldrive web UI
To reach Teldrive's file-management web UI in a browser without going through Telegram OTP authentication, open:
```text
http://<VPS-IP>:8080/api/auth/static?key=fall_detection_web_secure_api_key_2026
```
The system validates the API key, sets a session cookie, and redirects you straight into the file manager.

---

## Redis Server Installation Guide

To use the Redis caching feature that optimises the site, you need a Redis server installed on the system:

### 1. On Linux (Ubuntu / Debian VPS)

Run the following in a terminal to install and enable Redis:
```bash
# Install the Redis server
sudo apt update
sudo apt install -y redis-server

# Enable it to run in the background with the system
sudo systemctl enable --now redis-server

# Check that it is running
sudo systemctl status redis-server
```

### 2. On Windows
You can install Redis on Windows through WSL, or run it quickly with Docker:
```bash
docker run -d --name redis-cache -p 6379:6379 redis:alpine
```

### 3. Fail-safe fallback
The application is designed to be very safe here. If the Redis server stops or was never configured, the web app **skips the cache automatically** and queries the SQLite database or disk directly, without crashing or interrupting the monitoring loop.

---

## Important Notes

1. **Security**: Always change the default `admin/admin` password immediately after a successful installation. If you expose the application to the internet beyond your LAN, put SSL (HTTPS) in front of it with a reverse proxy (Nginx, Caddy, or a Cloudflare Tunnel) so the JWT cookie is encrypted in transit.
2. **VPS CPU**: 
   * Lean on go2rtc as much as possible for streaming and snapshots. 
   * Video recording is already optimised to record natively (copy codec), which keeps heavy transcoding off the VPS CPU.
3. **Camera stability**: Image quality and latency depend heavily on your camera's local network quality and your go2rtc configuration. Prefer a wired LAN connection for cameras over an unreliable Wi-Fi link.
