#!/usr/bin/env python3
"""Persistent SimH process with TCP stdio proxy.

Forks `pdp11 $SIM_INI` onto a PTY and exposes its console on $SIM_PORT.
Single client at a time; a new connection kicks the previous one. PTY
output is also mirrored to container stderr so `docker logs` still shows
SimH activity.
"""

import errno
import fcntl
import os
import pty
import select
import signal
import socket
import sys

PORT = int(os.environ["SIM_PORT"])
INI = os.environ["SIM_INI"]
LISTEN_ADDR = os.environ.get("SIM_BIND", "0.0.0.0")

PANIC_MARKERS = (b"XDT>", b"CPU error through vector", b"Trap stack")

pid, master_fd = pty.fork()
if pid == 0:
    os.execvp("pdp11", ["pdp11", INI])

flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((LISTEN_ADDR, PORT))
srv.listen(1)
srv.setblocking(False)

clients: list[socket.socket] = []

panic = False
console_tail = b""

stopping = False
def handle_term(_signum, _frame):
    global stopping
    stopping = True
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass

signal.signal(signal.SIGTERM, handle_term)
signal.signal(signal.SIGINT, handle_term)

TN_IAC, TN_SB, TN_SE = 255, 250, 240
TELNET_PREAMBLE = bytes([255, 251, 3, 255, 251, 1])
tn_pending = bytearray()

def telnet_clean(data):
    global tn_pending
    buf = bytes(tn_pending) + data
    tn_pending = bytearray()
    out = bytearray()
    i, n = 0, len(buf)
    while i < n:
        b = buf[i]
        if b == TN_IAC:
            if i + 1 >= n:
                tn_pending += buf[i:]; break
            c = buf[i + 1]
            if c == TN_IAC:
                out.append(TN_IAC); i += 2; continue
            if c == TN_SB:
                j = i + 2
                while j + 1 < n and not (buf[j] == TN_IAC and buf[j + 1] == TN_SE):
                    j += 1
                if j + 1 >= n:
                    tn_pending += buf[i:]; break
                i = j + 2; continue
            if 251 <= c <= 254:
                if i + 2 >= n:
                    tn_pending += buf[i:]; break
                i += 3; continue
            i += 2; continue
        out.append(b); i += 1
    return bytes(out).replace(b"\r\n", b"\r").replace(b"\r\x00", b"\r")

while True:
    rfds = [srv.fileno(), master_fd] + [c.fileno() for c in clients]
    try:
        r, _, _ = select.select(rfds, [], [], 1.0)
    except OSError as e:
        if e.errno == errno.EINTR:
            continue
        raise

    if srv.fileno() in r:
        try:
            cli, _ = srv.accept()
        except BlockingIOError:
            cli = None
        if cli is not None:
            cli.setblocking(False)
            for c in clients:
                try: c.close()
                except OSError: pass
            clients = [cli]
            tn_pending = bytearray()
            try: cli.sendall(TELNET_PREAMBLE)
            except OSError: pass

    if master_fd in r:
        try:
            data = os.read(master_fd, 4096)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                data = b""
            else:
                data = b""
                break
        if data:
            try:
                sys.stderr.buffer.write(data)
                sys.stderr.flush()
            except OSError:
                pass
            for c in list(clients):
                try:
                    c.sendall(data)
                except OSError:
                    clients.remove(c)
                    try: c.close()
                    except OSError: pass
            console_tail = (console_tail + data)[-1024:]
            hit = next((m for m in PANIC_MARKERS if m in console_tail), None)
            if hit is not None and not stopping:
                sys.stderr.write(
                    f"\n[sim-runner] FATAL: guest panic detected "
                    f"({hit.decode()!r}); restarting node\n"
                )
                sys.stderr.flush()
                panic = True
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
                break
        elif master_fd in r:
            break

    for c in list(clients):
        if c.fileno() in r:
            try:
                data = c.recv(4096)
            except (OSError, BlockingIOError):
                continue
            if not data:
                clients.remove(c)
                try: c.close()
                except OSError: pass
                continue
            try:
                os.write(master_fd, telnet_clean(data))
            except OSError:
                pass

    try:
        rpid, _ = os.waitpid(pid, os.WNOHANG)
        if rpid != 0:
            break
    except ChildProcessError:
        break

try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass

for c in clients:
    try: c.close()
    except OSError: pass
srv.close()

if panic:
    sys.exit(1)
