# Simple AI Vision

Simple AI Vision is a lightweight Home Assistant add-on that analyses camera snapshots with an AI Vision API, matches keywords and sends Telegram alerts.

Main flow:

```text
Frigate person event via MQTT
-> POST /analyze
-> fetch a snapshot from go2rtc or the Frigate latest frame
-> OpenAI-compatible Vision API
-> keyword matching
-> Telegram sendPhoto
-> write the event to the log
```

By default the add-on does not poll cameras on its own. A Home Assistant automation decides when `/analyze` should be called.

## Features

- Accepts triggers via `POST /analyze`.
- Snapshot support from go2rtc `/api/frame.jpeg?src={camera}`.
- Snapshot fallback from the Frigate API `/api/<camera>/latest.jpg`.
- Sends images as `data:image/jpeg;base64,...` to an OpenAI-compatible `chat/completions` endpoint.
- Supports OpenAI, OpenRouter, 9Router and Gemini through an OpenAI-compatible gateway.
- Matches keywords or regular expressions, case-insensitively.
- Sends to Telegram using the Bot API `sendPhoto` method.
- Separate test buttons for the AI API and for Telegram.
- Cameras tab for managing cameras and toggling Monitor per camera.
- Loads streams directly from go2rtc.
- Live tab for viewing a camera via backend snapshot refresh.
- Events tab for reviewing analyze results: `sent`, `no_match`, `telegram_error`, and network/config errors.
- Configuration stored at `/data/simple_ai_vision_config.json`.
- Event log stored at `/data/simple_ai_vision_events.jsonl`.
- No database, no local object detection, no RTSP decoding, no ffmpeg processing.

## Installation

1. Open Home Assistant.
2. Go to **Settings** -> **Add-ons** -> **Add-on Store**.
3. Click the **...** menu -> **Repositories**.
4. Add the repository:

```text
https://github.com/minhhungtsbd/my_hass_addon_public
```

5. Install the **Simple AI Vision** add-on.
6. Click **Start**.
7. Click **Open Web UI** to configure it.

## Core Settings

The main fields:

| Option | Description |
| --- | --- |
| `go2rtc_url` | go2rtc base URL, for example `http://homeassistant.local:1984` |
| `go2rtc_host_url` | go2rtc URL reachable from the browser, for example `http://192.168.1.101:1984` |
| `frigate_url` | Internal Frigate API base URL, for example `http://ccab4aaf-frigate:5000` |
| `frigate_host_url` | Frigate URL reachable from the browser, for example `http://192.168.1.101:5000` |
| `ai_api_key` | API key for the OpenAI-compatible provider |
| `ai_base_url` | API base URL, for example `https://api.openai.com/v1` or `https://9router.example/v1` |
| `ai_model` | The vision model to use |
| `telegram_bot_token` | Telegram bot token |
| `telegram_chat_id` | Chat ID that receives the alerts |
| `prompt` | Default prompt sent to the AI when a camera has no Prompt Profile selected |
| `keyword_match` | One keyword or regular expression per line |
| `ai_timeout` | AI API timeout, in seconds |
| `snapshot_timeout` | Snapshot timeout, in seconds |
| `telegram_timeout` | Telegram API timeout, in seconds |

A timeout is not a schedule. It is only the maximum time to wait for an individual request.

Suggested prompt:

```text
You are an indoor camera image analysis system.

If you see a person in the image, reply only with:
ALERT_PERSON: a short description in at most 20 words.

If you do not see a person, reply only with:
NORMAL

Do not explain.
Do not give instructions.
Do not write code.
Do not mention Telegram.
```

Suggested keywords:

```text
ALERT_PERSON
fire
smoke
cháy
```

## Cameras

Each camera has the following fields:

| Field | Description |
| --- | --- |
| `Monitor` | Enable or disable monitoring. When disabled, `/analyze` returns `skipped: true` and does not call the AI |
| `Name` | Display name |
| `go2rtc src` | go2rtc stream name, for example `bep` |
| `Prompt` | A Prompt Profile specific to this camera; leave empty to use the Default Prompt |

Buttons in the Cameras tab:

- `Load go2rtc`: load streams from `go2rtc_url/api/streams`.
- `Add Stream`: add the selected go2rtc stream.
- `Snapshot`: view a snapshot image.
- `Live`: view a backend snapshot refresh.
- `Test`: call `/analyze` manually.
- `Save Cameras`: save the cameras.

Cameras are configured with `go2rtc src`. With the Frigate fallback, `go2rtc src` is the camera or stream name in Frigate, for example `bep`.

## Prompt Profiles

The **Prompt Profiles** tab lists the saved prompts. Use `Add Prompt` or `Edit` to open a modal for creating or editing a titled prompt, for example `Cong`, `Bep`, `Thu cung`.

When adding a camera, select the matching prompt title in the `Prompt` column. Several cameras can share one Prompt Profile. If a camera has no profile selected, the add-on uses the `Default Prompt` from Core Settings.

## Home Assistant Automation

The add-on does not run in the background on its own. To automate it, a Home Assistant automation needs to call `/analyze`.

Example `rest_command`:

```yaml
rest_command:
  simple_ai_vision_analyze:
    url: "http://127.0.0.1:8000/analyze"
    method: post
    content_type: "application/json"
    payload: "{{ payload }}"
```

Example automation shared by every Frigate camera:

```yaml
automation:
  - alias: "Simple AI Vision - Frigate person"
    trigger:
      - platform: mqtt
        topic: frigate/events
    condition:
      - condition: template
        value_template: >
          {{ trigger.payload_json["after"]["label"] == "person"
             and trigger.payload_json["type"] in ["new", "update"] }}
    action:
      - service: rest_command.simple_ai_vision_analyze
        data:
          payload: >
            {"camera":"{{ trigger.payload_json['after']['camera'] }}"}
    mode: single
```

If you have configured a camera list in the Cameras tab, `/analyze` only handles cameras that appear in that list. Cameras that have not been added to Simple AI Vision are skipped.

If `127.0.0.1:8000` is not reachable from Home Assistant, use the IP or hostname of the machine running the add-on:

```text
http://<home-assistant-ip>:8000/analyze
```

## API

Web UI:

```http
GET /
```

Configuration and tests:

```http
GET /api/config
POST /api/config
POST /api/test-ai
POST /api/test-telegram
```

Camera helpers:

```http
GET /api/camera/frame?camera=bep
GET /api/go2rtc/streams
GET /api/events
```

Analyze:

```http
POST /analyze
Content-Type: application/json

{
  "camera": "bep"
}
```

Response on a match:

```json
{
  "success": true,
  "matched": true,
  "matched_keyword": "ALERT_PERSON",
  "analysis": "ALERT_PERSON: A person is sitting at the desk."
}
```

Response with no match:

```json
{
  "success": true,
  "matched": false,
  "matched_keyword": "",
  "analysis": "NORMAL"
}
```

Response for a camera with Monitor disabled:

```json
{
  "success": true,
  "skipped": true,
  "reason": "camera disabled",
  "camera": "bep"
}
```

## Live Tab

The Live tab uses a snapshot refresh through the Simple AI Vision backend. This works with internal Frigate add-on hostnames such as `ccab4aaf-frigate`.

In the Live tab you can change `View Mode` to try different access paths:

- `Backend snapshot`: the browser calls Simple AI Vision, and the add-on fetches the snapshot from go2rtc or Frigate itself.
- `go2rtc URL stream`: the browser tries to open the stream from `go2rtc_url`.
- `go2rtc Host stream`: the browser tries to open the stream from `go2rtc_host_url`.
- `Frigate URL latest image`: the browser tries to fetch the latest image from `frigate_url`.
- `Frigate Host latest image`: the browser tries to fetch the latest image from `frigate_host_url`.

## Events Tab

The Events tab reads this file:

```text
/data/simple_ai_vision_events.jsonl
```

Common statuses:

| Status | Meaning |
| --- | --- |
| `sent` | A keyword matched and the Telegram message was sent successfully |
| `no_match` | The AI replied but nothing matched a keyword |
| `telegram_error` | A keyword matched but Telegram returned an error |
| `config_error` | Configuration is missing or wrong |
| `timeout` | Network timeout |
| `upstream_error` | The upstream API returned an HTTP error |
| `network_error` | Network error |
| `internal_error` | Unexpected error |

## Telegram

The add-on sends images using the Telegram Bot API `sendPhoto` method.

Caption:

```text
Camera: <camera>

<AI analysis result>
```

The `Test Telegram` button sends a text message so you can verify the token and chat ID before testing a camera.

## Quick Check

```bash
curl -X POST http://<home-assistant-ip>:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{"camera":"bep"}'
```

## Frigate Add-on Streams

Simple AI Vision can discover camera names from the Frigate add-on when loading go2rtc streams. It tries the configured `go2rtc_url` first, then Frigate built-in go2rtc on port `1984`, then Frigate API on port `5000`.

Use the optional `frigate_url` setting when auto-discovery cannot find the Frigate add-on, for example:

```text
http://ccab4aaf-frigate:5000
```

Snapshot analysis prefers go2rtc:

```text
{go2rtc_url}/api/frame.jpeg?src=<camera>
```

If Frigate's go2rtc API port `1984` is not reachable, Simple AI Vision falls back to the Frigate API latest frame endpoint:

```text
{frigate_url}/api/<camera>/latest.jpg
```

For the Home Assistant Frigate add-on, use:

```text
frigate_url = http://ccab4aaf-frigate:5000
```

The Frigate `8555` port is WebRTC and is not used for snapshot analysis.

The **Live** button and **Live** tab use a lightweight refreshed snapshot view through Simple AI Vision, which works with the Frigate API fallback and internal add-on hostnames.

To trigger analysis from Frigate person detection, enable MQTT in Frigate and use a Home Assistant automation on `frigate/events`:

```yaml
trigger:
  - platform: mqtt
    topic: frigate/events
condition:
  - condition: template
    value_template: >
      {{ trigger.payload_json["after"]["label"] == "person"
         and trigger.payload_json["type"] in ["new", "update"] }}
action:
  - service: rest_command.simple_ai_vision_analyze
    data:
      payload: >
        {"camera":"{{ trigger.payload_json['after']['camera'] }}"}
```
