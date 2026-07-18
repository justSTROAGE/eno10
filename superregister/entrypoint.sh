#!/bin/sh
set -e
set -x

# Chown the mounted data volume
chown -R service:service "/data/"

# Launch our compiled service natively as user 'service'
chmod +x ./SuperRegister
exec su -s /bin/sh service -c "./SuperRegister"
