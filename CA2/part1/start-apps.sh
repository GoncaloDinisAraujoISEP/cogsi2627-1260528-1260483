#!/usr/bin/env bash
# Runs on every `vagrant up`/`reload`, after /h2-data is mounted, so H2 never writes
# to the VM disk underneath the mount point.
set -euo pipefail
if [ "$START_APPS" = "true" ]; then
  systemctl restart bookstore chat-server
  systemctl --no-pager --lines=0 status bookstore chat-server
else
  echo ">> START_APPS=false, apps not started"
fi