#!/bin/sh
# Run from the installed target Runtime directory.
set -eu
case "$#:${4:-}" in
  1:|4:--plan|5:--confirm) ;;
  *)
    echo "Usage: scripts/restore-portable-backup.sh openhub-<archive>.zip" >&2
    echo "Cluster preview: scripts/restore-portable-backup.sh <archive> <manifest-sha256> <controller-service> --plan" >&2
    echo "Cluster restore: scripts/restore-portable-backup.sh <archive> <manifest-sha256> <controller-service> --confirm <plan-sha256>" >&2
    exit 2;;
esac
engine="${UNS_CONTAINER_ENGINE:-}"
if [ -z "$engine" ]; then
  if command -v podman >/dev/null; then engine=podman; else engine=docker; fi
fi
case "$engine" in docker|podman) ;; *) echo "Select docker or podman." >&2; exit 2;; esac
service=uns-openhub-controller
operation=restore
if [ "$#" -gt 1 ]; then
  service=${UNS_RESTORE_CONTROLLER_SERVICE:-$3}
  case "$service" in ""|-*|*[!a-zA-Z0-9_.-]*) echo "Invalid controller service." >&2; exit 2;; esac
  operation=cluster-restore-member
fi
# podman-compose accepts no service argument for ps. Inspect the active
# project's containers so other Runtime installations remain independent.
ids=$("$engine" compose ps -q)
for id in $ids; do
  owner=$("$engine" inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$id")
  case "$owner" in
    "$service"|controller-[0-9]*|uns-openhub-controller) ;;
    *) continue;;
  esac
  if [ "$("$engine" inspect --format '{{.State.Running}}' "$id")" = true ]; then
    echo "Stop the target Controller before full restore. Keep PostgreSQL running." >&2
    exit 1
  fi
done
"$engine" compose run --rm --no-deps -e UNS_PORTABLE_OFFLINE=1 --entrypoint sh "$service" -ec '
  helper=/opt/uns-runtime-tools/uns-backup-helper
  [ -x "$helper" ] || helper=/usr/local/bin/uns-backup-helper
  exec "$helper" portable "$@"
' sh "$operation" "$@"
