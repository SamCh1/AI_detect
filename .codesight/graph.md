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
