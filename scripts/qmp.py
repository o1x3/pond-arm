#!/usr/bin/env python3
"""Tiny QMP client for the QEMU test: screenshots and typing.
  qmp.py SOCKET shot FILE.png
  qmp.py SOCKET type 'text\\n'
  qmp.py SOCKET quit
"""
import json
import socket
import sys
import time

KEYS = {" ": "spc", "\n": "ret", "-": "minus", "_": "shift-minus", ".": "dot", "/": "slash"}


def connect(path):
    sock = socket.socket(socket.AF_UNIX)
    sock.connect(path)
    stream = sock.makefile("rw")
    stream.readline()
    return stream


def call(stream, command, **arguments):
    stream.write(json.dumps({"execute": command, "arguments": arguments}) + "\n")
    stream.flush()
    while True:
        reply = json.loads(stream.readline())
        if "return" in reply or "error" in reply:
            if "error" in reply:
                sys.exit(f"qmp: {reply['error']}")
            return reply["return"]


def main():
    path, action = sys.argv[1], sys.argv[2]
    stream = connect(path)
    call(stream, "qmp_capabilities")
    if action == "shot":
        call(stream, "screendump", filename=sys.argv[3], format="png")
    elif action == "type":
        for char in sys.argv[3].encode().decode("unicode_escape"):
            key = KEYS.get(char) or (f"shift-{char.lower()}" if char.isupper() else char)
            call(stream, "human-monitor-command", **{"command-line": f"sendkey {key}"})
            time.sleep(0.05)
    elif action == "quit":
        call(stream, "quit")


if __name__ == "__main__":
    main()
