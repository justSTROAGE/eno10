#!/bin/sh
set -u

MAX_AGE_MIN="${CLEANUP_MAX_AGE_MIN:-15}"
INTERVAL_SEC="${CLEANUP_INTERVAL_SEC:-120}"
UPLOAD_DIR="${UPLOAD_DIR:-/data/uploads}"

log() { echo "[$(date -u +%FT%TZ)] cleanup: $*"; }

while true; do
    log "deleting users older than ${MAX_AGE_MIN}m"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c \
        "DELETE FROM users WHERE created_at < NOW() - (INTERVAL '1 minute' * ${MAX_AGE_MIN});" \
        || log "psql delete failed"

    find "$UPLOAD_DIR" -type f -mmin "+${MAX_AGE_MIN}" -exec rm -f {} + 2>/dev/null
    find "$UPLOAD_DIR" -mindepth 1 -type d -exec rmdir {} + 2>/dev/null

    log "done, sleeping ${INTERVAL_SEC}s"
    sleep "$INTERVAL_SEC"
done
