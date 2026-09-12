# Home Assistant Add-ons

This repository contains public Home Assistant add-ons.

## Add-ons

| Add-on | Description |
| --- | --- |
| [Simple AI Vision](./simple_ai_vision) | Lightweight add-on that analyses camera snapshots with an AI Vision API, matches keywords and sends Telegram alerts. |
| [Fall Detection Web](./fall_detection_web) | Standalone web UI for running YOLO person detection, AI fall verification and Telegram alerts on a VPS or server. |

## Simple AI Vision

Main processing flow:

```text
Home Assistant motion/sensor trigger
-> POST /analyze
-> go2rtc or Home Assistant Generic Camera snapshot
-> OpenAI-compatible Vision API
-> keyword matching
-> Telegram sendPhoto
-> event log and optional MQTT publish
```

By default this add-on does not poll cameras on its own. A Home Assistant automation decides when `/analyze` should be called.

Key features:

- Manage cameras from the web UI.
- Enable or disable Monitor per camera.
- Snapshot support from a go2rtc `src` or a Home Assistant camera entity.
- go2rtc takes priority when a camera has both `src` and `entity_id`.
- Load camera entities, go2rtc streams and motion/sensor triggers from Home Assistant.
- Generate a sample YAML automation for the selected trigger.
- Live tab for viewing a camera via entity, go2rtc, or both.
- Events tab for reviewing the analyze log.
- Optional MQTT publishing of event JSON.
- Test AI API, Test Telegram, and per-camera test actions.

Full documentation: [simple_ai_vision/README.md](./simple_ai_vision/README.md)

## Installing the Repository

1. Open Home Assistant.
2. Go to **Settings** -> **Add-ons** -> **Add-on Store**.
3. Click the **...** menu in the top right.
4. Select **Repositories**.
5. Add the repository URL:
6. Click **Add**.
7. Find the **Simple AI Vision** add-on in the Add-on Store.
8. Install it, then click **Start**.
9. Open **Open Web UI** to configure it.

## Requirements

- Home Assistant OS or Supervised, with the Add-on Store available.
- go2rtc if you want snapshots or video taken directly from a stream.
- A Home Assistant camera entity if you want to use Generic Camera snapshots.
- An API key from an OpenAI-compatible provider with vision support.
- A Telegram bot token and chat ID.
- An MQTT broker if you enable the MQTT publish option.

## Calling It From a Home Assistant Automation

Add a `rest_command`:

```yaml
rest_command:
  simple_ai_vision_analyze:
    url: "http://127.0.0.1:8000/analyze"
    method: post
    content_type: "application/json"
    payload: "{{ payload }}"
```

Example using a go2rtc source:

```yaml
automation:
  - alias: "Simple AI Vision - Bếp"
    trigger:
      - platform: state
        entity_id: binary_sensor.motion_bep
        to: "on"
    action:
      - service: rest_command.simple_ai_vision_analyze
        data:
          payload: '{"camera":"bep"}'
    mode: single
```

Example using a Home Assistant camera entity:

```yaml
automation:
  - alias: "Simple AI Vision - Bếp Entity"
    trigger:
      - platform: state
        entity_id: binary_sensor.motion_bep
        to: "on"
    action:
      - service: rest_command.simple_ai_vision_analyze
        data:
          payload: '{"entity_id":"camera.camera_bep_go2rtc"}'
    mode: single
```

If `127.0.0.1:8000` is not reachable from Home Assistant, use the IP or hostname of the machine running the add-on:

```text
http://<home-assistant-ip>:8000/analyze
```
