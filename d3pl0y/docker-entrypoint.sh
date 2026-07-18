#!/bin/sh
set -e

d3pl0y-reaper &

exec "$@"
