#!/bin/sh
set -e

SOCK=${VDE_SOCK:-/vde/dsm_switch}
PIDFILE=/tmp/vde_switch.pid

vde_switch -d -p "$PIDFILE" -s "$SOCK" -m 700
for _ in $(seq 1 100); do
    [ -s "$PIDFILE" ] && [ -S "$SOCK/ctl" ] && break
    sleep 0.05
done
VDE_PID=$(cat "$PIDFILE")

trap 'kill "$VDE_PID" 2>/dev/null; exit 0' TERM INT
exec tail --pid="$VDE_PID" -f /dev/null
