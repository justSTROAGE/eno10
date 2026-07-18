#!/bin/sh
set -u

MAILDIR="${1:-/maildir}"
USERS_DIR="$MAILDIR/users"

MAX_AGE_MIN=12

[ -d "$USERS_DIR" ] || exit 0

find "$USERS_DIR" -mindepth 1 -maxdepth 1 -type d -mmin "+$MAX_AGE_MIN" \
	-exec rm -rf {} + 2>/dev/null || true
