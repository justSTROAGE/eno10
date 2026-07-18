#!/bin/sh
set -e
set -x

chown -R service:service "/service/"
chown -R service:service "/maildir/"

cron

exec su -s /bin/sh -c '/service/inboxd --db /maildir' service
