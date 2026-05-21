#!/usr/bin/env python3
"""
Send a JSON command to the running Migs Battle debug server (port 6560).

Usage:
    python3 tools/game_cmd.py '{"action": "state"}'
    python3 tools/game_cmd.py '{"action": "screenshot", "path": "/tmp/game.png"}'
    python3 tools/game_cmd.py '{"action": "click", "x": 640, "y": 360}'
    python3 tools/game_cmd.py '{"action": "right_click", "x": 500, "y": 300}'
    python3 tools/game_cmd.py '{"action": "key", "keycode": 32}'        # Space
    python3 tools/game_cmd.py '{"action": "key", "keycode": 4194305}'   # Escape

Godot 4 KEY_ constants (int values):
    KEY_SPACE   = 32
    KEY_ENTER   = 4194309
    KEY_ESCAPE  = 4194305
    KEY_F5      = 4194376
"""

import socket
import json
import sys
import time

HOST = '127.0.0.1'
PORT = 6560
TIMEOUT = 8.0


def send(cmd: dict) -> dict:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    try:
        s.connect((HOST, PORT))
    except ConnectionRefusedError:
        return {"error": f"Could not connect to {HOST}:{PORT} — is the game running?"}
    msg = json.dumps(cmd) + '\n'
    s.sendall(msg.encode())
    buf = b''
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        try:
            chunk = s.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        buf += chunk
        if b'\n' in buf:
            break
    s.close()
    line = buf.split(b'\n')[0]
    if not line:
        return {"error": "no response"}
    return json.loads(line)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    result = send(json.loads(sys.argv[1]))
    print(json.dumps(result, indent=2))
