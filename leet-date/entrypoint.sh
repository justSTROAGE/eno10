#!/bin/sh
set -e

until pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; do
    echo "waiting for postgres..."
    sleep 1
done

exec /service/server
