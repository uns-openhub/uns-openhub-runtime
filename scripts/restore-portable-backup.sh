#!/bin/sh
# Run from the installed single-controller Runtime directory.
set -eu
if [ "$#" -ne 1 ]; then
  echo "Usage: scripts/restore-portable-backup.sh openhub-<archive>.zip" >&2
  exit 2
fi
engine="${UNS_CONTAINER_ENGINE:-}"
if [ -z "$engine" ]; then
  if command -v podman >/dev/null; then engine=podman; else engine=docker; fi
fi
case "$engine" in docker|podman) ;; *) echo "Select docker or podman." >&2; exit 2;; esac
service=uns-openhub-controller
# podman-compose accepts no service argument for ps. Inspect the active
# project's containers so other Runtime installations remain independent.
ids=$("$engine" compose ps -q)
for id in $ids; do
  owner=$("$engine" inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$id")
  if [ "$owner" = "$service" ] && [ "$("$engine" inspect --format '{{.State.Running}}' "$id")" = true ]; then
    echo "Stop the target Controller before full restore. Keep PostgreSQL running." >&2
    exit 1
  fi
done
"$engine" compose run --rm --no-deps -e UNS_PORTABLE_OFFLINE=1 --entrypoint sh "$service" -ec '
  helper=/opt/uns-runtime-tools/uns-backup-helper
  [ -x "$helper" ] || helper=/usr/local/bin/uns-backup-helper
  exec "$helper" portable restore "$1"
' sh "$1"
