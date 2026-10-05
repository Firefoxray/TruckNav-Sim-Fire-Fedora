#!/usr/bin/env python3
import json
import os
import sys
import time
from pathlib import Path

if len(sys.argv) != 2 or sys.argv[1] not in {"ats", "ets2"}:
    raise SystemExit("usage: set-shared-game.py ats|ets2")

game = sys.argv[1]
config_root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
path = config_root / "trucknav-linux" / "shared-settings.json"
path.parent.mkdir(parents=True, exist_ok=True)

try:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        payload = {}
except (OSError, json.JSONDecodeError):
    payload = {}

settings = payload.get("settings")
if not isinstance(settings, dict):
    settings = {}

settings["selectedGame"] = game
payload["settings"] = settings
payload["revision"] = int(time.time() * 1000)
payload["updatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

tmp = path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
tmp.replace(path)

print(f"TruckNav shared game: {game}")
