#!/usr/bin/env python3
"""TCP readiness probe for DSM-11 terminals.

Opens a connection to the VH listener and waits for the "Username: "
login prompt. Exits 0 when the prompt is seen within the deadline,
non-zero otherwise. VH lines are configured for modem hangup so the
slot is released as soon as we close the socket.
"""

import socket
import sys
import time

HOST = "127.0.0.1"
PORT = 1337
TIMEOUT = 5.0
NEEDLE = b"Username: "

deadline = time.monotonic() + TIMEOUT
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.settimeout(TIMEOUT)
    s.connect((HOST, PORT))
    buf = b""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            sys.exit(1)
        s.settimeout(remaining)
        try:
            chunk = s.recv(1024)
        except socket.timeout:
            sys.exit(1)
        if not chunk:
            sys.exit(1)
        buf += chunk
        if NEEDLE in buf:
            sys.exit(0)
        if len(buf) > 8192:
            sys.exit(1)
except OSError:
    sys.exit(1)
finally:
    try:
        s.close()
    except OSError:
        pass
