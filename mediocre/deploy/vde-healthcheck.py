#!/usr/bin/env python3

import socket
import sys

CTL = "/vde/dsm_switch/ctl"

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    s.connect(CTL)
    s.close()
except OSError as e:
    print(f"vde not ready: {CTL}: {e}", file=sys.stderr)
    sys.exit(1)
